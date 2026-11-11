# Threat model

Harfi is an input method: it sees every key typed while it is selected. The design goal is that what a user types never leaves their Mac and is never written down, and that a broken or tampered part fails safe (rules or Latin text, never a leak). As of 1 Nov 2026 (v0.1.0); the Windows keyboard has [its own section](#windows-adr-0032).

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

## Windows (ADR 0032)

The same goal on Windows: what a user types never leaves the PC and is never written down, and a broken or tampered part fails safe. The parts differ: the keyboard is a TSF text service (`HarfiTIP.dll`) loaded into every app the user types in, and the model runs in its own process, `harfi-engine.exe`, reached over a named pipe. As of 7 Nov 2026.

### What data exists, and where it goes

| Data | Where it lives | Leaves the PC? |
|---|---|---|
| Text being typed (Latin and its Arabic) | Memory of the keyboard in the app being typed in, and of the engine for the request; the live preview keeps the engine's last 16 conversions per app in memory | Never. Not logged, not stored |
| Corrections, and habits the user refused (ADR 0027, 0033) | `%LOCALAPPDATA%\Harfi\words\corrections.bin` and `refused.bin`, AES-GCM encrypted (swift-crypto), entries older than 30 days dropped; the key in `corrections.key` beside them. The installer gives `words\` owner-only access (the account and SYSTEM). `install.ps1 -Uninstall` deletes them | Never. `harfi-words forget`, `refuse` and `wipe` change or delete them |
| Settings (the Harfi window) | `%LOCALAPPDATA%\Harfi\settings.json`: on/off switches only (live preview, faster preview), no text | Never |
| Tip counters | `HKCU\Software\Harfi` (how many times a tip was shown or a feature used: numbers only) | Never |
| Engine log | `%LOCALAPPDATA%\Harfi\engine.log`: start, model state, each conversion's outcome and time | Only if the user shares it. Never the text |
| Debug log (off unless `HKCU\Software\Harfi\DebugLog` is 1) | `%LOCALAPPDATA%\Harfi\debug.log`: lifecycle events and the app's name | Only if shared. Never the text |
| Model and rule files | `%LOCALAPPDATA%\Harfi` | Downloaded once by `install.ps1`; nothing goes up |

There is no telemetry, no crash reporting to a server, no update check and no account.

### Boundaries

- **Engine process:** runs as the user, **not sandboxed**. Its code makes no network calls, but unlike the Mac's XPC service nothing enforces it (an app container without the `internetClient` capability is the planned counterpart, ADR 0032).
- **Engine pipe** `\\.\pipe\harfi-engine-<SID>`: named after the account's SID; open to that account, SYSTEM and app containers (read and write, also from low integrity), never to the network (`PIPE_REJECT_REMOTE_CLIENTS`). One engine per account.
- **Keyboard in each app:** makes no network calls. Before writing to the pipe it checks that the process at the other end runs as this account (or, when that cannot be read, is its own `harfi-engine.exe`).
- **Password and PIN fields:** fields whose input scope is a password or PIN are never composed; keys are typed as Latin.
- **Installer:** the only network use. `install.ps1` downloads the model's parts from this repository's `model-v3` release over HTTPS and checks each part's SHA-256 and the whole file's against `config/models.json`.

### Threats and answers

| Threat | Answer | Residual risk |
|---|---|---|
| Typed text leaks (logs, files, network) | Nothing is logged or stored except single corrected words; the engine log and debug log hold outcomes and timings only; neither the keyboard nor the engine makes requests | The engine is not sandboxed: a future change that added a network call would not be blocked, only caught in review |
| Another account on the PC takes the engine's pipe name to receive typed text | The pipe is named by SID, and the keyboard refuses a server that is not this account's engine; it then uses its own rules | Denial of service: that account can keep the real engine from starting, so the user gets the rules |
| Another account, or a low-integrity process, uses the engine | Other accounts are not in the pipe's access list. Sandboxed and low-integrity processes of the same user may connect (so Store apps get the model), and can only ask for conversions | Such a process can keep the engine busy (slower conversions, no data exposed) |
| Store apps or sandboxed processes read the corrections | `words\` is not readable by app containers (owner and SYSTEM only), though the rest of the keyboard's folder is, so the keyboard loads in Store apps | Not protected against software running as the same user: the key sits beside the record (as on the Mac; DPAPI would protect it from other accounts only) |
| A file in the keyboard's folder replaced by software running as the user | Nothing checks the keyboard's DLLs at load; the engine checks the model's SHA-256 and refuses a different one | The folder is user-writable, and the installer also registers the keyboard machine-wide (for apps that load keyboards without COM), which elevated apps use too: same-user malware could replace `HarfiTIP.dll` and run inside an app running as administrator. Installing to Program Files (writable by administrators only) closes it: task 6, the real installer |
| Tampered package | The `harfi-windows` package is built by GitHub Actions from the repository; the model is checked by SHA-256 | Nothing is code-signed: Windows cannot vouch for the files, SmartScreen may warn, and trust rests on the GitHub account and repository |
| Supply chain (llama.cpp, Swift packages) | llama.cpp is built from source at release b11429 (the Mac's pin), fetched by tag; Swift packages are resolved from their repositories | A tag can be moved upstream: CI should check out commit `d81235049` itself, not the tag |

### What this does not cover on Windows

Malware running as the user or as administrator (it can read keys before any input method), a compromised Windows, other apps recording the screen, and backups or sync tools the user points at `%LOCALAPPDATA%` (Windows has no per-folder "exclude from backup" flag like the Mac's).
