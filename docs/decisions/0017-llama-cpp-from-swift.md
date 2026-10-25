# ADR 0017: Calling llama.cpp from Swift (P5 step 4)

- **Status:** accepted (15 Oct 2026)
- **Date:** 2026-10-15
- **Deciders:** Moustafa Abbara
- **Stage:** P5

## Context

ADR 0003 chose llama.cpp and left the Swift packaging to be checked at P5, noting that the 2026 releases seemed to have dropped the XCFramework. `ArabiziLLM` (roadmap P5 step 4) must load a GGUF once, decode greedily, stop at the end of turn and give up at a deadline (default 1,500 ms) so the rule fallback (ADR 0016) answers instead. It runs inside an XPC service with **no network entitlement** (P5 step 5), on the 8 GB Air (≤ 1.5 GB engine RSS, docs/MODELS.md). The fine-tuned GGUF files are exported with llama.cpp commit `d81235049` (ADR 0015), the same build as the Mac's Homebrew `llama-server` (0.6.0, build 11429).

## Findings (15 Oct 2026, from the GitHub API and a prototype on the Air)

- **The XCFramework is still published** with every release: `llama-b11429-xcframework.zip` (61,992,495 bytes) in release `b11429`, whose tag is commit `d81235049384534c167caea52b85a694f6103d14`: exactly the commit we export with. GitHub lists its SHA-256 (`e26a6a0a813f5760fe45834ce239d5b525e4e2442d4fd017221d9f0438383174`), which is the checksum SwiftPM needs, and the release has a build attestation. ADR 0003's worry was wrong.
- **llama.cpp's own docs** (`docs/xcframework.md` at that tag) show exactly this use: a SwiftPM `.binaryTarget(url:checksum:)` on the release zip. The repository has no `Package.swift` of its own any more.
- What is inside (from `build-xcframework.sh`): one dynamic `llama.framework` per platform (macOS slice arm64 + x86_64, minimum macOS 13.3) combining libllama, ggml with **Metal (shader library embedded)**, BLAS/Accelerate and mtmd; Swift imports it as `import llama` (the C API of `llama.h`). It does **not** contain llama.cpp's `common` library, so no Jinja chat templates.
- **Prototype** (Swift calling the C API of Homebrew's libllama, same commit; not committed): `llama_model_load_from_file` → `llama_init_from_model` (n_ctx 512) → `llama_tokenize` → `llama_decode` loop with a greedy sampler, stopping at `llama_vocab_is_eog`. Base models, one 11-word public sentence, 3 runs each:

  | Model | Load | First token | ~32 tokens generated | Peak RSS |
  |---|---|---|---|---|
  | Llama 3.2 1B Q4_K_M | 1.0 s | 100–170 ms | 0.70–1.06 s | 0.92 GB |
  | Qwen3-1.7B Q4_K_M | 1.4 s | 150–240 ms | 0.72–1.41 s | 1.21 GB |

  Both fit the 1.5 GB budget. The 1.7B model is close to the 1,500 ms deadline on an 11-word sentence (runs 2–3 were slower than run 1; not investigated), so longer messages will time out unless the deadline grows with the input. One sentence is not a measurement: P4/P5 measure latency on dev.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **XCFramework as a SwiftPM `binaryTarget` (URL + checksum)** | Official, prebuilt, Metal included; pinned to the exact export commit; checksum verified by SwiftPM; works in CI with no extra tools | 62 MB download on first build (cache in CI); a dynamic framework must be copied into the app/XPC bundle by our build script |
| Homebrew `libllama.dylib` (what the prototype used) | Already installed, no download | Links to `/opt/homebrew`: not inside the app, breaks when Homebrew updates, CI needs `brew install`; a sandboxed service should not depend on it |
| Build llama.cpp from source in our build script (CMake, pinned commit) | Full control, same commit | Slow builds, a C++ toolchain step in CI, more script to maintain for no gain over the official build |
| Run `llama-server` and talk HTTP to it | Same code path as B1 | Needs a listening socket and a network entitlement in the sandbox, which fails the P5 gate; a second process to manage |

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | `Packages/ArabiziLLM` depends on `.binaryTarget(name: "llama", url: ".../b11429/llama-b11429-xcframework.zip", checksum: "e26a6a0a…3174")`. Upgrading llama.cpp means changing the URL, checksum, Homebrew build and `train/export_gguf.sh` commit together. | llama.cpp docs; pin **Recommendation** |
| 2 | Generation uses only the C API: load once and keep warm; n_ctx 512; greedy; stop at end of generation; the deadline is checked after every token and `llama_set_abort_callback` stops a long prompt decode; a timeout returns the rule fallback (`fallbackTimeout`). | Roadmap P5 step 4; details **Recommendation** |
| 3 | **Prompt text is pre-rendered, not templated in Swift.** The XCFramework has no Jinja engine, and `llama_chat_apply_template` only guesses common formats (it does not add Qwen3's empty `<think>` block). The prompt prefix and suffix around the Arabizi, exactly as rendered at training time (ADR 0015 #4), are stored with each fine-tuned model's entry in `config/models.json`, and a test compares them with `llama-server`'s `/apply-template` for the same input. | **Recommendation** |
| 4 | The build scripts copy `llama.framework` into the app (`Contents/Frameworks`) with an `@rpath` that the XPC service can also use; everything is ad-hoc signed as today (ADR 0013). CI caches SwiftPM's artifact folder. | **Recommendation** |

## Consequences

- The model file must be readable inside the sandboxed XPC service: either copied into the built app at install time (never committed; ~1 GB) or placed in the service's container. Decided with the XPC service (P5 step 5); the first option is simpler for the demo.
- The latency numbers above make the 1,500 ms default a real constraint for Qwen3-1.7B; ADR 0005 (final model) should weigh latency on dev, not only accuracy, and `config/engine.json` may scale the deadline with input length.
- `mtmd` (multimodal) comes along inside the framework; unused.

## Built

`Packages/ArabiziLLM`: the binary target above and `LlamaModel` (load once, `generate(_:maxTokens:timeout:)` → text plus why it stopped: end of turn, token limit or deadline; one generation at a time; llama.cpp logging off, no text logged) and `PromptTemplate`. The prompt is tokenized exactly as `llama-server`'s `/completion` does from text (special tokens parsed, the model's BOS added, nothing removed): the Llama fine-tune was trained with two BOS tokens, and an earlier version that removed the duplicate degraded its output (fixed 16 Oct 2026, MODELS.md). Tests run against `models/Qwen3-0.6B-Q4_K_M.gguf` (or `ARABIZI_TEST_MODEL`) and are skipped without it, as in CI. Checked on 15 Oct 2026: the downloaded zip's SHA-256 matches the pin, and `gh attestation verify --repo ggml-org/llama.cpp` passes (signed by llama.cpp's `release-publish.yml`; the attestation shows the release workflow, while the link to commit d81235049 comes from the `b11429` tag). With a model loaded at exit, llama.cpp's Metal clean-up aborts (`GGML_ASSERT([rsets->data count] == 0)`), which would crash the warm XPC service on every quit; `LlamaModel` frees models still loaded from an `atexit` handler registered after the first load, before llama.cpp's own clean-up. All 7 tests pass on the Air with Qwen3-0.6B (5 skip without a model). GitHub's download stalled here and SwiftPM timed out; the zip was fetched with a resuming `curl` and placed in SwiftPM's cache, which still checks the checksum (practical notes). The copy of `llama.framework` into the app comes with the XPC service (P5 step 5), the first bundle that links ArabiziLLM.
