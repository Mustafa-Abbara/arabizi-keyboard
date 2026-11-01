# Threat model

Harfi is an input method: it sees every key typed while it is selected. The design goal is that what a user types never leaves their Mac and is never written down, and that a broken or tampered part fails safe (rules or Latin text, never a leak). As of 1 Nov 2026 (v0.1.0).

## What data exists, and where it goes

| Data | Where it lives | Leaves the Mac? |
|---|---|---|
| Text being typed (Latin and its Arabic) | Memory of the keyboard and the engine service, for the message being typed; the live preview keeps the last 16 conversions in memory | Never. Not logged, not stored |
| Corrections: one typed word, the spelling chosen and the one replaced, with a date | `~/Library/Application Support/ArabiziKeyboard/corrections.bin`, AES-GCM encrypted, entries older than 30 days dropped; the key in `corrections.key` beside it (mode 0600, folder 0700), folder excluded from backups | Never. "Forget" and "Forget all" in Harfi's window delete them |
| Settings and practice ticks | The keyboard's user defaults (`lb.aub.arabizi.inputmethod.ArabiziIME`) | Never |
| Logs | macOS unified log, subsystem `lb.aub.arabizi`: key kinds, word positions, lengths, outcomes, timings, model status | Only if the user shares a log. Never the text (log calls mark only these values public) |
| Model and rule files | Inside the app bundle | They are downloaded once by the installer; nothing goes up |

There is no telemetry, no crash reporting to a server, no update check and no account.

## Boundaries

- **Engine service sandbox** (ADR 0020): the model runs in `ArabiziEngineXPC.xpc` with the App Sandbox and no network entitlement, reading only its own bundle. `arabizi-engine-check` probes the network from inside it and must report `blocked`.
- **Keyboard process**: not sandboxed (InputMethodKit), but it makes no network calls (`https://` appears in its code only in the link detector).
- **Password fields**: when macOS reports secure input, the keyboard composes nothing and keys go straight to the field.
- **Installer**: the only network use. `scripts/install_harfi.sh` and `harfi-setup.sh` download the app and the model from this repository's GitHub releases over HTTPS and check SHA-256 sums before installing.

## Threats and answers

| Threat | Answer | Residual risk |
|---|---|---|
| Typed text leaks (logs, files, network) | Nothing is logged or stored except single corrected words; the engine has no network; the keyboard makes no requests | A future change could add logging: reviews check `privacy: .public` on every log call |
| Tampered or corrupt model file | The engine hashes the model at load and refuses one that differs from `config/models.json` (falls back to rules); the installer checks the same hash | The hash and the files come from the same repository: an attacker with write access to it could change both |
| Tampered app release | Releases are built by GitHub Actions from a tagged `main` commit (protected branch, required checks); the installer checks `SHA256SUMS` | No Developer ID or notarisation: macOS cannot vouch for the app; trust rests on the GitHub account and the repository (two-factor sign-in on the account is recommended) |
| Malicious model output (text that looks like a command) | Output is only text inserted where the user types; output checks reject invented Latin words, lost placeholders, changed emoji and runaway length | The model can still write a wrong but plausible Arabic word (marked doubtful when it holds a letter nobody typed) |
| Other software running as the same user reads the correction record | The key file is user-only and the folder is out of backups | Not protected against same-user malware: an ad-hoc signed app cannot use a stable Keychain item (ADR 0027 decision 5). The record holds single words, not messages |
| Someone with the Mac reads past messages | No messages are kept | Corrections (single words, 30 days) are readable with the key file |
| Supply chain (llama.cpp, Swift packages, Python tools) | llama.cpp XCFramework pinned by URL and checksum (ADR 0017); Python dependencies locked (`uv.lock`); Dependabot and secret scanning on | A pinned dependency can still carry a flaw: updates are reviewed PRs |

## What this model does not cover

Malware with root or the user's privileges (it can read keys before any input method), a compromised macOS, and screen recording by other apps.
