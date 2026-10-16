# Models

Which language models the project uses, where they come from, their licences, and how they are fetched. Weights are **never committed** (`models/` is in `.gitignore`); `config/models.json` pins every file to a repository revision and SHA-256 (taken from the Hugging Face API, 14 Oct 2026), and `scripts/fetch_models.py` downloads and checks them. Runtime: llama.cpp ([ADR 0003](decisions/0003-runtime-llama-cpp.md)).

## B1 candidates (P3: base models, no fine-tuning)

| Id | Model | Params | File (Q4_K_M) | Size | Licence | From | Why it is a candidate |
|---|---|---|---|---|---|---|---|
| `qwen2.5-0.5b` | Qwen2.5-0.5B-Instruct | 0.5B | `qwen2.5-0.5b-instruct-q4_k_m.gguf` | 0.49 GB | Apache-2.0 | Qwen (official) | Roadmap; smallest, fastest |
| `qwen2.5-1.5b` | Qwen2.5-1.5B-Instruct | 1.5B | `qwen2.5-1.5b-instruct-q4_k_m.gguf` | 1.12 GB | Apache-2.0 | Qwen (official) | Roadmap; likely better Arabic, still fits 8 GB |
| `qwen3-0.6b` | Qwen3-0.6B | 0.6B | `Qwen3-0.6B-Q4_K_M.gguf` | 0.40 GB | Apache-2.0 | Unsloth conversion | **Claude's recommendation**: the newer generation of the same family |
| `qwen3-1.7b` | Qwen3-1.7B | 1.7B | `Qwen3-1.7B-Q4_K_M.gguf` | 1.11 GB | Apache-2.0 | Unsloth conversion | **Claude's recommendation** |
| `gemma3-1b` | Gemma 3 1B IT | 1B | `google_gemma-3-1b-it-Q4_K_M.gguf` | 0.81 GB | Gemma Terms of Use | bartowski conversion | Roadmap; needs licence acceptance |
| `llama3.2-1b` | Llama 3.2 1B Instruct | 1B | `Llama-3.2-1B-Instruct-Q4_K_M.gguf` | 0.81 GB | Llama 3.2 Community License | bartowski conversion | Roadmap; Arabic is not among Meta's 8 officially supported languages; needs licence acceptance |

Total: 3.11 GB for the four Qwen files, 4.73 GB with Gemma and Llama.

- **Never Qwen2.5-3B** (Qwen Research licence, non-commercial; v1 decision D2).
- **Community conversions:** Qwen publishes official GGUF files for Qwen3 only as Q8_0 (too large for the memory budget), and Google/Meta publish theirs behind a login; the Unsloth and bartowski repositories are widely used conversions of the official weights. The original licence still applies to a conversion. Pinning the revision and SHA-256 makes the exact file reproducible.
- **Licences that need acceptance:** Gemma (Gemma Terms of Use, including Google's prohibited-use policy) and Llama 3.2 (Community License: acceptable-use policy; "Built with Llama" attribution if distributed). `fetch_models.py` only fetches them with `--accept-licence gemma` / `--accept-licence llama`; record the acceptance here (who, date) when it is given.
- **Memory budget** (≤ 1.5 GB engine RSS on the 8 GB Air): all Q4_K_M files above are ≤ 1.12 GB on disk; the run also needs a context buffer, so the 1.5–1.7B models will be close and P3 measures it.
- **Fine-tuning (P4)** uses the original Hugging Face weights of the chosen base model **on Kaggle**, not these GGUF files; the fine-tuned model is converted to GGUF there and fetched like the others (its entry is added to `config/models.json` then).

## Fine-tuned models (P4)

Trained on Kaggle with `train/finetune_lora.py` (ADR 0015) from the frozen data (`testset-v1.0`, export of 8,385 training examples, 48% AI-derived). The weights stay private (`models/`, never committed); `config/models.json` pins each file's size and SHA-256 and holds the **exact prompt** its run saved (`prompt.prefix` / `prompt.suffix`), and `train/runs/<run_id>.json` records the run (hyperparameters, losses, versions, public samples).

| Id | Base | Run | File | Size | Best val. loss | Dev word acc. |
|---|---|---|---|---|---|---|
| `arabizi-llama3.2-1b-v1` | Llama 3.2 1B Instruct | `20261016-051159-llama3.2-1b-lora` (T4, fp16, 25 min) | `arabizi-llama3.2-1b-v1-Q4_K_M.gguf` | 0.81 GB | 0.401 | 0.768 (EVAL.md) |
| `arabizi-qwen3-1.7b-v1` | Qwen3-1.7B | `20261016-084514-qwen3-1.7b-lora` (T4, fp16, 41 min) | `arabizi-qwen3-1.7b-v1-Q4_K_M.gguf` | 1.11 GB | 0.379 | 0.723 (EVAL.md) |

- **Qwen was trained twice:** the first run (`20261016-054238`, validation loss 0.370) finished, but its file was lost when the Kaggle session ended before the download; its run file stays in `train/runs/` as a record. The run above (`20261016-084514`) is the one in `models/` and `config/models.json`. Training is not bit-for-bit repeatable, so the two are different models.
- **Chosen model:** [ADR 0005](decisions/0005-final-model.md) proposes the Llama fine-tune (more accurate, faster, lighter).

- **Getting the files:** they are not on Hugging Face; download them from the Kaggle run's output (docs/TRAINING.md) and check them against the `.sha256` files. `scripts/fetch_models.py` lists them as skipped.
- **Licence:** the Llama 3.2 Community License applies to the fine-tune (accepted 14 Oct 2026); "Built with Llama" if it is ever distributed.
- **BOS tokens (Llama):** the saved prompt starts with the text `<|begin_of_text|>`, and the tokenizer adds another BOS, so training saw **two**. Evaluation sends the prompt as text to `llama-server`, which does the same and reproduces the run's samples; a single BOS degrades the output. The Swift `LlamaModel` tokenizes the same way (both BOS kept, fixed 16 Oct 2026); `FineTunedParityTests` checks the two BOS tokens and that it reproduces the run's own training-time sample exactly.

## The download step (one step, when Moustafa says go)

Everything that has to be downloaded to this Mac for P3, in one go:

```bash
brew install llama.cpp                                  # runtime: llama-cli / llama-server (~30 MB)
python3 scripts/fetch_models.py --list                   # check the plan first
python3 scripts/fetch_models.py                          # the four Qwen files, 3.11 GB, hash-checked
python3 scripts/fetch_models.py --accept-licence gemma --accept-licence llama   # only if those licences are accepted
```

Not part of this step: the llama.cpp Swift library for the keyboard engine (P5) is fetched by Swift Package Manager during the build; it is the official XCFramework of release b11429 (62 MB, same commit as Homebrew's build and the GGUF export), pinned by URL and checksum ([ADR 0017](decisions/0017-llama-cpp-from-swift.md)). Fine-tuning downloads happen on Kaggle.

## Licence acceptance log

| Licence | Accepted by | Date |
|---|---|---|
| Gemma Terms of Use | Moustafa Abbara ("i accept the licenses of gamma and llama models") | 2026-10-14 |
| Llama 3.2 Community License | Moustafa Abbara (same message) | 2026-10-14 |
