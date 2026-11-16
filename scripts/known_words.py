"""Known words: the Arabic words the model has already seen in training, so new data can bring words it hasn't.

Reads ONLY the committed training files (data/pairs/train-*.jsonl). Never dev, test or the others set: a list made
from them would leak held-out words into prompts and new training data.

Words are compared after the scorer's lenient normalization (no diacritics or tatweel; أ/إ/آ → ا, final ى → ي,
final ة → ه), so a spelling-convention difference doesn't make a word look new. A word that only appears with a
different attached prefix (والبيت / البيت / بالبيت) counts as "known in another form".

  uv run --project eval python scripts/known_words.py list [--top 3000]
      writes build/known_words/known_words.tsv (word, count; most frequent first) and
      build/known_words/known_words_top.txt (the top N words, one line, ready to paste into a prompt)

  uv run --project eval python scripts/known_words.py check FILE [--new-only]
      FILE (or - for stdin): plain Arabic words or sentences, one per line, or JSON Lines from the generator
      (uses "rare_words" if present, else "arabic"). Prints, per line, which words are new, known in another
      form, or known. --new-only prints just the new words, de-duplicated, one per line.
"""
import argparse
import collections
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "eval" / "src"))
from arabizi_eval.pairs import normalize_arabic  # the scorer's own normalization

ARABIC_WORD = re.compile(r"[ء-ي]+")
# Attached words at the start of a word, longest first. Only stripped when 3+ letters remain.
PREFIXES = ("وبال", "وال", "بال", "فال", "كال", "عال", "لل", "ال", "و", "ف", "ب", "ل", "ع", "ك")
OUT_DIR = ROOT / "build" / "known_words"


def words(text: str) -> list[tuple[str, str]]:
    """(the word as written, its comparison key) for each Arabic word."""
    return [(w, normalize_arabic(w, lenient=True)) for w in ARABIC_WORD.findall(normalize_arabic(text))]


def base(word: str) -> str:
    """The word with one attached prefix removed (والبيت → بيت), or the word itself."""
    for p in PREFIXES:
        if word.startswith(p) and len(word) - len(p) >= 3:
            return word[len(p):]
    return word


def training_counts() -> tuple[collections.Counter, dict[str, str]]:
    """Counts by comparison key, and each key's most common spelling in training (for display)."""
    files = sorted((ROOT / "data" / "pairs").glob("train-*.jsonl"))
    if not files:
        sys.exit("no data/pairs/train-*.jsonl found")
    counts, spellings = collections.Counter(), collections.defaultdict(collections.Counter)
    for f in files:
        for line in f.read_text(encoding="utf-8").splitlines():
            if line.strip():
                for written, key in words(json.loads(line)["arabic"]):
                    counts[key] += 1
                    spellings[key][written] += 1
    return counts, {k: c.most_common(1)[0][0] for k, c in spellings.items()}


def cmd_list(top: int) -> None:
    counts, shown = training_counts()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ranked = counts.most_common()
    (OUT_DIR / "known_words.tsv").write_text(
        "".join(f"{shown[w]}\t{n}\n" for w, n in ranked), encoding="utf-8")
    (OUT_DIR / "known_words_top.txt").write_text(" ".join(shown[w] for w, _ in ranked[:top]) + "\n",
                                                 encoding="utf-8")
    once = sum(1 for _, n in ranked if n == 1)
    print(f"{len(ranked):,} distinct words ({sum(counts.values()):,} in all; {once:,} seen only once)")
    print(f"wrote {OUT_DIR / 'known_words.tsv'} and the top {min(top, len(ranked)):,} to "
          f"{OUT_DIR / 'known_words_top.txt'}")


def cmd_check(path: str, new_only: bool) -> None:
    counts, _ = training_counts()
    bases = collections.Counter()
    for w, n in counts.items():
        bases[base(w)] += n
    text = sys.stdin.read() if path == "-" else Path(path).read_text(encoding="utf-8")
    new_words: dict[str, None] = {}
    total = {"new": 0, "other form": 0, "known": 0}
    for i, line in enumerate(l for l in text.splitlines() if l.strip()):
        label, source = f"line {i + 1}", line
        if line.lstrip().startswith("{"):
            row = json.loads(line)
            label = row.get("id", label)
            source = " ".join(row["rare_words"]) if row.get("rare_words") else row.get("arabic") or ""
        found = {"new": [], "other form": [], "known": []}
        for written, key in dict.fromkeys(words(source)):
            if counts[key]:
                found["known"].append(f"{written}({counts[key]})")
            elif bases[base(key)]:
                found["other form"].append(written)
            else:
                found["new"].append(written)
                new_words[written] = None
        for k in total:
            total[k] += len(found[k])
        if not new_only:
            parts = [f"{k}: {' '.join(v)}" for k, v in found.items() if v]
            print(f"{label}\t" + (" | ".join(parts) if parts else "(no Arabic words)"))
    if new_only:
        print("\n".join(new_words))
    else:
        print(f"\nnew {total['new']}, known in another form {total['other form']}, known {total['known']} "
              f"({len(new_words)} distinct new words)")


def main() -> None:
    for stream in (sys.stdin, sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8")  # Arabic through a Windows console or pipe
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_list = sub.add_parser("list", help="write the known-words list")
    p_list.add_argument("--top", type=int, default=3000, help="how many words go in the paste-ready file")
    p_check = sub.add_parser("check", help="which words in FILE are new")
    p_check.add_argument("file", help="a file, or - for stdin")
    p_check.add_argument("--new-only", action="store_true", help="print only the new words")
    a = ap.parse_args()
    if a.cmd == "list":
        cmd_list(a.top)
    else:
        cmd_check(a.file, a.new_only)


if __name__ == "__main__":
    main()
