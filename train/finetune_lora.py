#!/usr/bin/env python3
"""Fine-tune a base model with LoRA on Kaggle (roadmap P4, ADR 0004, ADR 0015). Runs on a Kaggle GPU, not on the Mac.

  python train/finetune_lora.py --base llama3.2-1b --data /kaggle/input/arabizi-train --out /kaggle/working/out

- Data: the folder written by `pairs export-train` (uploaded as a PRIVATE Kaggle dataset): train-*.jsonl, val-*.jsonl
  and export.json. Training rows only; dev and test never leave the Mac.
- Each example is rendered with the base model's own chat template exactly as llama-server will send it at run time
  (system instruction + Arabizi, generation prompt, Qwen3 thinking off); the loss is on the Arabic answer only.
- LoRA on all linear layers; the best epoch by validation loss is kept, merged into the base model and saved, ready
  for train/export_gguf.sh.
- run.json records the rendered prompt prefix and suffix around the Arabizi, which the engine needs (ADR 0017/0018).
- Nothing printed contains private text: progress and losses only; sample outputs come from public rows.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import time
from datetime import UTC, datetime
from pathlib import Path

# Hugging Face weights (repository, pinned commit) for each base model in config/models.json (ADR 0004). The Llama entry is Unsloth's ungated
# copy of Meta's weights; the Llama 3.2 Community License still applies (accepted by Moustafa, 14 Oct 2026).
BASES = {
    "llama3.2-1b": ("unsloth/Llama-3.2-1B-Instruct", "5a8abab4a5d6f164389b1079fb721cfab8d7126c"),
    "qwen3-1.7b": ("Qwen/Qwen3-1.7B", "70d244cc86ccca08cf5af4e1e306ecf908b1ad5e"),
    "qwen3-0.6b": ("Qwen/Qwen3-0.6B", "c1899de289a04d12100db370d81485cdf75e47ca"),
    "qwen2.5-1.5b": ("Qwen/Qwen2.5-1.5B-Instruct", "989aa7980e4cf806f80c7fef2b1adb7bc71aa306"),
}


def load_examples(data_dir: Path, split: str) -> list[dict]:
    """All examples of one split ('train' or 'val'), public and private files together."""
    examples = []
    for path in sorted(data_dir.glob(f"{split}-*.jsonl")):
        examples += [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    if not examples:
        raise SystemExit(f"no {split}-*.jsonl files in {data_dir}: upload the `pairs export-train` folder")
    return examples


def render(tokenizer, messages: list[dict]) -> dict:
    """Prompt exactly as llama-server builds it (generation prompt, thinking off) and the answer + end of turn."""
    prompt = tokenizer.apply_chat_template(messages[:-1], tokenize=False, add_generation_prompt=True,
                                           enable_thinking=False)
    return {"prompt": prompt, "completion": messages[-1]["content"] + tokenizer.eos_token}


PROMPT_MARKER = "ARABIZIPROMPTMARKER"


def prompt_template(tokenizer, examples: list[dict]) -> dict:
    """The rendered prompt around the Arabizi, as {"prefix", "suffix"}, for config/models.json (ADR 0017 #3, 0018 #5).

    The engine cannot render chat templates (the llama.cpp XCFramework has no Jinja), so it uses these two strings
    verbatim. They come from this run because templates can change with the date: Llama 3.2 writes today's date into
    its system header. Checked against real examples: prefix + Arabizi + suffix must be exactly the training prompt.
    """
    system = examples[0]["messages"][0]
    messages = [system, {"role": "user", "content": PROMPT_MARKER}, {"role": "assistant", "content": ""}]
    prompt = render(tokenizer, messages)["prompt"]
    if prompt.count(PROMPT_MARKER) != 1:
        raise SystemExit("the chat template changed the Arabizi placeholder; cannot record the prompt")
    prefix, _, suffix = prompt.partition(PROMPT_MARKER)
    for example in examples[:20]:
        if example["messages"][0] != system:
            raise SystemExit("training examples use different system prompts; cannot record one prompt")
        expected = render(tokenizer, example["messages"])["prompt"]
        if prefix + example["messages"][1]["content"] + suffix != expected:
            raise SystemExit("prefix + Arabizi + suffix differs from the training prompt; cannot record the prompt")
    return {"prefix": prefix, "suffix": suffix}


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base", required=True, choices=sorted(BASES))
    parser.add_argument("--data", type=Path, required=True, help="folder from `pairs export-train`")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--epochs", type=float, default=3)
    parser.add_argument("--lr", type=float, default=2e-4)
    parser.add_argument("--rank", type=int, default=16)
    parser.add_argument("--alpha", type=int, default=32)
    parser.add_argument("--dropout", type=float, default=0.05)
    parser.add_argument("--batch", type=int, default=8)
    parser.add_argument("--grad-accum", type=int, default=4)
    parser.add_argument("--max-length", type=int, default=256)
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--limit", type=int, help="only the first N training examples (smoke run)")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    import torch
    from datasets import Dataset
    from peft import LoraConfig
    from transformers import AutoModelForCausalLM, AutoTokenizer
    from trl import SFTConfig, SFTTrainer

    if not torch.cuda.is_available():
        raise SystemExit("no GPU: in Kaggle, Settings -> Accelerator -> GPU")
    started = time.time()
    hf_id, revision = BASES[args.base]
    run_id = f"{datetime.now(UTC):%Y%m%d-%H%M%S}-{args.base}-lora"
    out = args.out / run_id
    out.mkdir(parents=True, exist_ok=True)

    tokenizer = AutoTokenizer.from_pretrained(hf_id, revision=revision)
    train = load_examples(args.data, "train")[: args.limit]
    val = load_examples(args.data, "val")
    prompt = prompt_template(tokenizer, train)  # before training: a template problem stops the run early
    train_ds = Dataset.from_list([render(tokenizer, e["messages"]) for e in train])
    val_ds = Dataset.from_list([render(tokenizer, e["messages"]) for e in val])
    too_long = sum(len(tokenizer(r["prompt"] + r["completion"])["input_ids"]) > args.max_length for r in train_ds)
    print(f"{args.base} ({hf_id}): {len(train_ds)} training and {len(val_ds)} validation examples; "
          f"{too_long} longer than {args.max_length} tokens (truncated)")

    bf16 = torch.cuda.is_bf16_supported()
    model = AutoModelForCausalLM.from_pretrained(hf_id, revision=revision, torch_dtype=torch.bfloat16 if bf16 else torch.float16,
                                                 device_map={"": 0})
    config = SFTConfig(
        output_dir=str(out / "checkpoints"), num_train_epochs=args.epochs, learning_rate=args.lr,
        per_device_train_batch_size=args.batch, per_device_eval_batch_size=args.batch,
        gradient_accumulation_steps=args.grad_accum, lr_scheduler_type="cosine", warmup_ratio=0.03,
        logging_steps=20, eval_strategy="epoch", save_strategy="epoch", load_best_model_at_end=True,
        metric_for_best_model="eval_loss", greater_is_better=False, save_total_limit=1,
        bf16=bf16, fp16=not bf16, max_length=args.max_length, completion_only_loss=True,
        report_to="none", seed=args.seed,
    )
    lora = LoraConfig(r=args.rank, lora_alpha=args.alpha, lora_dropout=args.dropout,
                      target_modules="all-linear", task_type="CAUSAL_LM")
    trainer = SFTTrainer(model=model, args=config, train_dataset=train_ds, eval_dataset=val_ds,
                         processing_class=tokenizer, peft_config=lora)
    trainer.train()

    merged_dir = out / "merged"
    merged = trainer.model.merge_and_unload()
    merged.save_pretrained(merged_dir, safe_serialization=True)
    tokenizer.save_pretrained(merged_dir)

    # A few public validation sentences, greedy, as a quick look (never private rows).
    samples = []
    public_file = args.data / "val-public.jsonl"  # only the public file: private rows are never printed
    public_val = [json.loads(line) for line in public_file.read_text(encoding="utf-8").splitlines()
                  if line.strip()][:5] if public_file.exists() else []
    merged.eval()
    for example in public_val:
        rendered = render(tokenizer, example["messages"])
        ids = tokenizer(rendered["prompt"], return_tensors="pt").to(merged.device)
        with torch.no_grad():
            output = merged.generate(**ids, max_new_tokens=64, do_sample=False)
        reply = tokenizer.decode(output[0][ids["input_ids"].shape[1]:], skip_special_tokens=True).strip()
        samples.append({"arabizi": example["messages"][1]["content"], "reference": example["messages"][2]["content"],
                        "output": reply})
        print(f"  {samples[-1]['arabizi']}\n    -> {reply}")

    import peft
    import transformers
    import trl
    export = json.loads((args.data / "export.json").read_text(encoding="utf-8"))
    history = [{k: v for k, v in log.items() if k in ("epoch", "loss", "eval_loss", "learning_rate")}
               for log in trainer.state.log_history]
    run = {
        "run_id": run_id, "base": args.base, "hf_id": hf_id, "hf_revision": revision, "method": "LoRA, completion-only loss",
        "hyperparameters": {k: (str(v) if isinstance(v, Path) else v) for k, v in vars(args).items()},
        "data": {"export_files": export["files"], "rows_total": export["rows_total"], "ai_share": export["ai_share"],
                 "prompt_version": export["prompt_version"],
                 "export_sha256_16": hashlib.sha256(json.dumps(export, sort_keys=True).encode()).hexdigest()[:16]},
        "best_eval_loss": trainer.state.best_metric, "best_checkpoint": trainer.state.best_model_checkpoint,
        "history": history, "public_samples": samples,
        "prompt": prompt,  # copied into config/models.json with the model; the engine uses it verbatim
        "gpu": torch.cuda.get_device_name(0), "precision": "bf16" if bf16 else "fp16",
        "minutes": round((time.time() - started) / 60, 1), "python": platform.python_version(),
        "versions": {"torch": torch.__version__, "transformers": transformers.__version__,
                     "peft": peft.__version__, "trl": trl.__version__},
    }
    (out / "run.json").write_text(json.dumps(run, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"done in {run['minutes']} min; best validation loss {run['best_eval_loss']}; merged model in {merged_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
