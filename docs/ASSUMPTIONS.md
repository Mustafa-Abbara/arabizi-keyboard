# Assumptions register

Each assumption the plan depends on, its status, and what changes if it is wrong.
Update the row (never delete it) when something is confirmed or rejected, and link the evidence.

**Status values:** `open` (not yet checked) · `asked` (question sent, waiting) · `confirmed` · `rejected` (plan changed: see link)

| ID | Assumption | Status | Evidence / date | If wrong |
|---|---|---|---|---|
| A1 | **Calendar.** Project Week 1 = 12–18 Oct 2026; poster pitch ≈ end of W5 (≈ 13 Nov); final demo, poster and repo due ≈ W10 (14–18 Dec). | open (dates not pursued for now) | team decision (Moustafa, 10 Oct 2026; ADR 0001), not instructor-confirmed | Poster earlier → use the roadmap's "poster-first variant" (§5). Shorter term → fallback scope T2 (§7). |
| A2 | **Path A** (application-oriented) is accepted for this project. | confirmed | team decision (Moustafa, 10 Oct 2026; ADR 0001), not instructor-confirmed | Reframe as Path B around a research question (e.g. "does calibrated asking beat n-gram reranking?"). Most of the engineering still applies. |
| A3 | **VoiceType reuse.** We may read Dr. Mohanna's VoiceType code for ideas. Reusing or adapting code needs explicit permission. | confirmed: no code reuse | team decision (Moustafa, 10 Oct 2026; ADR 0001), not instructor-confirmed. VoiceType may still be read for ideas and compared against by hand | Write everything new and credit it as inspiration only. |
| A4 | **Hardware.** Apple Silicon Macs with recent macOS + Xcode are available for IME and model work, and a second macOS user account can be created for IME testing. The roadmap assumed 16 GB RAM. | **rejected for Moustafa's Mac** (M2 MacBook Air, **8 GB**, fanless; 10 Oct 2026). Solo build since 12 Oct 2026 (ADR 0011), so this Mac is the only build machine. | See "8 GB consequences" below. |
| A5 | **Budget = $0.** No paid Apple Developer Program; free tiers and open source only. | confirmed | team decision (Moustafa, 10 Oct 2026; ADR 0001), not instructor-confirmed: a local unsigned install is fine for the demo | If someone has a Developer ID, add notarization in S12. |
| A6 | **Swift experience is limited.** A one-week learning ramp is built into W1. | open | — | Shorten the ramp. |
| A7 | **Public repository** is allowed (free GitHub Actions minutes, CodeQL, secret scanning). | confirmed | team decision (Moustafa, 10 Oct 2026; ADR 0001), not instructor-confirmed. The course brief does not mention repo visibility; it requires a "full GitHub repository" and authorized data. MADAR stays local and is never committed | Private repo: CI minutes become limited, so nightly evals run on a local machine. |
| A8 | **Human-subjects rules.** AUB IRB review (student exemption form) is required before any interview, data donation or user study with outside participants. Dr. Mohanna is asked to serve as faculty PI, and all three members complete CITI training (student modules). Written consent forms are used either way. | deferred | Interviews and the user study are deferred (Moustafa, 10 Oct 2026; ADR 0001). The IRB rule still applies before any outside participant takes part. AUB IRB manual (Feb 2020) and exemption form, cited in `QUESTIONS_BEFORE_BUILDING.md` Q10–Q12. Still confirm the current process with the IRB office. | Approval takes about 8 days to 2 weeks, so S1 observations slip to W2–W3. Use team-written data only until approved. |
| A10 | **Phase 1 scope.** Phase 1 is a fine-tuned local Arabizi→Arabic translator + the macOS keyboard; the agents move to an optional Phase 2. | confirmed | Approved by Dr. Mohanna, 12 Oct 2026 ([ADR 0010](decisions/0010-phase1-pivot.md)) | Return to the v1 plan in `archive/ROADMAP_v1_agentic.md`; P1–P3 carry over unchanged. |
| A11 | **Free cloud GPUs are enough for fine-tuning** (Kaggle ≈ 30 GPU h/week, or Colab) a 0.5B–1.5B model with LoRA on a few thousand pairs. | open | an estimate; P4 verifies | Contingency C5: alternate Kaggle/Colab; last resort MLX LoRA of the 0.5B model on the 8 GB Air. |
| A12 | **AI-generated training pairs are allowed by the provider's terms.** Some providers forbid using outputs to train competing models. | open | Checked per provider before generating, recorded in `docs/DATA.md` (ADR 0010 #7) | Contingency C6: skip AI rows; team-written + rule variants + public data only. |
| A13 | **Enough Lebanese data can be written by the team** (≥ 400 test/dev sentences by end of W3, ≥ 3,000 training pairs by end of W4, with helpers). | open | Targets from the Phase 1 roadmap P2 (Recommendation) | Contingency C4. |
| A14 | **One person can build Phase 1 in 10 weeks** with the reduced targets and the ranked cuts in roadmap §5. | open | Moustafa builds alone from 12 Oct 2026 ([ADR 0011](decisions/0011-solo-build.md)); an estimate | Apply the cuts in roadmap §5 in order as soon as a stage is a week late. |
| A9 | **Operating systems.** The M2 MacBook Air is the main development machine from S0 onward. All Swift code is built and tested on macOS (team Macs + CI). | confirmed | 10 Oct 2026 | — |

### 8 GB consequences (A4)

These are recommendations, accepted pending team review:

- **The 8 GB Air is the reference machine** for latency and RSS budgets. The roadmap says to measure on the weakest Mac, and a result that holds on 8 GB is a stronger claim. Record warm and cold runs, run on AC power, and close other apps. The Air has no fan, so long runs throttle.
- **Model budget:** Qwen2.5-0.5B or 1.5B at Q4_K_M (about 0.4–1 GB) still fits the < 1.5 GB engine RSS budget. Benchmark one model at a time. Report memory pressure and swap use alongside latency.
- **Fine-tuning runs in the cloud, not on the Air** (ADR 0010 #4). The Air only runs inference and evaluation.
- **Observability stack (Phase 2 only):** Jaeger all-in-one only. Self-hosted Langfuse (Postgres, ClickHouse, Redis, MinIO) is dropped on this machine. It can run on a 16 GB teammate's Mac if there is one.
- **Containers:** use Colima with a small VM (`colima start --cpu 2 --memory 2`) instead of Docker Desktop.
- **Xcode:** avoid running Simulators. Quit Xcode during benchmark runs.
