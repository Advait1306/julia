#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="${SST_BUILD_ROOT:-/tmp/julia-sst-build}"
cd "$repo_root"
xcodebuild -project julia.xcodeproj -scheme julia -destination 'platform=macOS' \
    -derivedDataPath "$build_root" CODE_SIGNING_ALLOWED=NO build > "$build_root-smoke.log" 2>&1
products="$build_root/Build/Products/Debug"
sdk="$(xcrun --show-sdk-path)"
objects=()
while IFS= read -r object; do
    case "$object" in
        */Julia.o|*/ContentView.o|*/GeneratedAssetSymbols.o) continue ;;
    esac
    objects+=("$object")
done < "$build_root/Build/Intermediates.noindex/julia.build/Debug/julia.build/Objects-normal/arm64/julia.LinkFileList"
xcrun swiftc -parse-as-library -target arm64-apple-macos27.0 \
    -import-objc-header julia/headers/bridging-header.h \
    -I "$products" -I "$products/include" \
    -I "$build_root/SourcePackages/checkouts/FluidAudio/Sources/FastClusterWrapper/include" \
    -I "$build_root/SourcePackages/checkouts/FluidAudio/Sources/MachTaskSelfWrapper/include" \
    tests/SSTSmoke.swift "${objects[@]}" \
    -L "$products" -ltext_processing_rs -lc++ \
    -F "$sdk/System/Library/PrivateFrameworks" -framework MediaRemote -framework IOBluetooth \
    -o "$build_root/sst-smoke"
"$build_root/sst-smoke" "$@"
