"""Build the synthetic (AI-written) training data for v4 from the generator outputs, with a held-out test slice.

Inputs: any mix of folders, .zip files and the breaker .xlsx. Every `<M><R>_chat_<N>.jsonl` inside them is a run of
the agent packs (M = machine A/B/C, R = round: "" for 1, "2", "3"...); the .xlsx is the breaker file.

What it does, in order:
  1. reads every row and labels its group (machine + round, or breaker) and kind;
  2. cleans: Latin letters with marks in the Arabizi become the plain letter (é -> e), Arabic diacritics and
     tatweel removed, Arabic-Indic digits become Western, Arabic prefixes glued to Latin words split (SPELLING.md 4),
     and the v2.0 spelling applied (أ / إ written ا, a verb plural وا written و);
  3. drops rows that fail the repo's own row checks (pairs.row_errors), rows whose Arabic has a Latin word not typed in
     the Arabizi, rows with a word count outside 0.5x-2x, breaker rows marked "convention only" or ok = no, and rows
     whose context round used the two test-set example words;
  4. drops anything equal to or near (>= 80% of words, >= 4 words) a dev or test row, anything equal to a training row,
     and repeats inside the synthetic data (the first copy is kept);
  5. holds out a test slice per group and kind: the breaker's own "probe" rows, plus 10% of every other group chosen by
     a hash of the pair's target word (or of the sentence when it has none). The hash makes the split stable: adding
     new inputs later never moves an existing row between train and test, and every row with the same target word
     lands on the same side;
  6. writes the train rows in the pair schema (method ai_checked, checked_by CHECKED_BY) and the test rows with their group.

Nothing in data/ is touched. Output (default build/v4_data/):
  train-ai_checked.synthetic.jsonl   train rows, pair schema; `source` records group, run, original id and kind
  synthetic_test.jsonl               held-out rows: id, arabizi, arabic, accepted, group, kind, source
  REPORT.md                          counts per group and kind, what was dropped and why, the ADR 0010 cap

  uv run --project eval --with openpyxl python scripts/build_synthetic_dataset.py <input> [<input> ...] [--out DIR]
"""
import argparse
import collections
import hashlib
import io
import json
import re
import sys
import unicodedata
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "eval" / "src"))
from arabizi_eval import metrics as M
from arabizi_eval import pairs as P
from arabizi_eval.spelling_v2 import Converter

HOLDOUT = 0.10
DATE = "2026-11-14"
# The models used across the runs (which run used which was not recorded), and who checked every row.
WRITER = "ai: sol-6.1, fable-5.2, opus-5.5, sonnet-5.5 (per-run model not recorded)"
CHECKED_BY = "moustafa"
BREAKER_KIND = {"new form of a known word": "inflect", "low-frequency word": "low", "new vocabulary": "new",
                "common word, unusual spelling": "common", "context word / spelling trap": "context",
                "common words only": "plain"}
TEST_WORDS = re.compile("طلع|ثواني|تلعب")  # examples taken from the test error table (removed from later packs)
RUN_FILE = re.compile(r"(?:^|/)([A-Z])(\d*)_chat_\d+\.jsonl$")


HEAVY_DIGIT = re.compile(r"6'|[69]")


# Which Arabic letters each Arabizi unit can stand for (for lining a word up letter by letter).
UNIT_LETTERS = {
    "sh": "ش", "ch": "ش", "kh": "خ", "gh": "غ", "th": "ثت", "dh": "ذض", "ou": "و", "oo": "و", "ee": "ي", "aa": "ا",
    "b": "ب", "p": "ب", "t": "تط", "j": "ج", "g": "جغق", "7": "ح", "h": "هحة", "5": "خ", "d": "دض", "r": "ر",
    "z": "زظذ", "s": "سصث", "3": "ع", "8": "غق", "f": "ف", "v": "ف", "q": "ق", "2": "قءأإئؤآ", "k": "كق", "l": "ل",
    "m": "م", "n": "ن", "w": "و", "y": "يى", "x": "كس",
    "a": "اىةهآأ", "e": "ةهيإ", "i": "يإ", "o": "وأ", "u": "و",
    "6": "طظضتصدز", "6'": "ظ", "9": "صقسض",
}
VOWEL_UNITS = {"a", "e", "i", "o", "u", "y", "w", "ou", "oo", "ee", "aa"}
# The plain letter a typist uses for the Arabic letter a 6 or 9 stood for.
PLAIN = {"ط": "t", "ت": "t", "ظ": "z", "ز": "z", "ذ": "z", "ض": "d", "د": "d", "ص": "s", "س": "s", "ث": "s", "ق": "2"}


