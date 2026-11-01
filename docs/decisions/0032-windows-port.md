# ADR 0032: Windows port: reuse the Swift core behind a TSF text service

- **Status:** Proposed, 1 Nov 2026 (to be agreed with Mohamad before work starts, ADR 0011 #10)
- **Deciders:** Moustafa Abbara, Mohamad Al Masri
- **Stage:** after P6

## Context

Harfi runs on macOS: an InputMethodKit keyboard, a sandboxed XPC engine with llama.cpp, and `ArabiziCore`, about 3,000 lines of plain Swift that hold all the behaviour (rules, protected spans, output checks, English guard, suggestions, spelling, the key-by-key composer). Windows keyboards are Text Services Framework (TSF) text input processors: COM DLLs loaded into every app. Mohamad works on Windows and contributes by pull request (ADR 0011). The Mac and Windows outputs must stay identical; the Swift rules already match the Python reference through `Fixtures/b0_parity.json`.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **A. C++ TSF shell + `ArabiziCore` compiled for Windows as a DLL with a small C API** | No second copy of the logic: one set of tests and fixtures; Swift 6 has an official Windows toolchain; `ArabiziCore` uses only Foundation (CryptoKit is replaced by swift-crypto, same API) | Swift on Windows is less used; the Swift runtime DLLs ship with the app |
| B. Rewrite everything in C++ | One language on Windows; TSF samples are C++ | ~3,000 lines rewritten and kept in step by parity tests forever; every fix done twice |
| C. C# TSF shell + Swift core | Faster UI work in C# | TSF from C# needs COM interop for every interface; two runtimes (.NET and Swift) |

## Decision (proposed)

| # | Decision | Source |
|---|---|---|
| 1 | Option A: a C++ TSF text service (`Apps/HarfiWindows`) calls `ArabiziCore` through a C API (`@_cdecl` functions taking and returning UTF-8 JSON, the same shapes as `ArabiziContracts`). | **Recommendation** |
| 2 | The engine runs in its own process, as on the Mac: `ArabiziEngine` with llama.cpp's Windows build (CPU, Vulkan where available), started by the text service, reached over a named pipe with the `ArabiziContracts` JSON, in an AppContainer **without** the `internetClient` capability (the Windows counterpart of the no-network sandbox, ADR 0020). | **Recommendation** |
| 3 | First step is a spike: `swift build` and `swift test` of `ArabiziCore` on Windows. If it cannot pass in two days, fall back to option B for the rules only and keep the parity fixtures as the contract. | **Recommendation** |
| 4 | Same look and words: the preview box and chips as layered Win32 windows in the Cedar and sand palette (`design/palette.json`) with Noto Naskh Arabic; strings from `docs/VOICE.md`. | **Recommendation** |
| 5 | Install without a paid certificate: a zip with an install script that registers the DLL for the current user; Windows SmartScreen will warn, and the guide explains it, as `docs/INSTALL.md` does for macOS. Whether TSF registration works per user without admin rights is checked in the spike. | **Recommendation** |
| 6 | Mohamad builds it by pull request, one task at a time (tracking issue); measurements on his machine are smoke runs (ADR 0011 #9). | ADR 0011 |

## Tasks

1. Spike: `ArabiziCore` builds and its tests pass on Windows (swift-crypto in place of CryptoKit behind `#if canImport(CryptoKit)`).
2. C API for the core: convert with the rules, the composer's key handling, suggestions, spelling, the English guard.
3. TSF text service: registration, keys, composition (underlined text), Enter converts with the rules.
4. Engine process over a named pipe, in an AppContainer without network; the model from the `model-v3` release.
5. Preview box and correction chips, palette and font.
6. Installer script and a Windows section in `docs/INSTALL.md`.
7. Parity: the same output as the Mac on `b0_parity.json` and the core tests; latency smoke run.

## Consequences

- One behaviour for both platforms: a fix in `ArabiziCore` reaches Windows by rebuilding.
- `ArabiziCore` must stay free of Apple-only frameworks (AppKit, InputMethodKit, CryptoKit without a fallback); CI could add a Windows job for `swift test` once task 1 passes.
- The Mac app is unchanged.
