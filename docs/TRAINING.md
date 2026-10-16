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
| each `run.json` | `train/runs/` (committed: hyperparameters, losses, versions, the rendered `prompt` prefix and suffix; no private text) |

Then tell Claude: the models get entries in `config/models.json` (with their SHA-256 and the `prompt` prefix and suffix from `run.json`, which the engine uses verbatim, ADR 0017/0018) and are scored on dev with the same harness as B0 and B1, without examples (the fine-tuned model has learnt the task).

## Sweep: one setting at a time (accuracy plan, step 2)

`train/sweep_lora.ipynb` trains Llama 3.2 1B four times on the **same export** (the existing private Kaggle dataset; no new upload), each run changing **one** setting against the shipped model's (rank 16, alpha 32, lr 2e-4, 3 epochs):

| Run (`--tag`) | Change | Why |
|---|---|---|
| `base` | none | reproducibility (P4 gate: dev within 2 points of 0.768) and the noise floor of a rerun |
| `rank32` | `--rank 32 --alpha 64` | more adapter capacity |
| `lr1e-4` | `--lr 1e-4` | smaller steps: validation loss rose after epoch 2 |
| `ep2` | `--epochs 2` | the schedule ends where the shipped run's best checkpoint was (epoch 2) |

Import it like the main notebook, set **GPU T4**, **Internet on**, add the `arabizi-train` dataset, then **Save Version → Save & Run All (Commit)**: it runs in the background (about 2 hours of GPU) and keeps the outputs on the version page. Download the three files per run (`arabizi-llama3.2-1b-<tag>-Q4_K_M.gguf`, `.sha256`, `run.json`).

**How the runs are judged** (on the Mac, dev only; the test set is not touched): each run is scored with the same harness and compared with the shipped model by paired bootstrap on the same 104 dev rows. A setting is kept only if the 95% interval of the gain is above 0, and only if it beats `base` by more than `base` differs from the shipped model (the rerun noise). The winners are combined in one more run; a clear overall gain makes a new final candidate (one test run, new ADR).

## Smoke run first (optional)

Add `--limit 200 --epochs 1` to the training command in the notebook to check everything end to end in a few minutes before the full run.

## Troubleshooting

| Problem | Try |
|---|---|
| `no GPU` | Settings → Accelerator → GPU; quota left? |
| Cannot clone or install | Settings → Internet on (needs the verified phone number) |
| `add exactly one dataset with export.json` | Add the private dataset; only one export folder |
| Out of memory | `--batch 4 --grad-accum 8` (same effective batch) |
