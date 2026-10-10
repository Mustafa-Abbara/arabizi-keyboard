# ADR 0001: Instructor confirmations before building

- **Status:** proposed (waiting for reply)
- **Date:** 2026-10-10
- **Deciders:** Omar Al Itani, Mohamad Al Masri, Moustafa Abbara; confirmed by Dr. Ammar Mohanna
- **Stage:** S0

## Context

Several parts of the plan depend on permissions only the instructor can give: the project path, reusing his VoiceType code, licensed datasets, human-subjects research, manual Yamli references, and the deadlines. Building on an unconfirmed assumption risks wasted weeks or a guardrail violation ("respect ToS / authorised data"). We ask once, in writing, in Week 1, and record the answers here and in `docs/ASSUMPTIONS.md`.

**IRB is the most time-critical item.** AUB's IRB manual says course projects with outside participants must be submitted to the IRB and approved before they begin. The application needs a faculty member as PI and CITI certificates for all three of us. Exempt review takes about 8 days to 2 weeks (see `docs/QUESTIONS_BEFORE_BUILDING.md`, Q10–Q12).

## Questions and answers

**Source column:** R = `docs/ROADMAP.md` · Q = `docs/QUESTIONS_BEFORE_BUILDING.md` · C = Claude's recommendation (see ADR 0008). Merging both drafts into one email was also Claude's recommendation.

| # | Question | Source | Assumption | Answer | Date |
|---|---|---|---|---|---|
| a | Is Path A (application) appropriate for this project? | R, Q | A2 | | |
| b | Exact dates: proposal (if a separate written one is required), poster pitch, final demo/submission? | R, Q | A1 | | |
| c | May we reuse parts of VoiceType (rule tables, ideas), and under which licence? | R, Q | A3 | | |
| d | Will you act as faculty PI on our IRB student exemption application (interviews, data donation, 6–9 person user study)? | Q (replaces R's "is IRB needed?") | A8 | | |
| e | May one team member type a small synthetic sample (≤100 sentences) into the Yamli website by hand as a comparison reference? Automated access is forbidden by Yamli's ToS, so we will not do that. | Q | — | | |
| f | Is a public repository allowed, and may we use MADAR locally for internal evaluation only (raw text never committed)? | R, Q | A7 | | |
| g | Does AUB have an Apple Developer team we can use for signing, or is a local unsigned install acceptable for the demo? | Q | A5 | | |
| h | Is our scope justified: macOS only, and two agents (sentence resolver + memory curator) with everything else deterministic? | Q (two agents) + C (macOS only) | A4 | | |
| i | Inference is local, so API cost is $0. May we report cost as compute time per successful task, plus an estimate of the equivalent cloud API cost? | C | — | | |

## Message to send (from Moustafa, cc Omar and Mohamad)

> **Subject:** EECE 503N/798S – Arabizi Keyboard team (Al Itani, Al Masri, Abbara) – 9 questions before we build
>
> Dear Dr. Mohanna,
>
> We are starting "A Local, Personal Arabizi Keyboard for macOS". Lebanese users who chat in Arabizi currently get Arabic script through word-by-word web tools and copy-paste. These tools get context wrong (e.g. "la mohammad" → لا محمد instead of لمحمد) and send what users type to a server. Before building, we need your answers on these points:
>
> 1. Can you confirm that our project counts as **Path A (application)**?
> 2. What are the exact **dates** for the proposal (if a separate written one is required), the poster pitch and the final demo?
> 3. May we **reuse parts of VoiceType** (rule tables and ideas)? Under which licence?
> 4. **IRB:** AUB's IRB manual says course projects with outside participants must be submitted before they begin. Will you act as **faculty PI** on our student exemption application for interviews, data donation and a 6–9 person user study? All three of us are completing CITI training.
> 5. **Yamli:** its Terms of Service forbid automated access, so we will not call it. May a team member type a small synthetic sample (≤100 sentences) into the Yamli website **by hand** as a comparison reference?
> 6. May our **repository be public**? We would use the MADAR corpus locally for internal evaluation only and never commit its raw text.
> 7. Does AUB have an **Apple Developer team** we can use for signing, or is a local unsigned install acceptable for the demo?
> 8. Is our scope justified: **macOS only**, with **two agents** (a sentence resolver and a memory curator) and everything else deterministic?
> 9. Inference runs locally, so API cost is $0. May we report **cost as compute time per successful task**, plus an estimate of the equivalent cloud API cost?
>
> Thank you,
> Omar Al Itani, Mohamad Al Masri, Moustafa Abbara

## Decision

Pending. Until answers arrive, we proceed with the assumptions in `docs/ASSUMPTIONS.md`. Nothing that depends on (c), (d), (e) or (f) is started:

- No VoiceType code is copied.
- No interviews, observations or data collection happen with anyone outside the team.
- No Yamli comparison is made.
- No MADAR file is downloaded.

## Consequences

- Each answer updates the matching row in `ASSUMPTIONS.md` (`confirmed` / `rejected`) and, if needed, the roadmap.
- A "no" to (a) moves us to the Path B framing. A "no" to the macOS-only part of (h) requires re-scoping before S2 continues.
- The IRB timeline (8 days to 2 weeks) pushes S1 user observations to around W2–W3. The roadmap's S1 plan assumed W1–W2, so S1 starts with team-internal work: the consent form, the interview guide and the proposal draft.
