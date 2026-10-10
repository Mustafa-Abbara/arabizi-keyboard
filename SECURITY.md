# Security policy

## Reporting a vulnerability

Please **do not open a public issue**. Use GitHub's private vulnerability reporting instead: *Security* tab → *Report a vulnerability*. We aim to respond within 7 days during the semester.

## In scope

- Any way typed text, the memory database, or its encryption key can leave the user's Mac.
- Ways to make the engine use the network, load a tampered model, or write memory without passing `replay_eval`.
- Prompt-injection inputs that change decisions outside their own slot.
- Leaks of secrets or personal data in the repository, logs or traces.

## Design commitments

The design aims for these (see `docs/THREAT_MODEL.md` once written in S11):

- The engine process has no network entitlement.
- Model files are checked against a SHA-256 lock file before loading.
- Memory is encrypted at rest with a device-only Keychain key.
- Logs and traces contain counts and hashes, never typed text.