def units(word):
    out, i, w = [], 0, word.lower()
    while i < len(w):
        two = w[i:i + 2]
        if two in UNIT_LETTERS:
            out.append(two); i += 2
        else:
            out.append(w[i]); i += 1
    return out


def align(word, arabic_word):
    """Line up an Arabizi word with an Arabic word. Returns (cost, {unit index: Arabic letter}) for the 6/9 units."""
    u, a = units(word), [c for c in arabic_word if "ء" <= c <= "ي" or c in "آأإؤئ"]
    n, m = len(u), len(a)
    INF = float("inf")
    cost = [[INF] * (m + 1) for _ in range(n + 1)]
    back = [[None] * (m + 1) for _ in range(n + 1)]
    cost[0][0] = 0
    for i in range(n + 1):
        for j in range(m + 1):
            c = cost[i][j]
            if c == INF:
                continue
            if i < n and j < m:  # unit i stands for letter j
                ok = a[j] in UNIT_LETTERS.get(u[i], "")
                step = 0 if ok else (1.5 if u[i] in VOWEL_UNITS or a[j] in "اويىةه" else 3)
                if c + step < cost[i + 1][j + 1]:
                    cost[i + 1][j + 1], back[i + 1][j + 1] = c + step, (i, j, "pair")
            if i < n:  # unit with no letter (short vowels, doubled letters)
                step = 0.2 if u[i] in VOWEL_UNITS else (0.6 if i and u[i] == u[i - 1] else 3)
                if c + step < cost[i + 1][j]:
                    cost[i + 1][j], back[i + 1][j] = c + step, (i, j, "unit")
            if j < m:  # letter with no unit (long vowels left out, the article's alif)
                step = 0.4 if a[j] in "اويىةه" else 2
                if c + step < cost[i][j + 1]:
                    cost[i][j + 1], back[i][j + 1] = c + step, (i, j, "letter")
    pairs, i, j = {}, n, m
    while (i, j) != (0, 0):
        pi, pj, kind = back[i][j]
        if kind == "pair" and u[pi] in ("6", "9", "6'"):
            pairs[pi] = a[pj]
        i, j = pi, pj
    return cost[n][m], pairs, u


def fix_heavy_digits(arabizi: str, arabic: str, stats: collections.Counter | None = None) -> str:
    """Real typists never write 6 or 9 as letters (0% in the real dev rows). Each 6 or 9 inside a word is lined up
    with the Arabic letter it stands for and replaced by the plain Latin letter for that letter: ط/ت -> t, ظ/ز/ذ -> z,
    ض/د -> d, ص/س/ث -> s, ق -> 2. If no Arabic letter can be found, 6 -> t and 9 -> s. Numbers are left alone."""
    stats = stats if stats is not None else collections.Counter()
    a_words = [w for w in M.tokens(arabic) if re.search("[ء-ي]", w)]
    out = []
    for w in arabizi.split():
        core = w.strip(M.PUNCTUATION)
        if not core or not re.search(r"[A-Za-z]", core) or not re.search(r"[69]", core) or P.NUMBER.fullmatch(core):
            out.append(w); continue
        best = min((align(core, aw) for aw in a_words), key=lambda x: x[0], default=None)
        u = units(core)
        letters = best[1] if best and best[0] <= 2.5 * len(u) else {}
        new = []
        for i, unit in enumerate(u):
            if unit in ("6", "9", "6'"):
                letter = PLAIN.get(letters.get(i, ""))
                if letter is None:
                    letter = {"6": "t", "6'": "z", "9": "s"}[unit]
                    stats["no matching Arabic letter (default used)"] += 1
                else:
                    stats[f"{unit} = {letters[i]} -> {letter}"] += 1
                new.append(letter)
            else:
                new.append(unit)
        fixed = "".join(new)
        # keep the typed capitals: units() lower-cases, so restore the case letter by letter where lengths agree
        if len(fixed) == len(core):
            fixed = "".join(f.upper() if c.isupper() else f for f, c in zip(fixed, core))
        out.append(w.replace(core, fixed))
    return " ".join(out)


