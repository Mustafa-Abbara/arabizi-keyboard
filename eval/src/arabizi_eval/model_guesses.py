"""The model's own guesses for each wrong word of a scored run (ADR 0036, source 1), for training and checking the
↑ list's ranker. Needs llama-cpp-python (not an eval dependency: `uv run --with llama-cpp-python`) and the model file.

  uv run --project eval --with llama-cpp-python python -m arabizi_eval.model_guesses \\
      eval/results/<run>/predictions.jsonl --set dev --out eval/results/candidates/guesses-v3.jsonl

For each wrong word (candidates.wrong_words), the model's answer is kept up to that word and a small beam over its next
tokens finishes the word several ways (until a space or the end of the answer). Resumes: words already in OUT are
skipped. Only public rows belong in the repo; guesses for private sheets stay outside it.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

from arabizi_eval import b0
from arabizi_eval import candidates as C
from arabizi_eval import pairs as P

MODEL_ID = "arabizi-llama3.2-1b-v3"


class Guesser:
    def __init__(self, model_id: str = MODEL_ID, threads: int = 8):
        from llama_cpp import Llama

        models = {m["id"]: m for m in json.loads((P.ROOT / "config" / "models.json").read_text("utf-8"))["models"]}
        model = models[model_id]
        self.prefix, self.suffix = model["prompt"]["prefix"], model["prompt"]["suffix"]
        self.llm = Llama(model_path=str(P.ROOT / "models" / model["file"]), n_ctx=512, logits_all=True,
                         verbose=False, n_threads=threads, n_batch=512)
        self.ends = {self.llm.token_eos(), self.llm.tokenize(b"<|eot_id|>", add_bos=False, special=True)[0]}

    def _word(self, tokens: list[int]) -> str:
        word = P.normalize_arabic(self.llm.detokenize(tokens).decode("utf-8", "ignore").strip())
        word = b0.ARABIC_CORE.sub("", word)
        return word if C.is_arabic_word(word) else ""

    def guesses(self, arabizi: str, before: str, width: int = 8, depth: int = 6, keep: int = 10) -> list[list]:
        """The model's best ways to write the next word after `before`, with their log-probabilities."""
        llm = self.llm
        context = llm.tokenize((self.prefix + arabizi + self.suffix).encode(), add_bos=False, special=True)
        start = llm.tokenize(before.encode(), add_bos=False, special=False) if before else []
        llm.reset()
        llm.eval(context + start)
        base = llm.n_tokens  # each branch rewinds here: eval drops the cache after n_tokens
        beams, done = [(0.0, [])], {}
        for _ in range(depth):
            grown = []
            for lp, toks in beams:
                llm.n_tokens = base
                if toks:
                    llm.eval(toks)
                row = np.asarray(llm.scores[llm.n_tokens - 1], dtype=np.float64)
                logits = row - (row.max() + np.log(np.exp(row - row.max()).sum()))
                for tok in np.argsort(logits)[::-1][: width * 2]:
                    tok = int(tok)
                    piece = llm.detokenize([tok])
                    if tok in self.ends or (toks and piece[:1] in (b" ", b"\n")):
                        if toks and (word := self._word(toks)) and (word not in done or done[word] < lp):
                            done[word] = lp
                        continue
                    if not toks and before and piece[:1] != b" ":
                        continue  # the next word must start a new word
                    grown.append((lp + float(logits[tok]), toks + [tok]))
            beams = sorted(grown, key=lambda b: -b[0])[:width]
            if not beams:
                break
        for lp, toks in beams:
            if (word := self._word(toks)) and word not in done:
                done[word] = lp
        return [[w, round(lp, 4)] for w, lp in sorted(done.items(), key=lambda x: -x[1])[:keep]]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("predictions", type=Path, help="a run's predictions.jsonl (arabizi, reference, prediction)")
    parser.add_argument("--set", required=True, help="a name for these rows (dev, dev-others…)")
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8")
    rules = b0.RuleConverter()
    done = set()
    if args.out.exists():
        done = {(r["set"], r["id"], r["k"]) for r in map(json.loads, args.out.read_text("utf-8").splitlines())}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    guesser, n = Guesser(), 0
    with args.out.open("a", encoding="utf-8") as out:
        for line in args.predictions.read_text("utf-8").splitlines():
            row = json.loads(line)
            for k, kind, typed, shown, before, right in C.wrong_words(row, rules):
                if (args.set, row["id"], k) in done:
                    continue
                guesses = guesser.guesses(row["arabizi"], before)
                out.write(json.dumps({"set": args.set, "id": row["id"], "k": k, "kind": kind, "typed_words": typed,
                                      "shown": shown, "ref": right, "guesses": guesses}, ensure_ascii=False) + "\n")
                n += 1
    print(f"{args.set}: {n} wrong words written to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
