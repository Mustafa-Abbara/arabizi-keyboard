"""SPELLING.md v2.0 (18 Nov 2026): the spelling decisions applied to every pair, so the training data, the references
and the rules agree.

1. أ and إ are written ا (انا، اذا، سال). ء, ؤ, ئ and آ are unchanged: ء is not merged with ا.
2. A verb's plural ending is always و, never وا (يعملوا -> يعملو). Words where وا is part of the word keep it (سوا،
   الدوا، الهوا، جوا).
3. A feminine ending is ة (سيارة, never سياره); ه only where it belongs to the word (سفيه، الله). The data already
   follows this (a dry run found 7 words to change, some of them names such as عاليه), so it is not rewritten here.
4. `leh` is ليه and `lesh` is ليش; `hay` is هي.

    uv run --project eval python -m arabizi_eval.spelling_v2 <file.jsonl> ...   rewrite pair files in place
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

HAMZA_ALIF = str.maketrans({"أ": "ا", "إ": "ا"})
PREFIXES = ("وبال", "وال", "بال", "عال", "هال", "لل", "ال", "و", "ب", "ل", "ف", "ع", "ك")
WA_WORDS = {"سوا", "دوا", "هوا", "جوا", "لجوا", "شوا", "كوا", "مكوا"}  # وا belongs to the word
LEH = {"leh", "le", "lei", "leih", "leeh", "leeeh", "lehh"}
LESH = {"lesh", "leysh", "leish", "lech", "lich", "lish", "laysh", "laych", "leshh"}
HAY = {"hay", "hayy", "hai", "hayyy"}
ARABIC_WORD = re.compile(r"[ء-ي]+")


def _core(word: str) -> str:
    for p in PREFIXES:
        if word.startswith(p) and len(word) - len(p) >= 2:
            return word[len(p):]
    return word


def plural_wa(word: str) -> str:
    if word.endswith("وا") and len(word) >= 4 and _core(word) not in WA_WORDS and word not in WA_WORDS:
        return word[:-1]
    return word


class Converter:
    def word(self, word: str) -> str:
        return plural_wa(word.translate(HAMZA_ALIF))

    def text(self, arabic: str) -> str:
        return ARABIC_WORD.sub(lambda m: self.word(m.group(0)), arabic)

    def pair(self, arabizi: str, arabic: str) -> str:
        out = self.text(arabic)
        typed = {w.strip(".,?!") for w in arabizi.lower().split()}
        if typed & LEH and not typed & LESH:
            out = re.sub(r"(?<![ء-ي])ليش(?![ء-ي])", "ليه", out)
        elif typed & LESH and not typed & LEH:
            out = re.sub(r"(?<![ء-ي])ليه(?![ء-ي])", "ليش", out)
        if typed & HAY:
            out = re.sub(r"(?<![ء-ي])هاي(?![ء-ي])", "هي", out)
        return out

    def row(self, row: dict) -> dict:
        row = dict(row)
        for key in ("arabic", "reference"):
            if key in row and isinstance(row[key], str):
                row[key] = self.pair(row.get("arabizi", ""), row[key])
        if isinstance(row.get("accepted"), dict):
            row["accepted"] = {self.text(k): sorted({self.text(v) for v in vs} - {self.text(k)})
                               for k, vs in row["accepted"].items()}
            row["accepted"] = {k: v for k, v in row["accepted"].items() if v}
        return row


def training_converter() -> Converter:
    return Converter()


def main(argv: list[str]) -> int:
    conv = training_converter()
    for name in argv:
        path = Path(name)
        lines = path.read_text(encoding="utf-8").splitlines()
        out, changed = [], 0
        for line in lines:
            if not line.strip():
                out.append(line)
                continue
            row = json.loads(line)
            new = conv.row(row)
            changed += new != row
            out.append(json.dumps(new, ensure_ascii=False) if new != row else line)
        path.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
        print(f"{path}: {changed} of {len(lines)} rows changed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
