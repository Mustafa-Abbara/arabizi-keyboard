# ADR 0015: Fine-tuning setup (P4)

- **Status:** accepted
- **Date:** 2026-10-14
- **Deciders:** Moustafa Abbara
- **Stage:** P4

## Context

ADR 0004 picked Llama 3.2 1B and Qwen3-1.7B to fine-tune. Training needs a GPU (Kaggle, ADR 0010 #4); the result must run with llama.cpp on the 8 GB Air (ADR 0003). The training data mixes public rows with Moustafa's private messages (ADR 0014). The AI share of training is capped at half (ADR 0010).

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | `pairs export-train` writes chat examples (B1's instruction, the Arabizi, the Arabic) from **training rows only**; dev and test never leave the Mac. Public and private rows go to separate files; the whole folder is uploaded as a **private** Kaggle dataset. | **Recommendation** (ADR 0014 #6) |
| 2 | **AI cap:** one spelling variant per AI-drafted row, all variants of human rows: 8,385 examples, 48% AI-derived. The export fails above 50%. | **Recommendation** (meets ADR 0010) |
| 3 | **Validation:** 5% of sentence groups (a row and its variants together) for the validation loss, so no variant of a validation sentence is trained on. Dev stays the model-selection set, scored on the Mac. | **Recommendation** |
| 4 | **Prompt parity:** each example is rendered with the model's own chat template, generation prompt and thinking off, exactly as llama-server builds it at run time; the loss is on the Arabic answer (completion-only). | **Recommendation** |
| 5 | **LoRA** on all linear layers: rank 16, alpha 32, dropout 0.05, learning rate 2e-4 (cosine, 3% warm-up), 3 epochs, effective batch 32, max 256 tokens, seed 2026; best epoch by validation loss; then merged. Base weights pinned to a Hugging Face commit; the Llama weights from Unsloth's ungated copy (the Llama 3.2 licence still applies). | Roadmap P4 starting values; pins and Llama source **Recommendation** |
| 6 | **GGUF export on Kaggle** with the same llama.cpp commit as the Mac (d81235049), Q4_K_M, with SHA-256; the merged model and checkpoints are deleted so the download is small. | **Recommendation** |
| 7 | **Privacy in logs:** the scripts print counts, losses and public examples only; `run.json` (committed) holds hyperparameters, losses, versions and public samples, never private text. | **Recommendation** |

## Consequences

- Each fine-tuned model is scored on dev with the same harness as B0/B1 (zero-shot: the task is learnt). P4's gate compares it with B0 and the best B1 with paired bootstrap CIs; ADR 0005 records the final model.
- Ablations from the roadmap (with/without AI rows, with/without variants) are new exports (`--ai-variants 0`, `--public-only`, or a variant-free export) trained the same way.
- Kaggle versions of transformers/peft/trl are not pinned exactly (minimums in `train/requirements.txt`); each `run.json` records the versions used.
