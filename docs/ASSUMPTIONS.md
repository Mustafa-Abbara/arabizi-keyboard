# Assumptions register

Each assumption the plan depends on, its status, and what changes if it is wrong.
Update the row (never delete it) when something is confirmed or rejected, and link the evidence.

**Status values:** `open` (not yet checked) · `asked` (question sent, waiting) · `confirmed` · `rejected` (plan changed: see link)

| ID | Assumption | Status | Evidence / date | If wrong |
|---|---|---|---|---|
| A1 | **Calendar.** Project Week 1 = 12–18 Oct 2026; poster pitch ≈ end of W5 (≈ 13 Nov); final demo, poster and repo due ≈ W10 (14–18 Dec). | open | — | Poster earlier → use the roadmap's "poster-first variant" (§5). Shorter term → fallback scope T2 (§7). |
| A2 | **Path A** (application-oriented) is accepted for this project. | open | — | Reframe as Path B around a research question (e.g. "does calibrated asking beat n-gram reranking?"). Most of the engineering still applies. |
| A3 | **VoiceType reuse.** We may read Dr. Mohanna's VoiceType code for ideas. Reusing or adapting code needs explicit permission. | open | — | Write everything new and credit it as inspiration only. |
| A4 | **Hardware.** Apple Silicon Macs with recent macOS + Xcode are available for IME and model work, and a second macOS user account can be created for IME testing. The roadmap assumed 16 GB RAM. | **rejected for Moustafa's Mac** (M2 MacBook Air, **8 GB**, fanless; 10 Oct 2026). Omar's and Mohamad's chip/RAM not yet recorded. | See "8 GB consequences" below. |
| A5 | **Budget = $0.** No paid Apple Developer Program; free tiers and open source only. | open | — | If someone has a Developer ID, add notarization in S12. |
| A6 | **Swift experience is limited.** A one-week learning ramp is built into W1. | open | — | Shorten the ramp. |
| A7 | **Public repository** is allowed (free GitHub Actions minutes, CodeQL, secret scanning). | open | — | Private repo: CI minutes become limited, so nightly evals run on a local machine. |
| A8 | **Human-subjects rules.** AUB IRB review (student exemption form) is required before any interview, data donation or user study with outside participants. Dr. Mohanna is asked to serve as faculty PI, and all three members complete CITI training (student modules). Written consent forms are used either way. | asked | AUB IRB manual (Feb 2020) and exemption form, cited in `QUESTIONS_BEFORE_BUILDING.md` Q10–Q12. Still confirm the current process with the IRB office. | Approval takes about 8 days to 2 weeks, so S1 observations slip to W2–W3. Use team-written data only until approved. |
| A9 | **Mixed operating systems.** Moustafa uses both a Windows 11 machine and an M2 MacBook Air. The Mac is the main development machine from S0 onward; Windows is used only for docs, email and GitHub admin. All Swift code is built and tested on macOS (team Macs + CI). | confirmed | Windows observed and Mac confirmed by Moustafa, 10 Oct 2026 | — |

### 8 GB consequences (A4)

These are Claude's recommendations, accepted pending team review:

- **The 8 GB Air is the reference machine** for latency and RSS budgets. The roadmap says to measure on the weakest Mac, and a result that holds on 8 GB is a stronger claim. Record warm and cold runs, run on AC power, and close other apps. The Air has no fan, so long runs throttle.
- **Model budget:** Qwen2.5-0.5B or 1.5B at Q4_K_M (about 0.4–1 GB) still fits the < 1.5 GB engine RSS budget. Benchmark one model at a time. Report memory pressure and swap use alongside latency.
- **Observability stack:** Jaeger all-in-one only. Self-hosted Langfuse (Postgres, ClickHouse, Redis, MinIO) is dropped on this machine. It can run on a 16 GB teammate's Mac if there is one.
- **Containers:** use Colima with a small VM (`colima start --cpu 2 --memory 2`) instead of Docker Desktop.
- **Xcode:** avoid running Simulators. Quit Xcode during benchmark runs.
