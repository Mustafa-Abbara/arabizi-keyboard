# ADR 0010: Phase 1 pivot: fine-tuned local translator + keyboard first, agents later

- **Status:** accepted
- **Date:** 2026-10-12
- **Deciders:** Moustafa Abbara (scope approved by Dr. Ammar Mohanna, 12 Oct 2026); solo build from 12 Oct 2026, see [ADR 0011](0011-solo-build.md)
- **Stage:** P0 (was S0)

## Context

The v1 roadmap (now [archive/ROADMAP_v1_agentic.md](../archive/ROADMAP_v1_agentic.md)) built a deterministic engine first, then added two agents: a sentence resolver whose LLM only picks a candidate index (GBNF-constrained), and a memory curator. Phase 1 instead first builds a working translator from Lebanese Arabizi to Lebanese Arabic script using a **local LLM that we fine-tune**, plus the keyboard app, and only then decide whether to add the agentic parts.

Constraints: 8 GB M2 MacBook Air as the reference machine (A4), $0 budget (A5), no outside participants until IRB approval (A8), no public Lebanese Arabizi→Arabic parallel dataset.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| A. Keep the v1 plan (deterministic engine + index-picking agents) | Agentic rubric marks covered from the start; LLM cannot invent words | Large scope; the translator itself is mostly rules + dictionary |
| B. Phase 1 = fine-tuned local translator + keyboard; agents in an optional Phase 2 | Smaller, clearer goal; a working product sooner; fine-tuning is a strong evaluation story | The model writes Arabic freely, so it can produce MSA or invented words; agentic marks depend on Phase 2 |

## Decision

**Option B.** Each part below says where it came from.

| # | Decision | Source |
|---|---|---|
| 1 | Phase 1 builds a fine-tuned local translator and the macOS keyboard. The resolver and memory agents move to an optional Phase 2. | **Moustafa**, approved by Dr. Mohanna (12 Oct 2026) |
| 2 | The model writes the Arabic output directly. This replaces the v1 rule that the LLM only picks a candidate index (v1 S3/S7, ADR 0009 D-decisions about GBNF). | **Moustafa** (follows from 1) |
| 3 | Guards on the free-form output: protected placeholders for numbers, URLs, emails, mentions and emoji; output checks (placeholders, length, no new Latin text); a rule-based fallback on timeout or failed check. | **Recommendation** |
| 4 | Fine-tuning runs on free cloud GPUs (Kaggle/Colab). Inference runs only on the Mac, inside an XPC service with no network entitlement. | **Moustafa**; **Recommendation** (yes) |
| 5 | **Enter** converts the whole typed text and commits it without sending; a second Enter sends. English words, digits/standalone numbers stay as typed. | **Moustafa** |
| 6 | Training data: team-written pairs + rule-made spelling variants + licensed public Lebanese text (option A), **plus AI-generated pairs** (option B). | **Moustafa** |
| 7 | AI-generated pairs: **train only**, every row checked by a native speaker, provider terms checked and recorded first, prompt saved, de-duplicated against dev/test, capped at half the training set, and an ablation with/without them. | Train-only and checked: **Moustafa**. Terms check, cap and ablation: **Recommendation** |
| 8 | This **overrides Q57 and Q70** of `QUESTIONS_BEFORE_BUILDING.md` and the "never generate Arabizi with an AI model" rule in CONTRIBUTING.md and the working notes. Those were recommendations, not instructor or course rules. Dev and test stay human-written. | **Moustafa**, with the dev/test limit from **Recommendation** |
| 9 | New stage names **P0–P7** so v1 references (S0–S12) stay unambiguous. P0 is the old S0 unchanged. The v1 roadmap is archived, not deleted. | **Recommendation** |
| 10 | Budgets on the 8 GB Air: RSS ≤ 1.5 GB; warm latency for ≤ 15 words p50 ≤ 600 ms, p95 ≤ 1.2 s; candidate base models Qwen2.5-0.5B/1.5B-Instruct, Gemma 3 1B, Llama 3.2 1B; never Qwen2.5-3B (licence, v1 D2). P3 measures and may revise them. | **Recommendation** |

## What still applies from v1

- Everything in S0 (now P0) and the IME spike (S2, now P1) unchanged.
- The CI, CodeQL, Dependabot and contract-test approach from S4 (now inside P5).
- The privacy design: local inference, sandboxed XPC service with no network, no user text in logs.
- Data provenance, the frozen test set and paired-bootstrap reporting from S6.
- Licence rules: MADAR local evaluation only; never Yamli; never commit weights.

ADR 0009 decisions about the resolver, ask policy, calibration, GBNF and memory are **paused**, not rejected. They return if Phase 2 starts.

## Consequences

- **Easier:** one clear product goal; a demo-able keyboard earlier; a measurable "fine-tuning helps" result.
- **Harder:** the model can rewrite Lebanese into MSA or invent words; this is tracked with the MSA-rewrite and hallucination metrics and limited by the output checks and fallback.
- **Data is now the critical path** (P2). With only three team writers, test and train share writers; this is reported as a limitation, with AladdinBench (local only) as an external real-typing check.
- **Rubric risk:** marks tied to agents (agent performance, AgentOps) depend on Phase 2. Dr. Mohanna approved the Phase 1 scope; revisit at the poster pitch.
- **Terms of service:** AI-generated rows are only used where the provider's terms allow training on outputs. Some providers' terms forbid using outputs to train competing models, so this is checked per provider and recorded in `docs/DATA.md` (contingency C6).
- The 104 GitHub issues created from the v1 roadmap need to be closed as "not planned" and replaced with P0–P7 issues by `scripts/github/bootstrap.py issues`.
