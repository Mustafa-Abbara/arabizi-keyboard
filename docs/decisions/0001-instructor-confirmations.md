# ADR 0001: Instructor confirmations before building

- **Status:** accepted as team decisions (Moustafa, 10 Oct 2026). These are **not** instructor confirmations: no reply from Dr. Mohanna is recorded. Answer (h) on scope is **superseded by [ADR 0010](0010-phase1-pivot.md)** (Phase 1: fine-tuned translator + keyboard, agents later; approved by Dr. Mohanna). "R" below means the v1 roadmap, now [archive/ROADMAP_v1_agentic.md](../archive/ROADMAP_v1_agentic.md).
- **Date:** 2026-10-10
- **Deciders:** Omar Al Itani, Mohamad Al Masri, Moustafa Abbara; confirmed by Dr. Ammar Mohanna
- **Stage:** S0

## Context

Several parts of the plan depend on permissions only the instructor can give: the project path, reusing his VoiceType code, licensed datasets, human-subjects research, manual Yamli references, and the deadlines. Building on an unconfirmed assumption risks wasted weeks or a guardrail violation ("respect ToS / authorised data"). We ask once, in writing, in Week 1, and record the answers here and in `docs/ASSUMPTIONS.md`.

**IRB is the most time-critical item.** AUB's IRB manual says course projects with outside participants must be submitted to the IRB and approved before they begin. The application needs a faculty member as PI and CITI certificates for all three of us. Exempt review takes about 8 days to 2 weeks (see `docs/QUESTIONS_BEFORE_BUILDING.md`, Q10–Q12).

## Questions and answers

**Source column:** R = `docs/ROADMAP.md` · Q = `docs/QUESTIONS_BEFORE_BUILDING.md` · C = recommendation (see ADR 0008). Merging both drafts into one email was also recommendation.

| # | Question | Source | Assumption | Answer | Date |
|---|---|---|---|---|---|
| a | Is Path A (application) appropriate for this project? | R, Q | A2 | Yes, Path A. | Moustafa, 2026-10-10 |
| b | Exact dates: proposal (if a separate written one is required), poster pitch, final demo/submission? | R, Q | A1 | Not pursued now. Keep the roadmap's assumed calendar (A1). | Moustafa, 2026-10-10 |
| c | May we reuse parts of VoiceType (rule tables, ideas), and under which licence? | R, Q | A3 | No. No VoiceType code is reused or adapted. | Moustafa, 2026-10-10 |
| d | Will you act as faculty PI on our IRB student exemption application (interviews, data donation, 6–9 person user study)? | Q (replaces R's "is IRB needed?") | A8 | Deferred: no interviews or user study for now. If any later involve outside participants, IRB approval comes first (A8). | Moustafa, 2026-10-10 |
| e | May one team member type a small synthetic sample (≤100 sentences) into the Yamli website by hand as a comparison reference? Automated access is forbidden by Yamli's ToS, so we will not do that. | Q | — | Recommendation: yes, by hand only (see Decision). | Moustafa, 2026-10-10 |
| f | Is a public repository allowed, and may we use MADAR locally for internal evaluation only (raw text never committed)? | R, Q | A7 | The course brief (`503N_798S.pdf`) does not say public or private. It requires a "full GitHub repository" and data that is "public, authorized, or synthetic" while respecting ToS. Reading: the repo stays public, and MADAR is allowed locally under its licence terms, with nothing derived from it committed. | Moustafa, 2026-10-10 |
| g | Does AUB have an Apple Developer team we can use for signing, or is a local unsigned install acceptable for the demo? | Q | A5 | A local unsigned install is fine for now. | Moustafa, 2026-10-10 |
| h | Is our scope justified: macOS only, and two agents (sentence resolver + memory curator) with everything else deterministic? | Q (two agents) + C (macOS only) | A4 | Yes. | Moustafa, 2026-10-10 |
| i | Inference is local, so API cost is $0. May we report cost as compute time per successful task, plus an estimate of the equivalent cloud API cost? | C | — | Yes. | Moustafa, 2026-10-10 |

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

The team answered the questions itself (Moustafa, 10 Oct 2026). No reply from the instructor is recorded.

- **Path A**, **macOS only**, **two agents**, a **local unsigned install** and **cost as compute time** are accepted (a, g, h, i).
- **VoiceType:** no code is copied or adapted (c). Reading it for ideas and comparing against it by hand stay allowed (roadmap A3, S12). Credit it in the README.
- **Interviews and the user study are deferred** (d). Nobody outside the team takes part until IRB approval is in place. Until then, S1 uses team-internal work only.
- **Yamli** (e), recommendation: use it by hand only, for (1) a few screenshots of current-tool failures for S1, the poster and the demo, and (2) the optional S12 manual sample of ≤ 50 sentences, labelled "indicative only". Ordinary manual use of the public web page is what the ToS allows. Never automate it, and never use its outputs as references or training data.
- **Repo visibility and MADAR** (f), Reading of the course brief: the brief does not forbid a public repo, so the repo stays public (free Actions, CodeQL, secret scanning and branch protection). MADAR may be used locally under its licence (internal research and evaluation only), and nothing derived from it is committed.

## Consequences

- Each answer updates the matching row in `ASSUMPTIONS.md` (`confirmed` / `rejected`) and, if needed, the roadmap.
- If Dr. Mohanna later contradicts any of these answers, that answer replaces the team decision here, and the plan changes as listed in `ASSUMPTIONS.md`.
- The IRB timeline (8 days to 2 weeks) pushes S1 user observations to around W2–W3. The roadmap's S1 plan assumed W1–W2, so S1 starts with team-internal work: the consent form, the interview guide and the proposal draft.
