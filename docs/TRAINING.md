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

## Sweep results (17 Oct 2026)

All four runs on a Kaggle T4, same data export and package versions as the shipped run; scored on dev (104 rows, numbers protected as the engine does, `ft-<id>-protect`) and compared with the shipped model by paired bootstrap. Private rows: aggregates only; runs in `eval/results/private/` (not committed).

| Run | Best val. loss | Dev word acc. [95% CI] | CER | Keep-Latin F1 | p50 / p95 ms | vs shipped (paired) |
|---|---|---|---|---|---|---|
| shipped `v1` | 0.401 | 0.774 | 0.093 | 0.87 | — | — |
| `base` | 0.401 | = shipped | = | = | = | **bit-identical GGUF** (same SHA-256) |
| `rank32` | **0.380** | **0.784** [0.75, 0.82] | **0.084** | **0.88** | 419 / 811 | +0.009 [−0.012, +0.031]: no clear difference |
| `lr1e-4` | 0.474 | 0.742 [0.70, 0.78] | 0.107 | 0.81 | 446 / 913 | −0.032 [−0.057, −0.008]: worse |
| `ep2` | 0.431 | 0.770 [0.73, 0.81] | 0.088 | 0.86 | 417 / 778 | −0.004 [−0.028, +0.022]: no clear difference |

- **Reproducibility:** with seed 2026 the training is deterministic on the T4, so a rerun's noise is 0; this says nothing about the spread across seeds.
- **No setting passes the keep rule** (gain interval above 0): the shipped model stays. A smaller learning rate is clearly worse; two epochs is no better than three.
- `rank32` is the best on every dev metric but within noise. **Claude's recommendation:** use rank 32 (`--rank 32 --alpha 64`) for the next run, which adds the new real rows (more data can use more adapter capacity), and judge that run as a whole against the shipped model, rather than spending another Kaggle run on rank alone.
- The three sweep models are registered in `config/models.json` (`arabizi-llama3.2-1b-rank32`, `-lr1e-4`, `-ep2`; weights in `models/`, never committed).

## Training with the real rows (ADR 0021)

`train/finetune_v2.ipynb` trains Llama 3.2 1B twice on the new export (4,994 real training rows added; 22,712 examples, AI-derived share 18%):

| Run (`--tag`) | Settings | Why |
|---|---|---|
| `v2` | rank 32, alpha 64 | the candidate: the sweep's best setting with more data |
| `v2-r16` | the shipped settings | separates the data's effect from the rank's |

Upload `build/train-export/` as a **new version** of the private `arabizi-train` dataset (Kaggle → your dataset → **New Version** → replace all files), import the notebook, set GPU T4 and Internet on, add the dataset, then **Save Version → Save & Run All (Commit)**. Download everything with **Download all**. Each run is scored on frozen dev and on the others dev set against the shipped model (others dev, 200 rows: B0 0.591 [0.57, 0.61], shipped model 0.636 [0.62, 0.66], +0.046 [+0.027, +0.065] over B0; hallucination 15%).

### Results (17 Oct 2026)

Both runs: 85 minutes each on a T4; 22,712 examples. Validation losses (0.431 for `v2`, 0.454 for `v2-r16`) are not comparable with earlier runs, because the validation rows changed. Dev word accuracy (numbers protected), paired against the shipped model:

| Run | Frozen dev | Others dev |
|---|---|---|
| `v2` | **0.812** (+0.038 [+0.008, +0.068]) | **0.811** (+0.175 [+0.155, +0.195]) |
| `v2-r16` | 0.803 (+0.029 [+0.001, +0.056]) | 0.797 (+0.160 [+0.139, +0.182]) |

The data makes the difference; rank 32 adds about one point, within noise. `v2` went to the one-time test run: 0.820 frozen test and 0.800 others test (ADR 0022).

## v3: one spelling for English words (ADR 0024)

`train/finetune_v3.ipynb`: one run, `v3`, with v2's settings (rank 32) on the export after `pairs split-prefixes` (every Arabic prefix apart from an English word; 0 glued tokens left in the export). Upload the new export as a new version of `arabizi-train`, then Save & Run All, as for v2. It is compared with v2 on frozen dev and others dev (`others-v1.1`).

## Smoke run first (optional)

Add `--limit 200 --epochs 1` to the training command in the notebook to check everything end to end in a few minutes before the full run.

## Troubleshooting

| Problem | Try |
|---|---|
| `no GPU` | Settings → Accelerator → GPU; quota left? |
| Cannot clone or install | Settings → Internet on (needs the verified phone number) |
| `add exactly one dataset with export.json` | Add the private dataset; only one export folder |
| Out of memory | `--batch 4 --grad-accum 8` (same effective batch) |
