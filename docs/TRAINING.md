# Fine-tuning on Kaggle (P4)

How to fine-tune the two base models chosen in [ADR 0004](decisions/0004-base-model-choice.md), Llama 3.2 1B and Qwen3-1.7B, on Kaggle's free GPU, and bring them back to the Mac. Decisions: [ADR 0015](decisions/0015-fine-tuning-setup.md). Training happens in the cloud; the keyboard only ever runs the result locally.

## Before you start

- The **test set is frozen** (`pairs freeze`, docs/DATA.md). Fine-tuning before the freeze would make the final results untrustworthy.
- Kaggle account with a verified phone number (needed for GPUs and Internet in notebooks). Free quota: about 30 GPU hours a week; both runs together should take well under 3 hours.

## 1. Export the training data (Mac)

```bash
uv run --project eval pairs variants        # spelling variants (generated, not committed)
uv run --project eval pairs export-train    # -> build/train-export/
```

The folder holds `train-public.jsonl`, `train-private.jsonl`, `val-public.jsonl`, `val-private.jsonl` and `export.json` (counts, hashes, AI share). **Training rows only:** dev and test never leave the Mac. The command fails if AI-derived rows are above half (ADR 0010).

## 2. Upload it as a private Kaggle dataset

Kaggle → Datasets → **New Dataset** → drop the files of `build/train-export/` → title e.g. `arabizi-train` → **Private** → Create. It contains your own messages (ADR 0014): keep it private and do not share it.

## 3. Run the notebook

Kaggle → Code → **New Notebook** → File → **Import Notebook** → `train/finetune_lora.ipynb` from the repo. Then:

- Settings → Accelerator → **GPU T4** (or P100); Settings → **Internet on**.
- Add data → your private `arabizi-train` dataset.
- Keep the notebook **private**. Run all.

The notebook clones the public repository, installs `train/requirements.txt`, trains Llama 3.2 1B then Qwen3-1.7B with `train/finetune_lora.py` (LoRA, loss on the Arabic answer only, best epoch by validation loss), converts each to GGUF Q4_K_M with `train/export_gguf.sh` (same llama.cpp commit as the Mac), and deletes the large intermediate files.

## 4. Bring the models back (Mac)

From the notebook's **Output**, download per model:

| File | Goes to |
|---|---|
| `arabizi-llama3.2-1b-v1-Q4_K_M.gguf`, `arabizi-qwen3-1.7b-v1-Q4_K_M.gguf` | `models/` (never committed) |
| the matching `.sha256` files | check with `shasum -a 256 models/<file>` |
| each `run.json` | `train/runs/` (committed: hyperparameters, losses, versions; no private text) |

Then tell Claude: the models get entries in `config/models.json` (with their SHA-256) and are scored on dev with the same harness as B0 and B1, without examples (the fine-tuned model has learnt the task).

## Smoke run first (optional)

Add `--limit 200 --epochs 1` to the training command in the notebook to check everything end to end in a few minutes before the full run.

## Troubleshooting

| Problem | Try |
|---|---|
| `no GPU` | Settings → Accelerator → GPU; quota left? |
| Cannot clone or install | Settings → Internet on (needs the verified phone number) |
| `add exactly one dataset with export.json` | Add the private dataset; only one export folder |
| Out of memory | `--batch 4 --grad-accum 8` (same effective batch) |
