import Foundation
import CryptoKit
import llama

/// Ollama's 0.8B blob combines vision and language tensors. llama.cpp's text loader
/// expects a language-only GGUF, four MRoPE sections, and `ssm_dt.bias` names.
/// This copies tensor bytes unchanged into a derived file; the source stays verified
/// against the registry digest. No Python, subprocess, model server, or re-quantization.
enum QwenGGUF {
    static func prepare(_ source: URL) throws -> URL {
        let output = source.deletingLastPathComponent().appendingPathComponent("text-b11026-v3.gguf")
        let receipt = output.appendingPathExtension("json")
        let sourceAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let sourceStamp = "\(sourceAttributes[.size] ?? 0)-\(sourceAttributes[.modificationDate] ?? "")"
        if let saved = try? JSONValue.parse(String(contentsOf: receipt, encoding: .utf8)),
           saved["sourceStamp"].string == sourceStamp,
           let expected = saved["sha256"].string,
           FileManager.default.fileExists(atPath: output.path),
           try hashFile(output) == expected { return output }

        var tensorContext: OpaquePointer?
        let gguf: OpaquePointer? = withUnsafeMutablePointer(to: &tensorContext) {
            gguf_init_from_file(source.path, gguf_init_params(no_alloc: true, ctx: $0))
        }
        guard let gguf, let tensorContext else { throw JuliaError("Could not read Qwen GGUF metadata.") }
        defer { gguf_free(gguf); ggml_free(tensorContext) }
        let archID = gguf_find_key(gguf, "general.architecture")
        guard archID >= 0, gguf_get_kv_type(gguf, archID) == GGUF_TYPE_STRING,
              String(cString: gguf_get_val_str(gguf, archID)) == "qwen35" else { throw JuliaError("Expected qwen35 architecture.") }
        guard let target = gguf_init_empty() else { throw JuliaError("Could not initialize GGUF conversion.") }
        defer { gguf_free(target) }
        gguf_set_kv(target, gguf)
        // Ollama marks recurrent layers with zero KV heads. llama.cpp keeps that
        // information in a separate mask and uses the dense head count globally.
        let headsKey = "qwen35.attention.head_count_kv"
        let headsID = gguf_find_key(gguf, headsKey)
        if headsID >= 0, gguf_get_kv_type(gguf, headsID) == GGUF_TYPE_ARRAY {
            guard gguf_get_arr_type(gguf, headsID) == GGUF_TYPE_UINT32 else { throw JuliaError("Unsupported KV head metadata.") }
            let n = gguf_get_arr_n(gguf, headsID)
            let values = gguf_get_arr_data(gguf, headsID).assumingMemoryBound(to: UInt32.self)
            let heads = Array(UnsafeBufferPointer(start: values, count: n))
            let dense = Set(heads.filter { $0 != 0 })
            guard dense.count == 1, let count = dense.first else { throw JuliaError("Unsupported per-layer KV heads.") }
            gguf_set_val_u32(target, headsKey, count)
            var recurrent = heads.map { UInt8($0 == 0 ? 1 : 0) }
            recurrent.withUnsafeMutableBytes {
                gguf_set_arr_data(target, "qwen35.attention.recurrent_layers", GGUF_TYPE_BOOL, $0.baseAddress, n)
            }
        }
        let ropeKey = "qwen35.rope.dimension_sections"
        let ropeID = gguf_find_key(gguf, ropeKey)
        guard ropeID >= 0, gguf_get_kv_type(gguf, ropeID) == GGUF_TYPE_ARRAY,
              gguf_get_arr_type(gguf, ropeID) == GGUF_TYPE_INT32 || gguf_get_arr_type(gguf, ropeID) == GGUF_TYPE_UINT32 else {
            throw JuliaError("Unsupported Qwen MRoPE metadata.")
        }
        let count = gguf_get_arr_n(gguf, ropeID)
        guard count == 3 || count == 4 else { throw JuliaError("Unsupported Qwen MRoPE section count.") }
        if count == 3 {
            let values = gguf_get_arr_data(gguf, ropeID).assumingMemoryBound(to: Int32.self)
            var sections: [Int32] = [values[0], values[1], values[2], 0]
            sections.withUnsafeMutableBytes { gguf_set_arr_data(target, ropeKey, GGUF_TYPE_INT32, $0.baseAddress, 4) }
        }
        var tensors: [(id: Int64, name: String)] = []
        for id in 0..<gguf_get_n_tensors(gguf) {
            let original = String(cString: gguf_get_tensor_name(gguf, id))
            // Vision and the optional multi-token prediction head are unused by text decoding.
            if original.hasPrefix("v.") || original.hasPrefix("mtp.") { continue }
            guard let tensor = ggml_get_tensor(tensorContext, original) else { throw JuliaError("Missing tensor \(original)") }
            let name = original.hasSuffix(".ssm_dt") ? original + ".bias" : original
            ggml_set_name(tensor, name)
            gguf_add_tensor(target, tensor)
            tensors.append((id, name))
        }
        guard !tensors.isEmpty else { throw JuliaError("No language tensors found.") }
        let staging = output.appendingPathExtension("partial")
        defer { try? FileManager.default.removeItem(at: staging) }
        guard gguf_write_to_file(target, staging.path, true) else { throw JuliaError("Could not write converted model metadata.") }
        let input = try FileHandle(forReadingFrom: source), out = try FileHandle(forWritingTo: staging)
        defer { try? input.close(); try? out.close() }
        let inputDataOffset = gguf_get_data_offset(gguf)
        let outputDataOffset = gguf_get_meta_size(target)
        for (index, entry) in tensors.enumerated() {
            try Task.checkCancellation()
            try input.seek(toOffset: UInt64(inputDataOffset + gguf_get_tensor_offset(gguf, entry.id)))
            try out.seek(toOffset: UInt64(outputDataOffset + gguf_get_tensor_offset(target, Int64(index))))
            var remaining = gguf_get_tensor_size(gguf, entry.id)
            while remaining > 0 {
                try Task.checkCancellation()
                guard let bytes = try input.read(upToCount: min(1024 * 1024, remaining)), !bytes.isEmpty else { throw JuliaError("Truncated model tensor data.") }
                try out.write(contentsOf: bytes); remaining -= bytes.count
            }
        }
        try out.synchronize()
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.moveItem(at: staging, to: output)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
        let data: JSONValue = .object(["sourceStamp": .string(sourceStamp), "sha256": .string(try hashFile(output)),
                                     "tensorCount": .number(Double(tensors.count)), "formatVersion": .number(3)])
        try Data(data.json.utf8).write(to: receipt, options: .atomic)
        return output
    }
    private static func hashFile(_ url: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: url); defer { try? h.close() }
        var hash = SHA256()
        while let bytes = try h.read(upToCount: 1024 * 1024), !bytes.isEmpty {
            try Task.checkCancellation(); hash.update(data: bytes)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
