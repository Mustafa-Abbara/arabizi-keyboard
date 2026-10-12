# 100 Questions to Answer Before Building "A Local, Personal Arabizi Keyboard for macOS"

> Where this document conflicts with `ROADMAP.md`, [ADR 0009](decisions/0009-plan-conflict-resolutions.md) decides (D1–D25, all Claude's recommendations). Overridden answers are left unchanged below for the record.
>
> **Phase 1 pivot (12 Oct 2026):** this document was written for the v1 roadmap (now `archive/ROADMAP_v1_agentic.md`). [ADR 0010](decisions/0010-phase1-pivot.md) overrides it where they conflict, notably **Q57** (fine-tuning is now the core of Phase 1) and **Q70** (AI-generated pairs are allowed in training only, checked by a native speaker; dev and test stay human-written).

Before you write code, about 10 questions can block you: Path A confirmation, AUB IRB approval for the user study, permission to reuse VoiceType, the "no Yamli at runtime" rule, the model bake-off, and a one-week IME spike on Enter and marked text. Apple's on-device Foundation Models cannot be your engine, because Apple Intelligence does not support Arabic.\[1\] Use Qwen2.5-1.5B or Qwen2.5-0.5B (Apache 2.0) through llama.cpp. The team can settle the other 90 questions in one or two meetings using the answers below.

## TL;DR
- **Blocking now (this week):** email Dr. Mohanna (Path A, dates, VoiceType reuse, faculty PI for IRB, manual Yamli references). Submit an AUB IRB exemption application, because AUB says course projects with outside participants "need to be submitted to the IRB for review and approval before they begin". All three of you should finish CITI training.
- **Technical defaults:** IMK input method, plus a sandboxed XPC service with no network access, running llama.cpp and a Qwen2.5 Q4_K_M model with GBNF-constrained output. Do not use Apple Foundation Models (no Arabic), Qwen2.5-3B (non-commercial licence) or Llama 3.2 1B (Arabic is not one of the 8 languages Meta's model card lists as officially supported).
- **Evaluation and data:** a frozen, human-written Lebanese test set split by writer. No automated Yamli access (Yamli's Terms of Service forbid it). Baselines B0/B1/B2 and ablations A1–A3, paired bootstrap confidence intervals, and a 6–9 person study comparing your keyboard with Yamli copy-paste.

## How to read the tables
- **Type:** Decide = team decision · Verify = check a fact or test it in a spike · Ask instructor · Ask users.
- **Owner:** Omar (IME/macOS), Mohamad (model/resolver), Moustafa (users/data/eval/memory), Team.
- **[ASSUMPTION]** marks an answer that rests on something not yet confirmed.
- Rubric weights: Idea & agentic justification 20% · Agent performance/eval 20% · AgentOps 15% · Reliability/QA/security 15% · Software engineering 10% · Poster & demo 10% · Docs & reproducibility 10% · Bonus +10%.

---

## 1. Problem and users (Q1–7)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 1 | Who exactly is the primary user? | Lebanese adults (18–35) who chat in Arabizi on a Mac every day and sometimes need real Arabic script. Secondary users: AUB students and staff. [ASSUMPTION until interviews confirm] | The course says start with the user, not the technology (Idea 20%) | Decide + Ask users | Moustafa |
| 2 | What is the one-sentence problem? | "Lebanese Mac users who think in Arabizi cannot get correct Lebanese Arabic script inside the app they are using. Today they copy-paste from a web tool that converts word by word, sends their text to a server, and gets context words like *la* wrong." | The poster's "Problem" section needs one clear sentence (Idea 20%) | Decide | Team |
| 3 | When does the user need Arabic script instead of Arabizi? | Hypothesis: messages to older relatives, formal or community WhatsApp groups, social posts, and names. Check this in interviews. [ASSUMPTION] | This shows real demand, so you are not solving an imagined problem (Idea 20%) | Ask users | Moustafa |
| 4 | What is the task-level success measure? | Time and number of corrections needed to produce a correct 10–15-word Lebanese Arabic message, compared with Yamli copy-paste | The proposal must name the tasks improved and the success criteria (Idea, Eval) | Decide | Moustafa |
| 5 | What is explicitly out of scope? | Voice, MSA output, translation, Windows/iOS, English autocorrect, and free sentence rewriting. Write this list in the README and on the poster | Protects the scope; graders check boundaries (Idea 20%) | Decide | Team |
| 6 | Will users switch input source for each message? | Design so they don't have to. English passes through unchanged (keep-Latin), so the IME can stay on all day. Check this in interviews | A wrong answer here kills adoption; it feeds the keep-Latin target (Eval) | Ask users | Moustafa |
| 7 | Is Path A (application) confirmed, and does the proposal cover every Path A item? | Ask for written confirmation. Then check the proposal against the list: user, workflow, tasks, why agentic, what stays deterministic or human-controlled, constraints, success criteria | If the path is wrong, everything else is wasted (Idea 20%) | Ask instructor | Team |

## 2. Current workflow and user research (Q8–14)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 8 | How many user conversations before the proposal? | 8–10 interviews of 15 minutes, plus 2 observed typing sessions, in the first build week (only after IRB clearance; see Q10) | The course "strongly encourages" grounding the proposal in user conversations (Idea 20%) | Ask users | Moustafa |
| 9 | What do we ask? | 8 fixed questions: which tools they use now (Yamli site, phone Arabic keyboard, plain Arabizi), how often, which apps, the worst moments, privacy feelings, and whether they would let a keyboard learn their habits. Do not collect their real messages | Gives evidence for the "Users & Current Workflow" poster section | Decide | Moustafa |
| 10 | Do we need IRB approval for interviews, data donation and the user study? | **Yes, plan for it.** AUB's IRB manual lists "research conducted in courses" as needing IRB review. It says course assignments with outside participants "need to be submitted to the IRB for review and approval before they begin". Only the IRB Chair or Vice Chairs can grant an exemption.\[2\] Submit the student exemption form this week | Ethics, data provenance, and the user study all depend on it (Eval 20%, Safety) | Ask instructor + Verify | Moustafa |
| 11 | Who is the faculty PI on the IRB form? | Dr. Mohanna. AUB's student exemption form says "An AUB faculty member (typically the course instructor…) is required to serve as the responsible Principal Investigator"\[3\] | The application is invalid without a PI | Ask instructor | Moustafa |
| 12 | Does everyone need CITI training? | Yes. All three of you should take the student modules (Belmont/Introduction plus Students in Research–SBR). AUB says the student module "takes less than an hour", and applications without CITI certificates are returned unreviewed\[2\]\[3\] | It is cheap and it unblocks the IRB | Verify | Team |
| 13 | How do we measure today's workflow (the baseline)? | Time five fixed, synthetic messages typed through Yamli copy-paste, using screen-timer logging and no real chats | Gives the B-condition of the user study and pilot numbers (Eval 20%) | Decide | Moustafa |
| 14 | What goes into the "Pilot Evidence" poster section? | Anonymised interview counts and quotes, plus a 50-sentence pilot of B0/B1 against the first prototype, with numbers | This poster section is required (Poster 10%) | Decide | Moustafa |

## 3. Scope and output target (Q15–22)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 15 | Which orthography is "correct"? | Lebanese forms as people actually write them (شو، هيدا، لمحمد), never MSA rewrites. Use the CODA convention as a guide: Eryani et al. (LREC 2020) describe the MADAR CODA corpus as five city dialects "in parallel across the cities (2,000 sentences from each city)", including Beirut, in CODA next to their raw form | Defines your ground truth (Eval 20%) | Decide | Moustafa |
| 16 | How do we handle spelling variants (ة/ه, ى/ي, hamza forms)? | Multi-reference gold: list every accepted variant for each word. Report strict accuracy, and also a "lenient" score that normalises alef, ya and ta marbuta | Avoids penalising valid outputs; makes the accuracy target fair | Decide | Moustafa |
| 17 | Do we output diacritics (tashkeel)? | No | Simpler; matches how people chat | Decide | Team |
| 18 | What happens to English/French words inside Arabizi ("meeting", "merci")? | Keep them in Latin by default. Transliterate only if the dictionary marks the word as Arabic or an Arabised loan | Supports the keep-Latin F1 ≥0.95 target | Decide | Mohamad |
| 19 | Digits as letters vs digits as numbers ("3al" vs "100$")? | A digit attached to letters is an Arabizi letter. Standalone numbers, currency, times, phone numbers, URLs, emails and @handles pass through unchanged | Deterministic and testable (Reliability) | Decide | Omar |
| 20 | Western or Arabic-Indic digits in the output? | Keep the digits exactly as typed (Western) | Users typed them on purpose; transliteration is not translation | Decide | Team |
| 21 | Do we convert punctuation (? → ؟, , → ،)? | Only when most of the sentence is Arabic, and never inside URLs, emails or numbers. Make it a config flag that is on by default | Small detail with high visibility in the demo | Decide | Omar |
| 22 | Which apps must work? | WhatsApp Desktop, Slack, Outlook, Safari, Chrome, Notes and TextEdit. Treat this as the compatibility test matrix | The real-world constraint you will evaluate (Reliability 15%) | Verify | Omar |

## 4. Agentic justification and agent boundaries (Q23–29)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 23 | Why is this agentic and not just "a model"? | Agent #1 decides, per sentence, whether to commit, keep Latin or ask, using tools (candidates, memory, contacts) and a calibrated confidence. Agent #2 runs an observe → propose → test → write loop behind a gate. Everything else is deterministic | This is the core of the Idea score (20%) | Decide | Team |
| 24 | Are two agents too many? | Keep exactly two. Do not add a planner or router agent. If time runs short, Agent #2 becomes a deterministic learner, but it keeps the replay_eval gate | The guardrail says "more agents ≠ better" | Decide | Team |
| 25 | What does the LLM never do? | It never writes free text. It only picks a candidate index or ASK. It never writes memory directly, never sees secure fields, and never sends a message | Least privilege; prompt-injection defence (Security) | Decide | Mohamad |
| 26 | What stays under human control? | The ask chooser, approving learned rules ("What I learned"), the contacts opt-in, and pressing Enter or Send | Human approval for consequential actions (Safety) | Decide | Team |
| 27 | Which actions count as "consequential"? | Only two: committing text, and writing memory. A memory write needs a replay_eval pass. Habit rules also need user approval after 3 occurrences | This is where you put the approval gates | Decide | Moustafa |
| 28 | Which experiment proves the agents add value? | A1 vs B1/B2 on the context subset; A2 vs A1 on risk–coverage; A3 vs A2 on corrections per 100 words over sessions | The ablations justify the agentic design (Eval 20%) | Decide | Moustafa |
| 29 | What happens if the LLM is removed entirely? | The keyboard still works (rules + dictionary + memory). Show this in the demo as graceful degradation | Reliability 15%; also your fallback scope | Decide | Omar |

## 5. Architecture and the macOS input method (Q30–41)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 30 | Extend VoiceType or build a new IME? | Build a new InputMethodKit target. VoiceType is a menu-bar app, not an IME, so reuse at most its rule ideas or tables, and only after written permission. Its licence is **unverified**: if the repo has no LICENSE file, default copyright applies | Avoids an architecture mismatch and a legal problem | Ask instructor | Omar |
| 31 | Which macOS and Xcode versions? | Develop on the team's current macOS. Build in CI with Xcode 26.x (Swift 6.3), because CodeQL lists support for "Swift 5.4-6.3".\[4\]\[5\] One project reported Xcode 27.0 ships Swift 6.4, which CodeQL did not yet list as of 2026-10-06\[6\] | Keeps CodeQL (bonus) working | Verify | Omar |
| 32 | Where does composition state live? | Outside IMKInputController, in a session store keyed by client. IMK "creates a controller object for each session request". One 2026 developer report says macOS 27 recreates the controller after every consumed key (single source; confirm in the spike)\[7\]\[8\] | Prevents lost marked text and random bugs | Verify | Omar |
| 33 | What does Enter do when marked text exists? | Enter commits the marked text and is consumed; it never sends. A second Enter goes to the app. Test this in WhatsApp and Slack, where Enter means Send | Avoids sending wrong text: a safety-critical behaviour | Verify | Omar |
| 34 | How long does text stay "marked"? | Keep the current sentence (up to ~12 words) as marked text and commit it at . ? ! or Enter after the resolver runs. In apps on the "no-marked-text" list, commit word by word with the deterministic engine only | Context resolution needs the whole sentence; some apps break otherwise | Decide | Omar |
| 35 | Candidate UI: IMKCandidates or a custom panel? | IMKCandidates for top-k word choices (number keys 1–5). A custom non-activating NSPanel only for the numbered "ask" chooser, if IMKCandidates proves too limited in the spike\[8\] | The UI must not default to chat (technical expectation) | Verify | Omar |
| 36 | How do we handle apps that ignore or break marked text? | A per-app config keyed by bundle ID with modes {marked, direct-commit, off}, filled in from the compatibility matrix | A real-world constraint, measured and documented | Verify | Omar |
| 37 | Password and secure fields? | Do nothing (no processing, no memory, no telemetry) when `IsSecureEventInputEnabled()` is true or the field looks like a password. Apple's TN2150 describes secure event input.\[9\] Recent Chromium issues show "revealed" password fields can turn secure input off, so never log text in any field\[10\]\[11\] | PII protection (Security 15%) | Decide + Verify | Omar |
| 38 | Where does the model run? | In a separate XPC service inside the IME bundle: sandboxed, no network entitlement, model file read-only, Codable messages validated on both sides | Least privilege and crash isolation | Decide | Mohamad |
| 39 | Is the IME itself sandboxed? | Yes. Use App Sandbox with the `mach-register.global-name` temporary exception `$(PRODUCT_BUNDLE_IDENTIFIER)_Connection` (the usual IMK sample pattern) and no `network.client` entitlement\[12\]\[13\] | Security; a strong point to show reviewers | Verify | Omar |
| 40 | How do we prove "zero network"? | (a) A CI check that fails if any entitlements file has a network key. (b) During eval and demo runs, `lsof -i`/`nettop` shows no sockets for either process | Turns a privacy claim into evidence (Eval, Security) | Decide | Omar |
| 41 | How is it installed and signed? | Local build plus a script that installs into `~/Library/Input Methods`. Notarize only if someone has a paid Developer account. [ASSUMPTION: $0 budget] | Reproducible installation (Docs 10%) | Ask instructor | Omar |

## 6. Deterministic engine (Q42–48)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 42 | Where does the character mapping live? | In a versioned YAML table (3=ع, 7=ح, 2=ء/ق, 5/kh=خ, 8/gh=غ, 9=ص, 6=ط, sh/ch=ش, th=ث/ت…) with unit tests, loaded through central config\[14\] | Centralised config; testable (SE 10%) | Decide | Omar + Moustafa |
| 43 | How do we resolve ambiguous "2" (ء or ق) and vowels? | Generate both readings and let dictionary priors rank them (e.g., "2al" → قال). Vowels are optional when matching | Keeps ambiguity explicit for the resolver | Decide | Moustafa |
| 44 | Which clitics do we segment? | Prefixes la-/li-, w-, b-, 3a-/3al-, el-/il-, ma-…-sh; suffixes -o, -ha, -kon, -na, -ak/-ik. Produce both joined and split candidates ("la mohammad" → لمحمد vs لا محمد) | This is your headline example, so it must be right | Decide | Mohamad |
| 45 | Where does the dictionary come from? | A Lebanese word list of 15–30k forms with frequencies: Beirut sentences from MADAR (non-commercial licence) plus your own train split plus manual additions. Ship derived counts only, never MADAR raw text, unless the licence allows it\[15\] | Data provenance and licences (guardrail) | Verify | Moustafa |
| 46 | How are the edit-distance weights set? | Set them by hand first (vowel insert/delete cheap, digit↔letter cheap). Tune only on the dev split, never on test | Prevents test leakage (Eval) | Decide | Moustafa |
| 47 | How many candidates per word? | k = 5 sent to the resolver and shown in the panel. The Latin original is always candidate 0 | Supports top-3 ≥97% and keep-Latin | Decide | Mohamad |
| 48 | When does the fast path skip the LLM? | When the top-1 margin is ≥ τ, with τ tuned on dev so fast-path precision is ≥98% | Latency and cost; justifies calling the LLM only when needed | Decide | Mohamad |

## 7. Local model (Q49–58)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 49 | Which runtime: llama.cpp, MLX, or Apple Foundation Models? | **llama.cpp**: it supports GBNF grammars and can convert JSON Schema to GBNF. MLX is a stretch goal. **Not Apple Foundation Models**: Apple lists 16 Apple Intelligence languages for macOS 27, and Arabic is not one of them\[16\]\[17\] | A factual blocker for the Apple route | Decide | Mohamad |
| 50 | Which model? | Run a bake-off on 100 dev sentences in week 1. Primary: **Qwen2.5-1.5B-Instruct Q4_K_M** (Apache 2.0; Ollama lists the Q4_K_M build at 986 MB; the Qwen team's Qwen2.5 announcement says the models support "over 29 languages, including … Arabic"). Fallback: Qwen2.5-0.5B. Avoid Qwen2.5-3B (Qwen Research licence, non-commercial).\[18\]\[19\] Meta's Llama 3.2 model card says "English, German, French, Italian, Portuguese, Hindi, Spanish, and Thai are officially supported", which leaves out Arabic. Gemma 3 1B is listed as English-only in Hugging Face's launch table, though other sources say "140 languages" for the family; test it before trusting it\[20\]\[21\] | Model choice drives accuracy, latency and licence risk | Verify | Mohamad |
| 51 | Which quantization? | Q4_K_M by default. Compare with Q8_0 on dev and keep Q8_0 only if it gains ≥2 points within the latency budget | A documented trade-off for the report | Verify | Mohamad |
| 52 | What exactly does the model output? | A GBNF grammar built per request: `{"s1": 0..k or "ASK", …}`, one enum per ambiguous slot. Use bounded repetition `x{0,N}`; llama.cpp warns that `x? x? …` "may result in extremely slow sampling"\[22\] | Schema violations must be 0 | Decide | Mohamad |
| 53 | What goes into the prompt? | A fixed instruction, the Latin sentence in delimiters, a candidate list per slot, at most 3 memory hints, and 3 Lebanese few-shot examples. No raw history, no contacts unless opted in | Prompt-injection surface kept small | Decide | Mohamad |
| 54 | How do we get confidence? | Take the probability of the chosen index token from logprobs, renormalised over the allowed tokens, then apply temperature scaling fitted on dev | Supports ECE ≤0.05 and ask decisions | Decide | Mohamad |
| 55 | When does it ask? | Pick τ_ask from the dev risk–coverage curve so that asks are ≤2 per 100 words with ask precision ≥0.5 | Human-in-the-loop with measured cost | Decide | Mohamad |
| 56 | What are the latency and RAM budgets? | p50 ≤500 ms, p95 ≤900 ms, hard timeout 700 ms → deterministic fallback; XPC RSS <1.5 GB; load lazily, keep warm, unload after 10 minutes idle. Measure on the weakest team Mac. [ASSUMPTION: Apple Silicon 16 GB] | The real-world constraint you will evaluate (rubric guardrail) | Verify | Mohamad |
| 57 | Fine-tune or not? | Not before the poster. Only if prompt-only A1 misses the target by >5 points, train a LoRA on the human-written train split (MADAR Beirut CODA plus your own data). Never on AI-generated Arabizi | Saves weeks; protects data rules | Decide | Mohamad |
| 58 | How do we protect the model file? | Pin a SHA-256 in config and check it at load. On mismatch or corruption, use the deterministic fallback and log an error span | A Failure Matrix row; supply-chain safety | Decide | Mohamad |

## 8. Memory and personalisation (Q59–65)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 59 | What exactly is stored? | Token-level events only: (Latin token, chosen Arabic, rejected candidates, app category, time). No sentences. Events expire after 30 days; learned rules stay until the user deletes them | Memory scope and lifetime (technical expectation) | Decide | Moustafa |
| 60 | How is memory encrypted? | Try SQLCipher via GRDB for one day. GRDB 7.10.0 supports SQLCipher with SwiftPM, but you "must fork GRDB, and modify Package.swift" (or use SQLCipher's managed GRDB fork).\[23\]\[24\]\[25\]\[26\] If that fails, use CryptoKit AES-GCM per row. Keep the key in the Keychain | A security asset; avoids a lost week | Verify | Moustafa |
| 61 | How are corrections classified? | typo / one-off / habit / context-dependent. Habit = same correction ≥3 times on ≥2 days. Context-dependent = stored with the left-context token | Prevents false learning (target ≤5%) | Decide | Moustafa |
| 62 | What does replay_eval accept? | Accept only if user-history accuracy improves AND global regression accuracy drops ≤0.5 points AND no "golden" item flips | A gate before the consequential write | Decide | Moustafa |
| 63 | How does the user control memory? | A "What I learned" panel in the menu: approve, edit, delete, pause learning, wipe all. No chat UI | User control; the UI must not default to chat | Decide | Moustafa |
| 64 | Do we use contacts? | Opt-in, off by default, names only, cached locally as candidates. Never in the demo without consent | Least privilege; PII | Decide | Moustafa |
| 65 | When is memory disabled? | During secure input, in blocklisted apps (password managers, Terminal), and while the user has paused learning | Privacy and safety | Decide | Moustafa |

## 9. Data (Q66–73)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 66 | How big is the test set, and when is it frozen? | 500 seed sentences, each written in Arabizi by ≥2 independent native writers, plus 150–300 consented natural sentences. Freeze it (hash + tag) by the end of build week 3 | Held-out testing (Eval 20%) | Decide | Moustafa |
| 67 | How do we elicit Arabizi without priming? | Give writers English or Arabic-script scenarios (never Arabizi) and ask them to type "as you would on WhatsApp". Then annotate the gold Arabic with variants | Natural spelling variation is the whole problem | Decide | Moustafa |
| 68 | How do we get consent for natural sentences? | An IRB-approved form. Donors retype or paraphrase their own messages, remove names and numbers, and can withdraw until the freeze | Ethics and provenance | Ask instructor | Moustafa |
| 69 | Which external data can we use? | MADAR / MADAR CODA: yes for research use (non-commercial licence; don't redistribute raw text). LDC BOLT: skip (Egyptian, LDC non-member licence with a fee).\[27\]\[28\] Jordanian Arabizi corpus (25k pairs): only if its licence is clear, and never in test. AladdinBench (has Lebanese Arabizi, on Hugging Face): check its licence and use it only as an extra sanity set\[15\]\[29\]\[30\]\[31\] | Respect licences and ToS (guardrail) | Verify | Moustafa |
| 70 | Is AI-generated Arabizi allowed? | No, not in train, dev or test. Every row records writer ID, date and method | Data provenance; avoids circular evaluation | Decide | Moustafa |
| 71 | Can we use Yamli as a reference? | No automated access: Yamli's ToS says "You agree not to access or attempts to access the services through any automated means". At most, a human types ≤100 test sentences into the Yamli website by hand, if the instructor agrees. Note that Yamli's privacy policy says its "server logs contain the words and characters that you type" and that it "may sell or otherwise provide access" to third parties, so use synthetic sentences only\[32\]\[33\] | ToS and privacy (guardrail) | Ask instructor | Moustafa |
| 72 | How do we split the data? | Split by writer AND by sentence. Test 50%, dev 25%, train 25%. No writer and no seed sentence appears in two splits | Prevents leakage | Decide | Moustafa |
| 73 | How do we check annotation quality? | A second annotator labels 20% of the gold. Report agreement; a third person adjudicates disagreements | Makes ground truth defensible | Decide | Moustafa |

## 10. Evaluation (Q74–80)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 74 | What are the primary metrics and targets? | Multi-reference word accuracy ≥90%, top-3 ≥97%, keep-Latin F1 ≥0.95, MSA-rewrite ≈0, and context subset ≥ B1 + 10 points | Pre-registered success criteria (Eval 20%) | Decide | Moustafa |
| 75 | How are the baselines built? | B0 = rules only; B1 = top-1 by dictionary frequency ("Yamli-style", without Yamli); B2 = KenLM 3-gram trained on the Arabic side of the train split | Baselines are required | Decide | Mohamad |
| 76 | How is the "context subset" defined? | Before the freeze, tag about 150 test sentences where the correct output needs context (clitics like la/l-, homographs, attached prepositions) | Isolates the agent's added value | Decide | Moustafa |
| 77 | Which statistics? | Paired bootstrap (10,000 resamples), 95% confidence intervals for every comparison, plus per-writer breakdown | Credible claims | Decide | Moustafa |
| 78 | User study design? | 6–9 participants, within-subject, counterbalanced: 5 fixed tasks with our keyboard vs Yamli copy-paste. Measure time, corrections, final errors and SUS. About 30 minutes per person. Memory sessions 1–5 run as a separate short diary track | Real-user evidence | Ask users | Moustafa |
| 79 | How do we measure latency fairly? | os_signpost plus spans around the resolve call, on named hardware, with a cold and a warm run. Report p50 and p95 | Latency claims need method | Decide | Mohamad |
| 80 | What is in the adversarial set? | 50 items: injection in Arabizi or English ("ignore instructions…"), 500-character input, emoji, zero-width and RTL marks, mixed scripts, key bursts | Adversarial testing is required | Decide | Moustafa |

## 11. AgentOps and observability (Q81–84)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 81 | Which spans and attributes? | Spans: sentence_resolve, xpc_call, llm_decode, memory_lookup, curator_cycle, replay_eval, write_memory (keystroke spans sampled). Attributes: latency, token counts, k, decision, confidence, error type, hashed token IDs. **Never raw text** | Traces and metrics (AgentOps 15%) | Decide | Mohamad |
| 82 | Which exporter? | opentelemetry-swift: tracing is stable. Write to a local JSONL file. In dev only, send OTLP gRPC to Jaeger or Langfuse (the README says only gRPC is production-ready and HTTP is still experimental)\[34\]\[35\] | Works offline; keeps the zero-network claim for users | Verify | Mohamad |
| 83 | How do we report "cost per successful task"? | API cost is $0. Report compute cost per correctly committed sentence (LLM ms and tokens), and compare it with an estimate of VoiceType's OpenAI cost for the same test set | A required metric | Decide | Mohamad |
| 84 | How do we show operations at the demo? | A script that turns the local traces into an HTML report (latency histogram, fallback rate, asks/100 words, errors) plus a Jaeger screenshot | Evidence on the poster (AgentOps, Poster) | Decide | Mohamad |

## 12. Reliability and failure handling (Q85–87)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 85 | What does the Failure Matrix look like? | Columns: failure · trigger · detection · response · what the user sees · test ID. At least the 15 agreed rows, each with an automated test | Required artefact (Reliability 15%) | Decide | Omar |
| 86 | Retry and circuit-breaker policy? | No retry inside a sentence (latency). Restart the XPC service once with backoff after a crash. After 3 failures in 5 minutes, disable the LLM for 10 minutes and show a small status icon | Graceful degradation | Decide | Omar |
| 87 | How do failures become regression tests? | Every bug gets an ID, and a frozen case goes into `tests/regression/` before the fix merges | Required: "failures → regression tests" | Decide | Team |

## 13. Security and threat model (Q88–91)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 88 | Which assets and attackers? | Assets: typed text, memory DB, key, contacts, model file. Attackers: malicious text pasted or typed (injection), local malware, another user on the same Mac, supply chain (model or package) | Threat model required (Security 15%) | Decide | Team |
| 89 | Prompt-injection defence? | The grammar allows only indices or ASK; user text sits inside delimiters as data; the model has no tools of its own; the adversarial set is in CI | Defence you can test, not just claim | Decide | Mohamad |
| 90 | What secrets exist? | None at runtime (no API keys). Keep it that way with gitleaks plus GitHub secret scanning, and remove VoiceType's OpenAI path completely | Secret protection | Decide | Omar |
| 91 | How do we keep PII out of logs and data? | Redact at the source, and add a unit test that fails if any span attribute contains Arabic or Latin word text. Scrub PII from test data before the freeze | PII protection | Decide | Moustafa |

## 14. Software engineering and CI/CD (Q92–94)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 92 | Repo layout? | Monorepo: `ime/` (IMK app), `resolver-xpc/`, `Engine/` (pure Swift package, most tests), `eval/` (Python), `data/` (pointers + hashes, no raw licensed text), `docs/`, one `config.yaml` | Clean modular repo (SE 10%) | Decide | Omar |
| 93 | Which CI? | GitHub Actions on macOS runners: build, unit tests, SwiftLint, Codecov, CodeQL Swift (CodeQL says Swift analysis "requires macOS"), Dependabot, gitleaks, and a nightly eval with gates (accuracy, latency, schema violations = 0)\[5\]\[36\] | Bonus +10% and quality | Decide | Omar |
| 94 | Branch and PR rules? | Protected `main`, 1 review, required checks, linked issues, a GitHub Projects board with the 13 stages | Project management bonus | Decide | Team |

## 15. Documentation, reproducibility, poster and demo (Q95–97)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 95 | How does a grader reproduce the results? | `make setup` (downloads the model, checks SHA) → `make eval` (rebuilds every table from the frozen test hash). Pinned versions and the hardware are recorded in the report | Docs & reproducibility 10% | Decide | Moustafa |
| 96 | What is the live demo script? | 5 minutes: normal message in WhatsApp → "b3at 100$ la mohammad" fixed by context → an ask chooser → approving a learned habit → silence in a password field → kill XPC (fallback) → injection attempt → network-off proof | Demo with edge cases and failures (Poster & demo 10%) | Decide | Omar |
| 97 | Poster plan? | Exactly the 9 required sections, with Pilot Evidence numbers and an architecture diagram that shows the trust boundaries (IME / XPC / memory) | Poster 10% | Decide | Team |

## 16. Logistics, roles, risks and legal (Q98–100)

| # | Question | Recommended answer | Why (rubric) | Type | Owner |
|---|---|---|---|---|---|
| 98 | What are the real poster and final dates? | Ask now. Plan as if the poster is about mid-November: test set frozen by week 3, pilot numbers by week 4. [ASSUMPTION: dates unconfirmed] | The roadmap depends on it | Ask instructor | Team |
| 99 | Roles and fallback scopes? | Omar: IME/macOS; Mohamad: model/resolver/AgentOps; Moustafa: users/data/eval/memory. Fallbacks: F1 Agent #2 becomes a deterministic learner; F2 drop the ask; F3 word-by-word commit only. Decide the trigger dates now | Risk management | Decide | Team |
| 100 | Licences of our repo and reused parts? | MIT for your own code; Apache 2.0 notice for Qwen; no raw MADAR text in a public repo; VoiceType code only with written permission and a confirmed licence.\[37\] Ask whether a public repo is allowed. [ASSUMPTION: public repo] | Legal and ethics guardrails | Ask instructor | Team |

---

## Top 10 blocking questions (answer these first)
1. **Q7**: Is Path A confirmed?
2. **Q10 + Q11 + Q12**: IRB exemption application with Dr. Mohanna as PI; CITI done by all three. AUB's IRB manual gives exempt studies "from eight days to two weeks for review and approval", so submit before any interview.
3. **Q98**: Real poster and final dates.
4. **Q30 / Q100**: VoiceType reuse permission and licence.
5. **Q71**: Is manual Yamli referencing allowed? (Automated access is forbidden.)
6. **Q49 + Q50**: Runtime and model bake-off (llama.cpp + Qwen2.5; Apple Foundation Models ruled out).
7. **Q32 + Q33 + Q34**: IME spike on state, Enter and marked text across the 7 target apps.
8. **Q15 + Q16**: Orthography guide and variant policy (this defines "correct").
9. **Q66 + Q72**: Test-set size, split and freeze date.
10. **Q60**: SQLCipher-through-GRDB spike, or the CryptoKit fallback.

## Email to Dr. Mohanna (draft)

> **Subject:** EECE 503N/798S – Arabizi Keyboard team (Al Itani, Al Masri, Abbara) – 8 questions before we build
>
> Dear Dr. Mohanna,
>
> We are starting "A Local, Personal Arabizi Keyboard for macOS". Before building, we need your answers on these points:
> 1. Can you confirm that our project counts as **Path A (application)**?
> 2. What are the exact **poster and final demo dates**?
> 3. May we **reuse parts of VoiceType** (rule tables and ideas)? Under which licence? We plan to remove the Yamli and OpenAI paths entirely.
> 4. **IRB:** AUB's IRB manual says course projects with outside participants must be submitted before they begin. Will you act as **faculty PI** on our student exemption application for interviews, data donation and a 6–9 person user study?
> 5. **Yamli:** its Terms of Service forbid automated access, so we will not call it. May a team member type a small synthetic sample (≤100 sentences) into the Yamli website by hand, as a comparison reference?
> 6. May our **repository be public**, given that we will not commit raw MADAR (non-commercial licence) text?
> 7. Does AUB have an **Apple Developer team** we can use for signing and notarization, or is a local unsigned install acceptable for the demo?
> 8. Is our design of **two agents** (sentence resolver + memory curator, everything else deterministic) a scope you consider justified?
>
> Thank you,
> Omar Al Itani, Mohamad Al Masri, Moustafa Abbara

## Caveats
- **VoiceType licence and README not verified.** The repo page could not be opened during research. Check its LICENSE file yourselves (if there is none, default copyright applies, so the code is not reusable without permission).
- **AUB IRB documents are older.** The manual is "Version 8 February 2020" and the student exemption form is "Form Version # 5, April 22, 2010". AUB's 2025-26 HSON PhD Student Handbook repeats the same exempt timeline ("around 8 days to two weeks"), but still confirm the current process with the IRB office. Q10 is written conservatively.
- **The macOS 27 IMK behaviour** (controller recreated after each key) comes from one developer's pull request.\[7\] Treat it as a spike item, not a fact.
- **Gemma 3 1B language support is reported differently** by different sources (English-only in Hugging Face's launch table vs "140 languages" for the family).\[20\]\[21\] Your bake-off decides.
- **The CodeQL and Xcode 27 gap** comes from a third-party issue dated 2026-10-06.\[6\] Re-check CodeQL's supported-versions page before setting up CI.
- **All numeric targets** (90%, ECE ≤0.05, etc.) are the team's own pre-registered goals, not external benchmarks. Lebanese Arabizi has no standard public test set, which is why you are building your own.

## Sources

1. [Apple Intelligence has no Arabic — and UAE misses a health feature](https://tbreak.com/apple-intelligence-arabic-uae-watch-hypertension/)
2. <https://www.aub.edu.lb/irb/Documents/irb_manual%20-%20revised-%20Version%208%20February%202020-.pdf>
3. <https://www.aub.edu.lb/irb/Documents/4-1StudentApplicationExemptForm.pdf>
4. [ci: add CodeQL code scanning for Swift and GitHub Actions by lquainta · Pull Request #106 · lquainta/RepoHub](https://github.com/lquainta/RepoHub/pull/106)
5. [Supported languages and frameworks - CodeQL - GitHub](https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/)
6. [Restore CodeQL Swift analysis once CodeQL supports macOS 27 and Swift 6.4 · Issue #54 · tomada1114/townsfolk](https://github.com/tomada1114/townsfolk/issues/54)
7. [Issue #4: InputMethodKit入力・変換フローの試作 by kiyoka · Pull Request #7 · kiyoka/Sumibi-mac](https://github.com/kiyoka/Sumibi-mac/pull/7)
8. [Input Method Kit Release Note](https://developer.apple.com/library/archive/releasenotes/Cocoa/RN-InputMethodKit/index.html)
9. [Technical Note TN2150: Using Secure Event Input Fairly](https://developer.apple.com/library/archive/technotes/tn2150/_index.html)
10. [Potential macOS secure input bypass for refocused revealed password/PIN fields \[519230894\] - Chromium](https://issues.chromium.org/issues/519230894)
11. [Potential secure event input bypass in RenderWidgetHostViewMac on password type toggles \[519233776\] - Chromium](https://issues.chromium.org/issues/519233776)
12. [macOS Input Method Development Guidelines for 2026](https://shikisuen.medium.com/macos-input-method-development-guidelines-for-2026-5123461fa53b)
13. [GitHub - ensan-hcl/macOS\_IMKitSample\_2021: InputMethodKit Sample App with macOS12, Xcode13, Swift5.6 in 2022.](https://github.com/ensan-hcl/macOS_IMKitSample_2021)
14. [Arabizi](https://en.wikipedia.org/wiki/Arabizi)
15. [Resources - NYU Abu Dhabi](https://nyuad.nyu.edu/en/research/faculty-labs-and-projects/computational-approaches-to-modeling-language-lab/resources.html)
16. [llama.cpp/grammars/README.md at master · ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md)
17. [Major updates for Apple’s software platforms are now available - Apple](https://www.apple.com/newsroom/2026/09/major-updates-for-apples-software-platforms-are-now-available/)
18. [Qwen2.5-Coder Series: Powerful, Diverse, Practical - Alibaba Cloud Community](https://www.alibabacloud.com/blog/qwen2-5-coder-series-powerful-diverse-practical_601765)
19. [Qwen2.5-LLM: Extending the Boundary of LLMs - Alibaba Cloud Community](https://www.alibabacloud.com/blog/qwen2-5-llm-extending-the-boundary-of-llms_601786)
20. [Welcome Gemma 3: Google's all new multimodal, multilingual, long context open LLM](https://huggingface.co/blog/gemma3)
21. [gemma-3](https://lmstudio.ai/models/gemma-3)
22. [llama.cpp/grammars/README.md · Steven10429/apply\_lora\_and\_quantize at main](https://huggingface.co/spaces/Steven10429/apply_lora_and_quantize/blob/main/llama.cpp/grammars/README.md)
23. [Questions regarding the future of GRDB + SQLCipher · groue/GRDB.swift · Discussion #1495](https://github.com/groue/GRDB.swift/discussions/1495)
24. [GRDB v7.10.0, Android, Linux, Windows, and SQLCipher+SwiftPM - GRDB - Swift Forums](https://forums.swift.org/t/grdb-v7-10-0-android-linux-windows-and-sqlcipher-swiftpm/84754)
25. [GRDB.swift on CocoaPods.org](https://cocoapods.org/pods/GRDB.swift)
26. [SQLCipher · GitHub](https://github.com/sqlcipher)
27. [BOLT Egyptian Arabic SMS/Chat and Transliteration - Linguistic Data Consortium](https://catalog.ldc.upenn.edu/LDC2017T07)
28. [Linguistic Data Consortium: 2025](http://ldc-upenn.blogspot.com/2025/)
29. [Arabizi vs LLMs: Can the Genie Understand the Language of Aladdin?](https://arxiv.org/html/2502.20973v2)
30. [GitHub - bashartalafha/Arabizi-Transliteration · GitHub](https://github.com/bashartalafha/Arabizi-Transliteration)
31. [GitHub - NNLP-IL/Arabic-Resources: A comprehensive list of Arabic NLP resources. · GitHub](https://github.com/NNLP-IL/Arabic-Resources)
32. [Yamli Terms of Service](https://www.yamli.com/terms/)
33. [Yamli Privacy Policy](https://httwww.yamli.com/privacy/)
34. [OpenTelemetry for Swift: iOS & Server Tracing with OpenObserve](https://openobserve.ai/opentelemetry/swift/)
35. [GitHub - open-telemetry/opentelemetry-swift: OpenTelemetry API for Swift · GitHub](https://github.com/open-telemetry/opentelemetry-swift)
36. [Workflow configuration options for code scanning - GitHub Docs](https://docs.github.com/en/code-security/code-scanning/creating-an-advanced-setup-for-code-scanning/customizing-your-advanced-setup-for-code-scanning)
37. [LICENSE · Qwen/Qwen2.5-1.5B-Instruct at main](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct/blob/main/LICENSE)
