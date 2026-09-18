# Qwen 3.5 0.8B MLX experiment

This branch uses native MLX Swift on Apple Silicon, without a Python process or local inference server. The UI, tool catalog, action parser, and tool argument validation remain in JuliaKit.

- Model: [mlx-community/Qwen3.5-0.8B-4bit](https://huggingface.co/mlx-community/Qwen3.5-0.8B-4bit), revision `da28692b5f139cb0ec58a356b437486b7dac7462` (Apache-2.0).
- Runtime: [mlx-swift-lm 3.31.3](https://github.com/ml-explore/mlx-swift-lm/tree/3.31.3), MLX Swift 0.31.3, swift-transformers 1.3.0. Resolved transitive dependencies are checked in.
- Model files are checksum-verified and cached under `~/Library/Application Support/Julia/Models/qwen3.5-0.8b-mlx-4bit`. Once downloaded, preparation and inference work offline.
- Text inference ignores the model's vision weights. Thinking is disabled using Qwen's closed think block. Generation uses greedy sampling, a 51,200-token context budget, and at most 768 output tokens.
- Each generation creates fresh attention and recurrent caches. Cancellation is checked between tokens and pending GPU work is synchronized before returning.

Unlike the llama.cpp version, this experiment does **not** constrain token sampling with a JSON grammar. It requests JSON in the system prompt, stops on a valid action, and retains the harness's validation and malformed-output retries. This difference can affect both speed and reliability.

## Reproduce

Use a **Release** build when comparing speed. Use full Xcode with its Metal Toolchain component installed (`xcodebuild -downloadComponent MetalToolchain` if needed). On this machine:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test --package-path Packages/JuliaKit -c release
swift run --package-path Packages/JuliaKit -c release julia-smoke --check-model
swift run --package-path Packages/JuliaKit -c release julia-smoke --benchmark
```

`--check-model` and `--benchmark` do not launch apps, execute tools, or read app data. The short-answer and tool-JSON cases use the real system prompt with a fixed date. The sustained-output case uses a minimal JSON-answer system prompt and asks for an exact paragraph, separating decoding speed from tool selection. Each case has one excluded warmup and three measured generations with fresh caches. `BENCH` JSON lines contain input/output token counts, first-token latency, total generation latency, decode throughput, JSON validity, expected-action correctness, and raw output. Model download/load time is excluded. Normal app traces also record `firstTokenMs`.

The comparison baseline is the Qwen llama.cpp implementation at commit `3963c0e`, with the same benchmark and timing instrumentation added in a temporary detached checkout. Its cached model is Q8_0; this MLX model is 4-bit. Consequently the comparison measures the configurations as used, including quantization and grammar differences, rather than the backend alone. Run sequentially without concurrent builds for representative timings.

## Results — Apple M2 Pro, September 18, 2026

Median of three measured runs per case, after one warmup. Both configurations matched the expected action in all 9 measured samples.

| Case | llama.cpp total | MLX total | Total speedup | llama.cpp first token | MLX first token |
| --- | ---: | ---: | ---: | ---: | ---: |
| Short answer | 361 ms | 328 ms | 1.10× | 225 ms | 303 ms |
| Tool JSON (14 tokens) | 736 ms | 380 ms | 1.94× | 233 ms | 321 ms |
| Sustained answer (126 tokens) | 5,608 ms | 650 ms | 8.63× | 89 ms | 130 ms |

Sustained decode throughput was **22.7 tokens/s for llama.cpp** and **240.8 tokens/s for MLX**. MLX decoded faster, but took longer to produce the first token. These are small synthetic benchmarks, not end-to-end app measurements. The tool-JSON case explicitly supplies the required action; it does not measure autonomous tool selection.

[Raw samples](benchmarks/qwen-mlx-m2-pro.json) include all outputs and correctness flags. [Baseline timing patch](benchmarks/qwen-llama-baseline.patch) applies to `3963c0e`; copy this branch's `Packages/JuliaKit/Sources/JuliaSmoke/ModelBenchmark.swift` into the baseline's same directory, apply the patch, and build Release to reproduce the comparator. Keep stdout and stderr separate when saving benchmark JSON lines.

Validation:

- Release app build passed, including the bundled Metal library; the app was not launched.
- All 16 JuliaKit unit tests passed.
- `--check-model` passed using the cached converted weights and the app's exact inference implementation.
- `--check-opening` **failed on the first case**: for “open the safari app”, the model returned “Done.” without calling the simulated opening tool. Remaining cases were not run after that failure. This branch is a speed experiment, not a claim of reliable tool use.
