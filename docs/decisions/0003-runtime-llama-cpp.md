# ADR 0003: llama.cpp as the model runtime

- **Status:** accepted
- **Date:** 2026-10-14
- **Deciders:** Moustafa Abbara (roadmap choice; this ADR records it)
- **Stage:** P3

## Context

The keyboard runs a small language model on the Mac only (ADR 0010), inside a sandboxed engine with no network (P5), on an 8 GB M2 Air. P3 needs to run several base models the same way for a fair comparison, and the same runtime has to be callable from Swift later. Fine-tuning happens on Kaggle with Hugging Face tools; the result must be convertible to whatever the runtime loads.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **llama.cpp (GGUF)** | One file per model, many quantisations (Q4_K_M ≈ 0.4–1.1 GB for 0.5–1.7B); Metal on Apple Silicon; `llama-cli`/`llama-server` for P3 and a Swift integration for P5; grammar-constrained output if ever needed; conversion script from Hugging Face weights; Homebrew package | C/C++ library inside the engine; Swift packaging must be checked at P5 |
| MLX / MLX-Swift | Apple-native, good speed, LoRA training on the Mac | Separate format and toolchain from the GGUF ecosystem; Swift API less settled; fewer ready quantised models |
| Apple Foundation Models | Built into macOS | Apple Intelligence does not support Arabic (v1 D3) |
| Core ML conversion | Native | Conversion of current LLMs is fragile; slower iteration |

## Decision

**llama.cpp with GGUF Q4_K_M models** (roadmap P3 step 3). P3 uses the Homebrew build (`llama-cli` / `llama-server`, version recorded with each run); P5 uses the same library from Swift. Models are pinned in `config/models.json` and fetched by `scripts/fetch_models.py` (docs/MODELS.md).

## Consequences

- B1 and later runs record the llama.cpp version, model id, quantisation and SHA-256 in `metrics.json`.
- The fine-tuned model (P4) must be exported to GGUF (llama.cpp's converter, on Kaggle) to be used.
- MLX stays the fallback for on-device fine-tuning if Kaggle is unavailable (roadmap C5).
- The Swift packaging of llama.cpp is checked and pinned at P5: its 2026 releases no longer list an XCFramework asset under the old name. **Update 15 Oct 2026:** checked, and this was wrong: every release still ships `llama-bNNNN-xcframework.zip`, including b11429 (= commit d81235049). See [ADR 0017](0017-llama-cpp-from-swift.md).
