# S0 runbook: setup, confirmations and project management

Phase 1 roadmap stage **P0** (the v1 stage S0, unchanged; the file name is kept). Goal: before writing product code, (1) ask for the permissions we depend on and (2) set up the "factory": repo, board, branch rules and tools. Bonus marks for process need **evidence over time**, so the board and PR history must start in Week 1.

## 1. Confirmations (Moustafa, day 1)

Send the message in [ADR 0001](../decisions/0001-instructor-confirmations.md). Record each answer in that ADR and flip the matching row in [ASSUMPTIONS.md](../ASSUMPTIONS.md).

## 2. Tools (everyone)

| | macOS (Omar, Mohamad) | Windows (Moustafa) |
|---|---|---|
| Base | Xcode from the App Store, then `xcode-select --install` | — (Swift work runs on macOS + CI) |
| Packages | `brew install gh uv swiftlint swiftformat gitleaks cmake python@3.12` | `winget install GitHub.cli astral-sh.uv` |
| Pre-commit | `uv tool install pre-commit` | `uv tool install pre-commit` |
| Docker | `brew install colima docker`, then `colima start --cpu 2 --memory 2` (recommended on 8 GB Macs; Docker Desktop is fine on 16 GB) | Docker Desktop (needs WSL 2) |

Then, in the repo:

```bash
python scripts/doctor.py
pre-commit install
docker run hello-world
```

## 3. GitHub (Moustafa: the repo lives on Moustafa's personal account, ADR 0008 #2)

```bash
gh auth login
gh auth refresh -s project
gh repo create USER/arabizi-keyboard --public --source . --remote origin --description "Local, private Arabizi to Arabic keyboard for macOS"
git add -A
git commit -m "chore(S0): repository scaffold"
git push -u origin main
```

`USER` is Moustafa's GitHub username (`gh api user -q .login`). Then run:

```bash
python scripts/github/bootstrap.py all --repo USER/arabizi-keyboard --dry-run
python scripts/github/bootstrap.py settings --repo USER/arabizi-keyboard
python scripts/github/bootstrap.py labels --repo USER/arabizi-keyboard
python scripts/github/bootstrap.py milestones --repo USER/arabizi-keyboard
gh project create --owner "@me" --title "Arabizi Keyboard"
python scripts/github/bootstrap.py issues --repo USER/arabizi-keyboard --project "Arabizi Keyboard"
python scripts/github/bootstrap.py protect --repo USER/arabizi-keyboard
```

- **Invite teammates** as collaborators (they must accept the email invite):
  `gh api -X PUT repos/USER/arabizi-keyboard/collaborators/OMAR_USERNAME -f permission=push` (same for Mohamad). Then fill `scripts/github/team.json` and the CODEOWNERS handles in a PR.
- **Only Moustafa can change settings** on a personal repo. Collaborators can push branches, open and review PRs, and manage issues, but rulesets, security settings and Actions secrets go through Moustafa.
- **Order matters:** push the scaffold *before* `protect`, or the first push itself will be blocked.
- **Board columns:** in the project's *Status* field, set the options to Backlog / This sprint / In progress / In review / Done (2 minutes in the web UI). Add a *Board* view grouped by Status and a *Table* view grouped by milestone.
- **Required status checks** (`lint`, `build-test`, `codeql`, `eval-smoke`) do not exist until P5. Re-run `protect --checks lint,build-test,...` once they have run at least once.
- All bootstrap commands are idempotent: re-running skips labels, milestones and issues that already exist.

## 4. Gate: tick these on the `[P0] Gate` issue, with evidence links

- [ ] **Each member's test PR reviewed and merged.** Suggested: each person opens a PR adding their row to the README team table (or their toy package from the learning ramp).
- [ ] **Direct push to `main` is rejected.** Run `git push origin HEAD:main` from a commit on a branch, and paste the rejection message into the gate issue.
- [ ] **Secrets are blocked.**
  - Local: commit a dummy key on a scratch branch, and `pre-commit`/gitleaks must refuse the commit.
  - Remote: confirm *Settings → Code security → Push protection* is **Enabled** and screenshot it.
  - Note: GitHub ignores well-known documentation examples such as AWS's published example access key, so a "fake key" push test can pass silently. Do not treat that as proof that push protection is off. (Local gitleaks *does* flag that example key, which is a quick way to see the local guard working.)
- [ ] **Scope recorded.** ADR 0001 (team answers) and ADR 0010 (Phase 1 pivot, approved by Dr. Mohanna) are merged.
- [ ] **Tools work.** Every member's `python scripts/doctor.py` passes on their OS (paste the output in the gate issue). macOS members: `swift --version`, `xcodebuild -version`. Everyone: `docker run hello-world`.
- [ ] **Cloud GPU works.** Every member can start a GPU notebook on Kaggle (phone-verified account) or Colab, for P4 fine-tuning.

## 5. Weekly rhythm (from Week 1)

- **Monday:** sprint planning. Move issues for the week into *This sprint*; each one has exactly one assignee.
- **Daily:** 10-minute async stand-up in the group chat: yesterday / today / blocked.
- **Friday:** demo + retro. Write 3 lines in a pinned Discussion thread "Sprint Wn retro" (went well / went badly / change). This is the cheapest evidence of a "meaningful sprint" for the bonus.
