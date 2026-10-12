# ADR 0009: Resolving conflicts between ROADMAP and QUESTIONS_BEFORE_BUILDING

- **Status:** accepted (2026-10-10). The team may override any row with a new ADR that names the Dn it replaces. **Partly paused by [ADR 0010](0010-phase1-pivot.md) (12 Oct 2026):** this ADR was written for the v1 roadmap, now [archive/ROADMAP_v1_agentic.md](../archive/ROADMAP_v1_agentic.md). Decisions about the resolver, GBNF output, ask policy, calibration and memory apply only if Phase 2 starts; ADR 0010 lists what still applies.
- **Deciders:** Claude's recommendation, adopted at Moustafa's request

`docs/ROADMAP.md` and `docs/QUESTIONS_BEFORE_BUILDING.md` disagreed on the 25 points below (D1–D25), and the questions doc filled 4 gaps. Each one is now decided. Every decision is applied in `docs/ROADMAP.md`, at the spot it changes, tagged `[Dn — Claude's recommendation]`. Where this ADR and the questions doc disagree, this ADR wins.

**Every decision below is Claude's recommendation.** The *Follows* column shows whether it sides with the roadmap, the questions doc, a combination of both, or neither.

## Applies from Week 1–2

Needed before the S2 IME spike, the S3 model bake-off and the S4 skeleton.

| ID | Topic | Stage | Owner | Roadmap said | Questions doc said | Decision (Claude's recommendation) | Follows |
|---|---|---|---|---|---|---|---|
| D1 | Candidate window | S2 → S9 | Omar | Build your own non-activating `NSPanel`. Avoid Apple's `IMKCandidates` (reported rendering glitches on macOS 26; Apple's own NumberInput sample avoids it). Planned as ADR 0002. | Q35: use `IMKCandidates` for top-k word choices; a custom panel only for the ask chooser, and only if `IMKCandidates` proves too limited. | Spend half a day of the S2 spike trying `IMKCandidates` on your actual macOS version. Default to your own panel: one UI for both word choices and the ask chooser means one code path to test. Record the result in ADR 0002. | Roadmap |
| D2 | Model shortlist | S3 | Mohamad | Bake off 4 models: Qwen2.5-0.5B, Qwen2.5-1.5B, Llama 3.2 1B, Gemma 3 1B. | Q50: Qwen2.5-1.5B primary, 0.5B fallback. Drop Llama 3.2 1B (Arabic not officially supported). Test Gemma 3 1B before trusting it. Avoid Qwen2.5-3B (non-commercial licence). | Keep all four in the bake-off. Each is one scripted run, and a measured result ("Llama 3.2 1B scores X on Lebanese") defends the choice better than citing a model card. Run them one at a time on the 8 GB Air. Never consider Qwen2.5-3B. | Roadmap |
| D3 | Apple Foundation Models baseline | S3 | Mohamad | Optional comparison if a team Mac supports Apple Intelligence. | Q49: ruled out. Apple Intelligence does not support Arabic. | Drop it. Write one line in ADR 0003 saying why, with the source. | Questions doc |
| D4 | Quantization | S3 | Mohamad | Q4_K_M only. | Q51: also compare Q8_0; keep it only if it gains ≥ 2 points within the latency budget. | Compare Q8_0 for the 0.5B model only. By my estimate, Q8_0 of the 1.5B model (about 1.6 GB of weights) already exceeds the 1.5 GB engine RSS budget, so it cannot ship. | Combined |
| D5 | CI Xcode version | S4 | Omar | CI jobs use `runs-on: macos-latest`. | Q31: build in CI with Xcode 26.x / Swift 6.3, because CodeQL may not yet support Xcode 27 / Swift 6.4. | Pin a specific macOS runner image and select the Xcode version explicitly. `macos-latest` can move under you. Check CodeQL's supported-versions page when writing the workflow. | Questions doc |
| D6 | Repository layout | S4 | Omar | `Packages/` (Contracts, Core, LLM, Memory, Telemetry), `Apps/` (IME, EngineXPC), `Tools/arabizi-cli`, `eval/`, `data/`, `config/`. | Q92: `ime/`, `resolver-xpc/`, `Engine/`, `eval/`, `data/`, `docs/`. | Use the roadmap's layout. Separate packages give the separation of concerns and per-package tests the software-engineering mark looks for, and CODEOWNERS already uses it. | Roadmap |
| D7 | Config file format | S4–S5 | Team | JSON: `config/engine.json`, `rules_v1.json`, `app_profiles.json`, decoded with `Codable`. | Q42 / Q92: a YAML rules table and one `config.yaml`. | JSON. Foundation decodes it natively, so the sandboxed engine needs no third-party YAML parser (one less dependency to scan). JSON has no comments, so document fields in the JSON Schema. | Roadmap |
| D8 | Where regression cases live | S4 → S11 | Team | `eval/regression/cases.jsonl`. | Q87: `tests/regression/`. | The roadmap's path, so cases sit next to the eval harness that runs them. Low stakes; just pick one. | Roadmap |