def plain_latin(text: str) -> str:
    """é -> e, ç -> c ...: strip combining marks from Latin letters only."""
    out = []
    for ch in unicodedata.normalize("NFD", text):
        if unicodedata.combining(ch) and out and out[-1].isascii():
            continue
        out.append(ch)
    return unicodedata.normalize("NFC", "".join(out))


SPELLING_V2 = Converter()  # SPELLING.md v2.0: no أ / إ, plural و (generators may still slip)


def clean_arabic(text: str) -> str:
    text = P.normalize_arabic(text)
    text = re.sub("[٠-٩]", lambda m: str(ord(m[0]) - 0x660), text)
    text = re.sub("[۰-۹]", lambda m: str(ord(m[0]) - 0x6F0), text)
    return SPELLING_V2.text(" ".join(P.split_glued_prefixes(text).split()))


def key_text(s: str) -> str:
    return " ".join(re.sub(r"[^\w\s]", " ", (s or "").lower()).split())


def lenient(w: str) -> str:
    return P.normalize_arabic(w, lenient=True)


def parse_accepted(value, arabic: str) -> dict:
    """'a=b|c; d=e' -> {a: [b, c], d: [e]}, keeping only primaries that occur in the Arabic."""
    out = {}
    for part in str(value or "").split(";"):
        if "=" not in part:
            continue
        primary, others = part.split("=", 1)
        primary = clean_arabic(primary.strip()) if re.search("[ء-ي]", primary) else primary.strip()
        alts = [a.strip() for a in others.split("|") if a.strip() and a.strip() != primary]
        if primary and alts and primary in arabic:
            out[primary] = alts
    return out


# ---------- reading ----------
def iter_inputs(paths):
    """(container name, inner path, bytes) for every file in the inputs."""
    for p in map(Path, paths):
        if p.is_dir():
            for f in sorted(p.rglob("*")):
                if f.suffix == ".zip":
                    yield from iter_inputs([f])
                elif f.is_file():
                    yield p.name, f.relative_to(p).as_posix(), f.read_bytes()
        elif p.suffix == ".zip":
            with zipfile.ZipFile(p) as z:
                for n in sorted(z.namelist()):
                    if not n.endswith("/"):
                        yield p.stem, n, z.read(n)
        elif p.is_file():
            yield p.parent.name, p.name, p.read_bytes()


def read_rows(paths):
    rows, seen_files = [], set()
    for container, inner, data in iter_inputs(paths):
        m = RUN_FILE.search(inner)
        if m:
            digest = hashlib.sha256(data).hexdigest()
            if digest in seen_files:  # the same file delivered twice
                continue
            seen_files.add(digest)
            group = f"{m[1]}{m[2] or '1'}"
            for n, line in enumerate(data.decode("utf-8").splitlines(), 1):
                if not line.strip():
                    continue
                try:
                    r = json.loads(line)
                except json.JSONDecodeError:
                    rows.append({"_drop": "bad JSON", "_where": f"{container}/{inner}:{n}"}); continue
                rare = r.get("rare_words") or []
                rows.append({"arabizi": r.get("arabizi") or "", "arabic": r.get("arabic") or "", "accepted": {},
                             "group": group, "kind": r.get("kind") or "?", "run": container,
                             "orig_id": r.get("id") or f"{inner}:{n}", "target": rare[0] if rare else "",
                             "fallback": any("fallback" in str(c).lower() for c in r.get("check") or []),
                             "split_hint": None, "v3": None})
        elif inner.endswith(".xlsx") or (inner.endswith(".jsonl") and "breaker" in inner):
            if inner.endswith(".xlsx"):
                import openpyxl
                ws = openpyxl.load_workbook(io.BytesIO(data), read_only=True).worksheets[0]
                it = ws.iter_rows(values_only=True)
                head = next(it)
                records = [dict(zip(head, r)) for r in it]
            else:
                records = [json.loads(line) for line in data.decode("utf-8").splitlines() if line.strip()]
            for r in records:
                if isinstance(r.get("accepted"), dict):  # the jsonl form: {primary: [variants]}
                    r["accepted"] = "; ".join(f"{k}={'|'.join(v)}" for k, v in r["accepted"].items())
                if not r.get("arabizi"):
                    continue
                arabic = str(r.get("arabic") or "")
                row = {"arabizi": str(r["arabizi"]), "arabic": arabic, "accepted": r.get("accepted"),
                       "group": "breaker", "kind": BREAKER_KIND.get(r.get("kind"), r.get("kind") or "?"),
                       "run": f"breaker batch {r.get('batch')}", "orig_id": None,
                       "target": str(r.get("kind_words") or "").split(",")[0].strip(), "fallback": False,
                       "split_hint": r.get("split"), "v3": r.get("v3_result")}
                ok = str(r.get("ok")).strip().lower() if r.get("ok") is not None else ""
                if ok in ("no", "n", "0", "false", "x", "wrong", "bad", "drop"):
                    row["_drop"] = "marked not ok in the breaker file"
                elif r.get("v3_result") == "convention only":
                    row["_drop"] = "breaker: v3 differed only by spelling convention"
                rows.append(row)
    return rows


