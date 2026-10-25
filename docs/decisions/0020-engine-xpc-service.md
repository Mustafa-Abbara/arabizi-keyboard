# ADR 0020: The sandboxed engine service and the keyboard switch-on (P5)

- **Status:** accepted
- **Date:** 2026-10-16
- **Deciders:** Moustafa Abbara
- **Stage:** P5

## Context

Roadmap P5 step 5: the engine runs in a sandboxed XPC service with **no network entitlement**; the keyboard talks to it, and if the service fails the keyboard still converts with the rules. ADR 0005 #3 switches the fine-tuned model on once the engine can run it. The engine itself is ADR 0019.

## Decision

| # | Decision | Source |
|---|---|---|
| 1 | `Apps/ArabiziEngineXPC` (SwiftPM executable) hosts `Engine`; `scripts/build_ime.sh` wraps it into `ArabiziIME.app/Contents/XPCServices/ArabiziEngineXPC.xpc` (bundle id `lb.aub.arabizi.inputmethod.ArabiziIME.Engine`, `XPC!`). Its only entitlement is `com.apple.security.app-sandbox`; no `network.client` or `network.server`. | Roadmap P5 step 5 |
| 2 | Everything the service reads is inside its own bundle (the sandbox allows nothing else): `llama.framework` in `Contents/Frameworks` (rpath `@executable_path/../Frameworks`), and `engine.json`, `models.json`, the two rule files and the configured model file in `Contents/Resources`. The model is copied from `models/` at build time with an APFS clone (`cp -c`), so the 0.8 GB copy is instant and takes no extra disk; without the file the service runs on the rules. | **Recommendation** (ADR 0017's "copy into the bundle" option) |
| 3 | The service answers on the rules at once and loads the model (SHA-256 check + load) in the background, then swaps; cold this takes about 27 s on the Air, warm about 2 s. Requests during loading get the rules (`fallbackModelUnavailable`), so typing is never blocked. | **Recommendation** |
| 4 | The XPC protocol (`ArabiziEngineServiceProtocol`, in ArabiziContracts) carries the JSON forms of `ConvertRequest`/`ConvertResponse`, plus `status` (model state, loading, network probe; no user text). | **Recommendation** |
| 5 | The keyboard (`EngineClient`) sends the text with the configured deadline (1,500 ms) and waits at most the deadline plus 500 ms; no reply, an error or an unreadable answer → its own rule converter, as before. It wakes the service when the first text field activates the keyboard, so the model loads before the first Enter. For now the wait happens on the keyboard's thread (Enter is synchronous); P6 makes the conversion asynchronous with a "…" while waiting. | Roadmap P5/P6; margin and warm-up **Recommendation** |
| 6 | `arabizi-engine-check` (a diagnostic in the app's `Contents/MacOS`, where macOS lets it reach the embedded service) prints the service status, the network probe and one converted public sentence; it exits non-zero if the network is not blocked. | **Recommendation** |
| 7 | **The model is switched on:** `config/engine.json` names `arabizi-llama3.2-1b-v1` with `use_model: true` (ADR 0005 #3). | ADR 0005 |

## Evidence (16 Oct 2026, the 8 GB Air)

- `codesign -d --entitlements -` on the service: `com.apple.security.app-sandbox = true`, nothing else. `codesign --verify --deep --strict` on the app: valid.
- `arabizi-engine-check`: `state: ready`, `model: arabizi-llama3.2-1b-v1`, `network: blocked: NSURLErrorDomain -1003`; a public sentence with numbers converted by the model (`outcome: model`, 958 ms cold), numbers restored.
- System log: `kernel (Sandbox): ArabiziEngineXPC deny(1) network-outbound /private/var/run/mDNSResponder`: the kernel's sandbox refuses the service's network access.

## Consequences

- The app is now about 0.8 GB (the model inside the service); `scripts/install_ime.sh` copies it with APFS clones.
- macOS may stop an idle XPC service; the next request starts it again on the rules while the model reloads (about 2 s warm).
- The keyboard waits up to 2 s on Enter when the model is slow; P6 turns this into an asynchronous conversion with feedback.
- The P5 gate items covered here: no network entitlement (codesign output) and a network request from inside failing (log). Still open: "a forced timeout and a forced bad output both return the rule fallback" is covered by the engine's unit tests (ADR 0019), and "CI is required on main" needs `bootstrap.py protect --checks …`.