## Applies from Week 3

Needed before the deterministic engine (S5) is built.

| ID | Topic | Stage | Owner | Roadmap said | Questions doc said | Decision (Claude's recommendation) | Follows |
|---|---|---|---|---|---|---|---|
| D9 | Fast-path rule (skip the LLM) | S5 | Mohamad | Commit without the LLM when every slot has `p(top1) ≥ tau_fast` (e.g. 0.9) and no conflicting memory entry. | Q48: when the top-1 *margin* is ≥ τ, with τ tuned on dev so fast-path precision is ≥ 98%. | Tune τ on dev to a precision target (the questions doc's 98%) rather than fixing 0.9. Compare probability against margin on dev and keep whichever gives more coverage at that precision. | Combined |
| D10 | Where the Latin original sits among candidates | S5 → S7, S9 | Mohamad + Omar | Top-5 candidates plus the Latin original always appended (k + 1). The chooser mock-up shows Latin last. | Q47: k = 5, with the Latin original always candidate 0. | Decide before the grammar and chooser are written, because indices are baked into both. Index 0 should be the best Arabic candidate so key 1 is the top suggestion; Latin goes last, and Esc also restores it (roadmap). | Roadmap |
| D11 | MADAR-derived files in the repo | S5–S6 | Moustafa | Never commit MADAR-derived files, counts included. Generate them locally; they are git-ignored. The licence gives "no rights to sublicense or further distribute". | Q45: ship derived counts only, never raw MADAR text, unless the licence allows it. | The roadmap's stricter rule until Dr. Mohanna (ADR 0001, question f) or the CAMeL Lab confirms that frequency counts may be redistributed. Consequence: the shipped dictionary uses team data only, and MADAR-boosted results are reported as a local experiment. | Roadmap |
| D12 | Who owns the linguistic rules | S5 | Team | Moustafa: tokenizer, letter map, clitic segmentation. Mohamad: candidate generation, fast path. | Q42 / Q44 / Q19: letter map Omar + Moustafa, clitics Mohamad, digit and pass-through rules Omar. | Keep the roadmap's owners, with Mohamad reviewing clitic PRs. Because Moustafa also builds the test set, rules must be tuned on dev only, and the test set must be annotated before rule tuning starts. | Roadmap |

## Applies to data collection (Week 3–4)

Needed before the test set is collected and frozen (S6).

| ID | Topic | Stage | Owner | Roadmap said | Questions doc said | Decision (Claude's recommendation) | Follows |
|---|---|---|---|---|---|---|---|
| D13 | Data splits | S6 | Moustafa | Split by writer and by sentence: dev 30% / test 70%, plus a `memory_future` split per personalisation volunteer. No train split; B2 is trained on other licensed Arabic-script text. | Q72: split by writer and by sentence: test 50% / dev 25% / train 25%. | The three-way split. B2 (KenLM) needs Lebanese Arabic-script text, your own sentences are the cleanest licensed source, and a possible LoRA (Q57) also needs a train split. Keep the roadmap's `memory_future` split on top. | Questions doc |
| D14 | Test-set size and freeze date | S6 | Moustafa | ≥ 400 elicited sentence-writer pairs + ≥ 150 natural sentences; freeze at end of W4. | Q66: 500 seed sentences × ≥ 2 writers + 150–300 natural; freeze at end of week 3. | Freeze at end of W4. IRB approval takes 8 days to 2 weeks, so outside writers cannot start before about W2–W3, and a W3 freeze is not realistic. Aim for 500 seeds, but let the gate pass at 400. | Combined |
| D15 | Annotation agreement | S6 | Moustafa | Every natural sentence transliterated by 2 annotators independently, with a third adjudicating. Report % agreement and Cohen's κ. | Q73: a second annotator labels 20% of the gold; a third adjudicates disagreements. | Both, by subset. Natural sentences (150–300) get full double annotation. Elicited sentences already have their Arabic-script seed as gold, so a 20% second check is enough there. | Combined |
| D16 | Elicitation prompt | S6 | Moustafa | Show each Arabic-script sentence to ≥ 2 native writers, who type it in Arabizi. | Q67: give English or Arabic-script scenarios (never Arabizi) and ask them to type "as on WhatsApp". | Mostly aligned. Use Arabic-script seeds for the main set, because they give the gold directly. Use English scenarios only for the natural-style subset, if at all. | Roadmap |

## Applies from Week 4–5

Needed before the resolver agent (S7).

| ID | Topic | Stage | Owner | Roadmap said | Questions doc said | Decision (Claude's recommendation) | Follows |
|---|---|---|---|---|---|---|---|
| D17 | Recovery after engine failures | S7 → S11 | Omar | Reconnect to the engine with exponential backoff (100 ms → 5 s). Never retry the model within a sentence. | Q86: restart once with backoff; after 3 failures in 5 minutes, disable the LLM for 10 minutes and show a status icon. | Both. Keep the roadmap's reconnect and add the questions doc's circuit breaker. It adds a Failure Matrix row and a clear demo moment. | Combined |
| D18 | What goes into the prompt | S3 → S7 | Mohamad | Only the ambiguous slots, ≤ 12 tokens of context on each side, and evidence (memory hits, contacts as data). | Q53: add 3 Lebanese few-shot examples and ≤ 3 memory hints; contacts only if opted in. | Decide by measurement: run zero-shot against 3-shot in the S3 bake-off. Few-shot examples add prompt tokens, which cost latency on the 8 GB Air. | Neither: measure |

## Applies from Week 6

Needed for S9–S12; revisit at the W5 retro if needed.

| ID | Topic | Stage | Owner | Roadmap said | Questions doc said | Decision (Claude's recommendation) | Follows |
|---|---|---|---|---|---|---|---|
| D19 | Trace exporter | S9 | Mohamad | Custom exporter writes OTLP-JSON lines to a file. A dev-only script ships them over HTTP. Langfuse accepts HTTP only, not gRPC. | Q82: local JSONL; in dev, send OTLP **gRPC** to Jaeger or Langfuse. | The roadmap's design: file export, then a dev script over HTTP. Jaeger accepts HTTP and Langfuse does not accept gRPC. On the 8 GB Air you run Jaeger only anyway. | Roadmap |
| D20 | When a correction counts as a habit | S10 | Moustafa | ≥ 3 occurrences and the same output ≥ 80% of the time. Context-dependent: ≥ 2 outputs, each ≥ 25%. | Q61: the same correction ≥ 3 times on ≥ 2 different days. Context-dependent entries are stored with the left-context token. | Combine: ≥ 3 times, ≥ 80% agreement, on ≥ 2 days. The day rule cheaply filters single-session bursts. Store context-dependent entries with the left-context token. | Combined |
| D21 | When a learned rule becomes active | S10 | Moustafa | `proposed` → `active` after user approval *or* 3 more confirmations: "choose one policy". | Q27: habit rules need user approval. | User approval. Human approval for consequential actions is an explicit rubric item, and one path is simpler to test. | Questions doc |
| D22 | What replay_eval must show | S10 | Moustafa | On the user's held-out history, accuracy improves *or stays equal*. Globally: 0.0-point drop on unrelated items and ≤ 0.5 points overall. | Q62: user accuracy *improves*, the global drop is ≤ 0.5 points, and no "golden" item flips. | Require a real improvement ("equal" shows no value) and the roadmap's 0.0-point rule on unrelated items, which acts as the golden set. | Combined |
| D23 | What each memory event stores | S10 | Moustafa | Latin, offered, chosen, app bundle ID, timestamp, context hash. | Q59: Latin, chosen, rejected candidates, app *category*, time. | Store app category instead of bundle ID: it identifies less about the user and is still useful. Keep the context hash and the rejected candidates. | Questions doc |
| D24 | User-study tasks | S11 | Moustafa | 8 given messages per condition. | Q78: 5 fixed tasks per condition, about 30 minutes per person. | 5 tasks. Both conditions plus SUS fit in 30 minutes, and a lighter session makes recruiting 6–9 people easier. | Questions doc |
| D25 | Live demo length | S12 | Omar | About 10 minutes, 10 segments. | Q96: 5 minutes. | Wait for the real slot length (ADR 0001, question b). Prepare a 5-minute core with the 10-minute version as an extension. | Combined |

## Gaps (in one document only, no conflict)

| Topic | What exists | Decision (Claude's recommendation) | Follows |
|---|---|---|---|
| Success-metric targets | The roadmap's S1 refers to "the metric targets list" but never defines it. Q74 does: word accuracy ≥ 90%, top-3 ≥ 97%, keep-Latin F1 ≥ 0.95, MSA rewrites ≈ 0, context subset ≥ B1 + 10 points. | Adopt Q74 in the proposal (S1). | Questions doc |
| Punctuation conversion | Only Q21 covers it: convert `?` → `؟` and `,` → `،` when most of the sentence is Arabic, behind a config flag. | Adopt it as a flag in `engine.json` (S5). | Questions doc |
| LoRA fine-tuning | Only Q57: allowed if prompt-only A1 misses its target by > 5 points, trained on the human-written train split. | Keep it as contingency only; it depends on D13 (the train split). | Questions doc |
| Dictionary size | Only Q45: 15–30k Lebanese forms with frequencies. | Use it as the S5 target, without MADAR in the shipped build (see D11). | Questions doc |
