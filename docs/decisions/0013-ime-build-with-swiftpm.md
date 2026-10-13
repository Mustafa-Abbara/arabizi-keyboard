# ADR 0013: Build the input method with Swift Package Manager and a bundle script

- **Status:** accepted
- **Date:** 2026-10-13
- **Deciders:** Moustafa Abbara (Claude's recommendation)
- **Stage:** P1

## Context

The roadmap's P1 step 1 (from v1 S2) says to create the input method as an Xcode app project. A `.xcodeproj` is a large generated file that is hard to review in PRs and easy to break in merges. XcodeGen and Tuist are not installed. An input method only needs an executable, an `Info.plist` and an icon inside an `.app` folder.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| Xcode project (`.xcodeproj`) | Xcode's Run/debug UI; the roadmap's default | Unreviewable project file; GUI steps hard to reproduce; extra work for CI |
| XcodeGen / Tuist (`project.yml` → `.xcodeproj`) | Reviewable spec, Xcode UI | Extra tool to install and pin |
| **Swift package + `scripts/build_ime.sh`** | Plain text, reviewable; `swift build`/`swift test` in CI; logic in `Packages/ArabiziCore` is unit-tested; Xcode can still open `Package.swift` | Bundle assembled by a script; no Xcode "Run" for the app (an input method cannot be run from Xcode anyway; attach the debugger to the running process) |

## Decision

**Swift package + bundle script** [Claude's recommendation]:

- `Packages/ArabiziCore`: pure Swift logic (typing behaviour `Composer`, the P1 `ToyTransliterator`), tested with Swift Testing.
- `Apps/ArabiziIME`: executable package (IMK server + a thin `IMKInputController`), linked to InputMethodKit.
- `scripts/build_ime.sh` assembles `build/ArabiziIME.app` (executable, `Info.plist`, an icon drawn by `Tools/make_icon.swift`), and signs it ad-hoc (no Developer ID, A5). `scripts/install_ime.sh` copies it to `~/Library/Input Methods` and registers it; `scripts/uninstall_ime.sh` removes it.
- The spike is not sandboxed. P5 adds the sandboxed XPC engine.

## Consequences

- CI (P5) can build and test with `swift build` / `swift test` and run the bundle script, with no Xcode project.
- If an Xcode project is needed later (e.g. for an XPC service target), XcodeGen can be added then with a new ADR.
- The P1 typing behaviour is tested without a GUI; the per-app matrix (`docs/spikes/ime_app_matrix.md`) still needs a person.
