"""Typing simulation for incremental conversion (ADR 0037): each dev message is sent to the engine one word longer
at a time, as the live preview does, once with incremental conversion and once with every text converted on its own
(arabizi-cli --no-incremental). Prints times, word accuracy of the whole messages and how many differ; writes the
whole messages' answers to a JSON file. Dev sets only.

  swift build -c release --package-path Packages/ArabiziEngine --product arabizi-cli
  uv run --project eval python scripts/typing_simulation.py . <path to arabizi-cli> out.json 200
"""
import json, random, subprocess, sys, time, uuid
from pathlib import Path

ROOT = Path(sys.argv[1]); CLI = sys.argv[2]; OUT = Path(sys.argv[3]); N = int(sys.argv[4])
sys.path.insert(0, str(ROOT / "eval" / "src"))
from arabizi_eval.metrics import aggregate, score_sentence

rows = [json.loads(l) for f in ("data/pairs/dev.jsonl", "data/pairs/others/dev.jsonl")
        for l in (ROOT / f).read_text(encoding="utf-8").splitlines() if l.strip()]
random.Random(2026).shuffle(rows)
rows = rows[:N]
q = lambda v, x: sorted(v)[min(len(v) - 1, int(len(v) * x))]
result = {}
for mode, extra in (("incremental", []), ("on its own", ["--no-incremental"])):
    p = subprocess.Popen([CLI, "--config", str(ROOT / "config"), "--rules", str(ROOT / "data/rules"), "--models",
                          str(ROOT / "models"), *extra], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True, encoding="utf-8", bufsize=1)
    p.stderr.readline()

    def ask(text):
        p.stdin.write(json.dumps({"v": 1, "id": str(uuid.uuid4()), "text": text, "deadlineMs": 10000}, ensure_ascii=False) + "\n")
        p.stdin.flush()
        t = time.perf_counter()
        r = json.loads(p.stdout.readline())
        return r, (time.perf_counter() - t) * 1000

    ask("kifak ya zalame")
    steps, lasts, finals, scores, outcomes = [], [], {}, [], {}
    for r in rows:
        words = r["arabizi"].split()
        for n in range(1, len(words) + 1):
            resp, ms = ask(" ".join(words[:n]))
            steps.append(ms)
        lasts.append(ms)
        finals[r["id"]] = resp["text"]
        outcomes[resp["outcome"]] = outcomes.get(resp["outcome"], 0) + 1
        scores.append(score_sentence(r, resp["text"]))
    p.stdin.close(); p.wait(timeout=30)
    result[mode] = finals
    print(f"{mode}: {len(rows)} messages, {len(steps)} requests; every step p50 {q(steps, .5):.0f} p95 {q(steps, .95):.0f} ms; "
          f"whole message (last step) p50 {q(lasts, .5):.0f} p95 {q(lasts, .95):.0f} max {max(lasts):.0f} ms; "
          f"word acc {aggregate(scores)['word_accuracy']:.4f}; outcomes {outcomes}", flush=True)
a, b = result["incremental"], result["on its own"]
differ = [i for i in a if a[i] != b[i]]
words = sum(1 for i in differ for x, y in zip(a[i].split(), b[i].split()) if x != y)
print(f"final answers that differ: {len(differ)} of {len(a)} messages ({words} words where the lengths match)")
OUT.write_text(json.dumps(result, ensure_ascii=False), encoding="utf-8")