# ---------- checks ----------
def held_out_rows():
    files = [P.PAIRS_DIR / "dev.jsonl", P.PAIRS_DIR / "test.jsonl", P.OTHERS_DIR / "dev.jsonl", P.OTHERS_DIR / "test.jsonl"]
    return [r for f in files if f.exists() for _, r, _ in P.read_jsonl(f) if r]


def training_rows():
    return [r for f in sorted(P.PAIRS_DIR.glob("train-*.jsonl")) for _, r, _ in P.read_jsonl(f) if r]


class NearIndex:
    """Sentences as word sets, with an index from word to sentence, for the >= 80% overlap check."""

    def __init__(self):
        self.sets, self.index = [], collections.defaultdict(list)

    def add(self, text):
        words = set(key_text(text).split())
        i = len(self.sets)
        self.sets.append(words)
        for w in words:
            self.index[w].append(i)

    def near(self, text):
        words = set(key_text(text).split())
        if len(words) < 4:
            return False
        # candidates come from the rarer words (a near copy shares most words, so it shares rare ones too)
        rare = sorted(words, key=lambda w: len(self.index.get(w, ())))[: max(2, len(words) // 2)]
        hits = collections.Counter(i for w in rare for i in self.index.get(w, ()))
        hits = {i: len(words & self.sets[i]) for i in hits}
        return any(n / max(len(words), len(self.sets[i])) >= 0.8 for i, n in hits.items() if len(self.sets[i]) >= 4)


def latin_ok(arabizi, arabic):
    typed = arabizi.lower()
    return all(w.lower() in typed for w in re.findall(r"[A-Za-z]+", arabic))


def target_key(row):
    return "w:" + lenient(row["target"]) if row["target"] else "s:" + key_text(row.get("key_arabizi", row["arabizi"]))


def holdout_key(row):
    """Stable: the same target word is held out (or not) in every group and every future build."""
    return int(hashlib.sha256(target_key(row).encode()).hexdigest(), 16) % 1000 < HOLDOUT * 1000


def new_id(row, used):
    base = f"{row['group']}|{row['run']}|{row['orig_id'] or key_text(row.get('key_arabizi', row['arabizi']))}"
    n = int(hashlib.sha256(base.encode()).hexdigest(), 16) % 10**10
    while f"ai-{n:010d}" in used:
        n = (n + 1) % 10**10
    used.add(f"ai-{n:010d}")
    return f"ai-{n:010d}"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--out", default=str(ROOT / "build" / "v4_data"))
    ap.add_argument("--previous", action="append", default=[],
                    help="an earlier build's folder: its train rows stay train and its test rows stay test, and new rows "
                         "never put into test a word or sentence an earlier model trained on (repeatable)")
    a = ap.parse_args()
    prev_train, prev_test = set(), set()
    for d in a.previous:
        prev_train |= {json.loads(x)["id"] for x in (Path(d) / "train-ai_checked.synthetic.jsonl").read_text(encoding="utf-8").splitlines() if x.strip()}
        prev_test |= {json.loads(x)["id"] for x in (Path(d) / "synthetic_test.jsonl").read_text(encoding="utf-8").splitlines() if x.strip()}
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8")

    rows = read_rows(a.inputs)
    held = held_out_rows()
    train = training_rows()
    held_z, held_a = {key_text(r["arabizi"]) for r in held}, {key_text(r["arabic"]) for r in held}
    held_near = NearIndex()
    for r in held:
        held_near.add(r["arabizi"])
    train_z = {key_text(r["arabizi"]) for r in train}
    msa = M.msa_words()

    seen_z, seen_a = set(), set()
    kept, drops = [], collections.Counter()
    used = set()
    accents = digits = 0
    digit_stats = collections.Counter()
    for r in rows:
        if "_drop" in r:
            drops[r["_drop"]] += 1; continue
        z0 = r["arabizi"].strip()
        z = plain_latin(z0)
        accents += z != z0
        arabic = clean_arabic(r["arabic"])
        # the held-out split hashes the sentence (when there is no target word) as it was before the 6/9 fix, so
        # fixing digits never moves a row between train and test
        r["key_arabizi"] = z
        z_fixed = fix_heavy_digits(z, arabic, digit_stats)
        digits += z_fixed != z
        z = z_fixed
        r["arabizi"], r["arabic"] = z, arabic
        r["accepted"] = parse_accepted(r["accepted"], arabic) if r["group"] == "breaker" else {}
        probe = {"id": "ai-0000", "arabizi": z, "arabic": arabic, "accepted": r["accepted"], "method": "ai_checked",
                 "writer": "x", "checked_by": "placeholder", "source": "x", "split": "train", "date": DATE}
        errs = P.row_errors(probe)
        reason = None
        if errs:
            reason = "repo row check: " + errs[0].split(":")[0]
        elif not latin_ok(z, arabic):
            reason = "Latin word in the Arabic that was not typed"
        elif not 0.5 <= len(M.tokens(arabic)) / max(len(M.tokens(z)), 1) <= 2:
            reason = "word count outside 0.5x-2x"
        elif r["kind"] == "context" and r["group"] == "C1" and TEST_WORDS.search(arabic):
            reason = "context round used a test-set example word"
        elif key_text(z) in held_z or key_text(arabic) in held_a:
            reason = "same as a dev/test row"
        elif held_near.near(z):
            reason = "near-duplicate of a dev/test row"
        elif key_text(z) in train_z:
            reason = "same Arabizi as an existing training row"
        elif key_text(z) in seen_z or key_text(arabic) in seen_a:
            reason = "repeat inside the synthetic data"
        if reason:
            drops[reason] += 1; continue
        seen_z.add(key_text(z)); seen_a.add(key_text(arabic))
        r["msa"] = any(lenient(t) in msa for t in M.tokens(arabic))
        # the breaker file already holds its own test slice (its "probe" rows); every other group: 10% by target word
        r["test"] = r["split_hint"] == "probe" if r["group"] == "breaker" else holdout_key(r)
        r["rid"] = new_id(r, used)
        # an earlier build's split is frozen: its train rows stay train, its test rows stay test
        r["fixed"] = r["rid"] in prev_train or r["rid"] in prev_test
        if r["fixed"]:
            r["test"] = r["rid"] in prev_test
        kept.append(r)

    # a word held out anywhere is held out everywhere (the breaker's probe rows choose their own words), but a word an
    # earlier model trained on can never become a test word: new rows with such a word stay in train
    old_train_targets = {target_key(r) for r in kept if r["fixed"] and not r["test"] and r["target"]}
    old_test_targets = {target_key(r) for r in kept if r["fixed"] and r["test"] and r["target"]}
    for r in kept:
        if not r["fixed"] and r["target"]:
            if target_key(r) in old_train_targets:
                r["test"] = False
            elif target_key(r) in old_test_targets:
                r["test"] = True
    test_targets = {target_key(r) for r in kept if r["test"] and r["target"]}
    moved = 0
    for r in kept:
        if not r["fixed"] and not r["test"] and r["target"] and target_key(r) in test_targets:
            r["test"] = True; moved += 1
    # no new test row may near-copy a sentence an earlier model trained on
    old_train_near = NearIndex()
    for r in kept:
        if r["fixed"] and not r["test"]:
            old_train_near.add(r["arabizi"])
    kept2 = []
    for r in kept:
        if r["test"] and not r["fixed"] and old_train_near.near(r["arabizi"]):
            drops["new test row near-copies a row an earlier model trained on"] += 1; continue
        kept2.append(r)
    kept = kept2
    # a test sentence must not be near-copied in train, and train rows must not near-copy each other
    # (rows an earlier build already settled are kept as they were)
    test_near, train_near = NearIndex(), NearIndex()
    for r in kept:
        if r["test"]:
            test_near.add(r["arabizi"])
        elif r["fixed"]:
            train_near.add(r["arabizi"])
    final = []
    for r in kept:
        if not r["test"] and not r["fixed"]:
            if test_near.near(r["arabizi"]):
                drops["train row near-copies a held-out test row"] += 1; continue
            if train_near.near(r["arabizi"]):
                drops["train row near-copies another train row"] += 1; continue
            train_near.add(r["arabizi"])
        final.append(r)

    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    train_out, test_out = [], []
    for r in final:
        rid = r["rid"]
        tag = (f"synthetic {r['group']} run={r['run']} orig={r['orig_id'] or '-'} kind={r['kind']}"
               + (f" v3={r['v3']}" if r["v3"] else "") + (" fallback" if r["fallback"] else ""))
        if r["test"]:
            test_out.append({"id": rid, "arabizi": r["arabizi"], "arabic": r["arabic"], "accepted": r["accepted"],
                             "group": ("breaker-probe" if r["split_hint"] == "probe" else "breaker")
                             if r["group"] == "breaker" else r["group"], "kind": r["kind"],
                             "source": tag})
        else:
            writer = WRITER
            train_out.append({"id": rid, "arabizi": r["arabizi"], "arabic": r["arabic"], "accepted": r["accepted"],
                              "method": "ai_checked", "writer": writer, "checked_by": CHECKED_BY, "source": tag,
                              "split": "train", "date": DATE})
    ai_old = sum(1 for r in train if r["method"] == "ai_checked")
    cap_max = max(0, len(train) - 2 * ai_old)  # (ai_old + x) / (len(train) + x) <= 0.5

    def priority(x):
        src = x["source"]
        kind = re.search(r"kind=(\w+)", src)[1]
        broke = " v3=broke" in src
        rank = 0 if broke else {"new": 1, "inflect": 2, "low": 3, "common": 4, "traps": 5, "context": 6, "plain": 7}.get(kind, 8)
        if " v3=pass" in src:
            rank += 4  # the breaker rows v3 already gets right teach little
        return rank, x["id"]
    # First every breaker row v3 got wrong, then the rest shared out by kind in proportion to v3's measured dev errors
    # (new forms 26%, rarely seen words 26%, new vocabulary 19%, common words 25% -> unusual spellings, traps, context),
    # so no kind crowds out the others; a kind with too few rows passes its share on.
    QUOTA = {"inflect": 0.28, "low": 0.28, "new": 0.22, "common": 0.12, "traps": 0.05, "context": 0.03, "plain": 0.02}
    ordered = sorted(train_out, key=priority)
    first = [x for x in ordered if " v3=broke" in x["source"]][:cap_max]
    rest = collections.defaultdict(list)
    for x in ordered:
        if " v3=broke" not in x["source"]:
            rest[re.search(r"kind=(\w+)", x["source"])[1]].append(x)
    picked, room = list(first), cap_max - len(first)
    while room > 0 and any(rest.values()):
        live = {k: q for k, q in QUOTA.items() if rest.get(k)} or {k: 1 for k in rest if rest[k]}
        total = sum(live.values())
        take = {k: max(1, int(room * q / total)) for k, q in live.items()}
        for k, n in take.items():
            n = min(n, room, len(rest[k]))
            picked += rest[k][:n]; rest[k] = rest[k][n:]; room -= n
    capped = sorted(picked, key=lambda x: x["id"])
    for name, data in (("train-ai_checked.synthetic.jsonl", train_out), ("train-ai_checked.synthetic.capped.jsonl", capped),
                       ("synthetic_test.jsonl", test_out)):
        (out / name).write_text("".join(json.dumps(x, ensure_ascii=False) + "\n" for x in data), encoding="utf-8")

    # ---------- report ----------
    tr = collections.Counter((r["group"], r["kind"]) for r in final if not r["test"])
    te = collections.Counter((r["group"], r["kind"]) for r in final if r["test"])
    groups = sorted({g for g, _ in tr} | {g for g, _ in te})
    kinds = sorted({k for _, k in tr} | {k for _, k in te})
    real = sum(1 for r in train if r["method"] != "ai_checked")
    n_new = len(train_out)
    share = (ai_old + n_new) / (len(train) + n_new)
    capped_kinds = collections.Counter(re.search(r"kind=(\w+)", x["source"])[1] for x in capped)
    lines = [
        "# Synthetic data for v4: build report", "",
        f"Inputs: {len(rows):,} rows read ({sum(1 for r in rows if r['group'] == 'breaker'):,} from the breaker file). "
        f"Kept {len(final):,}: **{n_new:,} train**, **{len(test_out):,} held out for testing**. "
        f"Latin letters with marks replaced by the plain letter (é -> e, ç -> c) in {accents:,} Arabizi messages. "
        f"Digits 6 and 9 used as letters replaced by the plain letter for the Arabic letter they stand for (in "
        f"{digits:,} messages).", "",
        "Each 6 or 9 was lined up with the Arabic letter it stands for: "
        + ", ".join(f"{k} ({v:,})" for k, v in digit_stats.most_common()) + ".", "",
        "## Dropped", "", "| Reason | Rows |", "|---|---|",
        *[f"| {k} | {v:,} |" for k, v in drops.most_common()], "",
        "## Train / held-out test by group and kind", "",
        "| Group | " + " | ".join(kinds) + " | total |", "|---|" + "---|" * (len(kinds) + 1),
    ]
    for g in groups:
        cells = [f"{tr[(g, k)]}/{te[(g, k)]}" if tr[(g, k)] or te[(g, k)] else "" for k in kinds]
        lines.append(f"| {g} | " + " | ".join(cells)
                     + f" | {sum(tr[(g, k)] for k in kinds):,}/{sum(te[(g, k)] for k in kinds):,} |")
    lines += [
        "", "Cells are train/test. Groups: A1 = machine A round 1, B2 = machine B round 2, and so on; breaker = the "
        "breaker file (its `probe` rows are all in test, as `breaker-probe`). About 10% of the target words are held out, "
        "chosen by a hash of the word, and every row with a held-out target word is in test, whatever its group: "
        f"no train row targets a test word ({moved:,} rows moved to test for that). Rows without a target word are held "
        "out by a hash of the sentence.",
        "", "## ADR 0010 cap (AI-generated rows at most half of the training rows)", "",
        f"Current training rows: {len(train):,} ({ai_old:,} ai_checked, {real:,} other). "
        f"Adding all {n_new:,} new train rows gives an AI share of **{share:.0%}**. "
        f"The most new rows that keep it at or under 50% is **{cap_max:,}**.", "",
        "`train-ai_checked.synthetic.capped.jsonl` holds that many: first every breaker row v3 got wrong, then the rest "
        "shared out by kind in proportion to v3's measured dev errors (new forms 28%, rarely seen words 28%, new "
        "vocabulary 22%, unusual spellings 12%, traps 5%, context 3%, plain 2%), breaker rows v3 already got right last "
        "within each kind. By kind: "
        + ", ".join(f"{k} {v:,}" for k, v in capped_kinds.most_common()) + ".", "",
        "## Before training", "",
        f"- Every train row: checked_by `{CHECKED_BY}`, writer `{WRITER}`.",
        "- Record the prompts and the four models in `docs/DATA.md`.",
        f"- {sum(1 for r in final if r['msa']):,} kept rows contain a word from the MSA list; worth a look.",
        f"- {sum(1 for r in final if r['fallback']):,} kept rows are agent 'fallback' pairs (ordinary pairs where the "
        "round's rule could not be met); their `source` ends in `fallback`.",
        "- Keep `ai_variants` at 1 (the export default) so the AI rows don't get two rule-made variants each.",
    ]
    (out / "REPORT.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
