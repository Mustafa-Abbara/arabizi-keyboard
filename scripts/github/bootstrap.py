"""Set up the GitHub side of the project from docs/ROADMAP.md.

Subcommands (all idempotent; add --dry-run to print actions without calling GitHub):
  settings    merge rules, Issues/Projects/Discussions, secret scanning + push protection,
              Dependabot alerts/security updates, private vulnerability reporting
  labels      stage:P0..P7, type:*, owner:*, security, regression, ...
  milestones  W1..W10 (due on each project week's Friday, ASSUMPTION A1)
  issues      one issue per numbered roadmap step + one gate checklist per stage
  protect     ruleset on the default branch (PR + 1 review, linear history, no force-push)
  all         settings, labels, milestones, issues, protect

Examples:
  python scripts/github/bootstrap.py all --repo ORG/arabizi-keyboard --dry-run
  python scripts/github/bootstrap.py issues --repo ORG/arabizi-keyboard --project "Arabizi Keyboard"
  python scripts/github/bootstrap.py protect --repo ORG/arabizi-keyboard --checks lint,build-test

Requires the GitHub CLI, logged in with `gh auth login` (add the `project` scope for --project:
`gh auth refresh -s project`).
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ROADMAP = ROOT / "docs" / "ROADMAP.md"
TEAM_FILE = Path(__file__).with_name("team.json")

WEEK1_FRIDAY = date(2026, 10, 16)  # ASSUMPTION A1: Project Week 1 = Mon 12 – Sun 18 Oct 2026
N_WEEKS = 10
N_STAGES = 8  # Phase 1 stages P0..P7 (ADR 0010)
OWNERS = ("omar", "mohamad", "moustafa")
RULESET_NAME = "protect-main"

RETRY_DELAYS_S = (2, 5, 15, 30)
CREATE_PAUSE_S = 1.0  # GitHub asks for about 1 s between content-creating requests
TRANSIENT_ERRORS = ("dial tcp", "read tcp", "wsarecv", "connectex", "tls handshake timeout",
                    "connection reset", "i/o timeout",
                    "unexpected eof", "http 502", "http 503", "http 504", "secondary rate limit")

LABELS: dict[str, tuple[str, str]] = {
    **{f"stage:P{i}": ("c5def5", f"Phase 1 roadmap stage P{i}") for i in range(N_STAGES)},
    "type:task": ("1d76db", "Planned roadmap work"),
    "type:gate": ("fbca04", "Stage gate checklist: must pass before dependants merge"),
    "type:bug": ("d73a4a", "Something behaves wrongly"),
    "type:eval": ("5319e7", "Evaluation, benchmarks, metrics"),
    "type:docs": ("0075ca", "Documentation"),
    "security": ("b60205", "Security-relevant change or finding"),
    "security-review": ("b60205", "Required on PRs that add entitlements or permissions"),
    "regression": ("e99695", "Fixed bug with a regression test"),
    "testset-change": ("f9d0c4", "Touches the frozen test set: needs 2 approvals"),
    **{f"owner:{o}": ("ededed", f"Accountable: {o.capitalize()}") for o in OWNERS},
}

STAGE_HEADING = re.compile(r"^### (P\d+) — (.+)$")
TOP_LEVEL_STEP = re.compile(r"^\d+\. (.*)$")
BOLD_OWNER = re.compile(r"^\*\*\(([^)]*)\)")
NAME = re.compile(r"\b(omar|mohamad|moustafa|all)\b", re.IGNORECASE)
SECTION_END = ("**Deliverables", "**Gate", "**ASSUMPTION", "**Rubric", "---", "### ", "## ")


@dataclass
class Issue:
    title: str
    body: str
    labels: list[str]
    milestone: str
    owners: list[str]


# --------------------------------------------------------------------------- gh helpers

class GhError(RuntimeError):
    def __init__(self, message: str, transient: bool):
        super().__init__(message)
        self.transient = transient


def gh(args: list[str], dry_run: bool, stdin: str | None = None, read_only: bool = False,
       retry: bool = True) -> str:
    """Run `gh`. In dry-run, writes are printed and skipped; reads return an empty result.

    Network errors are retried with backoff when `retry` is true. Pass retry=False for
    non-idempotent calls (issue creation) and handle the retry at the call site.
    """
    if dry_run:
        if not read_only:
            print("  [dry-run] gh " + " ".join(args[:6]) + (" ..." if len(args) > 6 else ""))
        return ""
    for delay in (*RETRY_DELAYS_S, None):
        result = subprocess.run(["gh", *args], input=stdin, capture_output=True, text=True, encoding="utf-8")
        if result.returncode == 0:
            return result.stdout
        error = result.stderr.strip()
        transient = any(marker in error.lower() for marker in TRANSIENT_ERRORS)
        if not (retry and transient and delay is not None):
            raise GhError(f"gh {' '.join(args[:4])} failed: {error}", transient)
        print(f"  network error, retrying in {delay}s", file=sys.stderr)
        time.sleep(delay)
    raise AssertionError("unreachable")


def gh_json(args: list[str], dry_run: bool, default):
    out = gh(args, dry_run, read_only=True)
    return json.loads(out) if out.strip() else default


# --------------------------------------------------------------------------- roadmap parsing

def owners_in(text: str) -> list[str]:
    found = [m.lower() for m in NAME.findall(text)]
    if "all" in found:
        return list(OWNERS)
    return list(dict.fromkeys(found))  # unique, in order of appearance


def clean(text: str) -> str:
    return re.sub(r"\*\*|`", "", text).strip()


def short_title(text: str, limit: int = 80) -> str:
    text = clean(text)
    colon = re.search(r":(\s|$)", text)  # a label colon, not one inside `stage:P5`
    if colon and colon.start() <= 90:
        text = text[: colon.start()]
    elif ". " in text:
        text = text.split(". ", 1)[0]
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def stage_plan(lines: list[str]) -> dict[str, tuple[str, list[str]]]:
    """Read the overview table: stage -> (milestone 'Wn' = last week of the stage, lead owners)."""
    plan = {}
    for line in lines:
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) == 5 and re.fullmatch(r"P\d+", cells[0]):
            weeks = [int(w) for w in re.findall(r"W(\d+)", cells[2])]
            plan[cells[0]] = (f"W{max(weeks)}", owners_in(cells[3]))
    return plan


def section_until_end(lines: list[str], start: int) -> tuple[list[str], int]:
    block, i = [], start
    while i < len(lines) and not lines[i].startswith(SECTION_END):
        block.append(lines[i])
        i += 1
    return block, i


def parse_roadmap(path: Path = ROADMAP) -> list[Issue]:
    lines = path.read_text(encoding="utf-8").splitlines()
    plan = stage_plan(lines)
    issues: list[Issue] = []

    # Learning ramp (roadmap §2) runs in W1 alongside P0.
    ramp_start = next(i for i, l in enumerate(lines) if l.startswith("## 2. Learning ramp"))
    ramp, _ = section_until_end(lines, ramp_start + 1)
    issues.append(Issue("[P0] Learning ramp: Swift, testing, IME, fine-tuning and eval concepts",
                        "\n".join(ramp).strip() + footer("§2 Learning ramp"),
                        ["stage:P0", "type:task"], "W1", list(OWNERS)))

    i = 0
    while i < len(lines):
        heading = STAGE_HEADING.match(lines[i])
        if not heading:
            i += 1
            continue
        stage, stage_name = heading.groups()
        milestone, lead = plan[stage]
        i += 1
        header_owners, steps, gate_body, deliverables = lead, [], [], ""
        while i < len(lines) and not STAGE_HEADING.match(lines[i]) and not lines[i].startswith("## "):
            line = lines[i]
            if line.startswith("**Steps"):
                header_owners = owners_in(line)[:1] or lead
                block, i = section_until_end(lines, i + 1)
                steps = split_steps(block)
                continue
            if line.startswith("**Deliverables"):
                deliverables = line
            if line.startswith("**Gate"):
                gate_body, i = section_until_end(lines, i + 1)
                continue
            i += 1

        for n, step in enumerate(steps, 1):
            first = TOP_LEVEL_STEP.match(step[0]).group(1)
            owner_match = BOLD_OWNER.match(first)
            owners = owners_in(owner_match.group(1)) if owner_match else header_owners
            text = first[owner_match.end():] if owner_match else first
            issues.append(Issue(f"[{stage}] {short_title(text)}",
                                "\n".join(step).strip() + footer(f"{stage} step {n}"),
                                [f"stage:{stage}", "type:task"], milestone, owners))

        gate = "\n".join([deliverables, "", "**Gate**", *gate_body]).strip()
        issues.append(Issue(f"[{stage}] Gate: {stage_name}",
                            gate + footer(f"{stage} gate") + "\n\nClose only when every box is ticked with linked evidence.",
                            [f"stage:{stage}", "type:gate"], milestone, lead))
    return issues


def split_steps(block: list[str]) -> list[list[str]]:
    steps: list[list[str]] = []
    for line in block:
        if TOP_LEVEL_STEP.match(line):
            steps.append([line])
        elif steps:
            steps[-1].append(line)
    return steps


def footer(where: str) -> str:
    return f"\n\n---\n_Source: `docs/ROADMAP.md`, {where}._"


# --------------------------------------------------------------------------- commands

def cmd_settings(repo: str, dry: bool) -> None:
    print("Repository settings")
    gh(["repo", "edit", repo, "--enable-issues", "--enable-projects", "--enable-discussions",
        "--enable-squash-merge", "--enable-merge-commit=false", "--enable-rebase-merge=false",
        "--delete-branch-on-merge"], dry)
    security = {"security_and_analysis": {"secret_scanning": {"status": "enabled"},
                                          "secret_scanning_push_protection": {"status": "enabled"}}}
    gh(["api", "-X", "PATCH", f"repos/{repo}", "--input", "-"], dry, stdin=json.dumps(security))
    for endpoint in ("vulnerability-alerts", "automated-security-fixes", "private-vulnerability-reporting"):
        gh(["api", "-X", "PUT", f"repos/{repo}/{endpoint}"], dry)


def cmd_labels(repo: str, dry: bool) -> None:
    print(f"Labels ({len(LABELS)})")
    for name, (color, desc) in LABELS.items():
        gh(["label", "create", name, "--repo", repo, "--color", color, "--description", desc, "--force"], dry)


def cmd_milestones(repo: str, dry: bool) -> None:
    print(f"Milestones W1..W{N_WEEKS}")
    existing = {m["title"] for m in gh_json(["api", f"repos/{repo}/milestones?state=all&per_page=100"], dry, [])}
    for week in range(1, N_WEEKS + 1):
        title = f"W{week}"
        if title in existing:
            continue
        friday = WEEK1_FRIDAY + timedelta(weeks=week - 1)
        monday = friday - timedelta(days=4)
        gh(["api", "-X", "POST", f"repos/{repo}/milestones",
            "-f", f"title={title}",
            "-f", f"description=Project week {week}: {monday:%d %b} – {friday + timedelta(days=2):%d %b} (ASSUMPTION A1)",
            "-f", f"due_on={friday.isoformat()}T23:59:59Z"], dry)


def issue_titles(repo: str, dry: bool) -> set[str]:
    return {i["title"] for i in gh_json(
        ["issue", "list", "--repo", repo, "--state", "all", "--limit", "1000", "--json", "title"], dry, [])}


def create_issue(repo: str, dry: bool, args: list[str], issue: Issue) -> None:
    """Creating an issue is not idempotent: after a network error, retry only if it did not land."""
    for delay in (*RETRY_DELAYS_S, None):
        try:
            gh(args, dry, stdin=issue.body, retry=False)
            return
        except GhError as exc:
            if not exc.transient or delay is None:
                raise
            print(f"  network error, checking and retrying in {delay}s", file=sys.stderr)
            time.sleep(delay)
            if issue.title in issue_titles(repo, dry):
                return


def cmd_issues(repo: str, dry: bool, project: str | None) -> None:
    team = {k: v for k, v in json.loads(TEAM_FILE.read_text(encoding="utf-8")).items() if k in OWNERS}
    issues = parse_roadmap()
    existing = issue_titles(repo, dry)
    print(f"Issues: {len(issues)} parsed from roadmap, {len(existing)} already on GitHub")
    for issue in issues:
        if issue.title in existing:
            continue
        print(f"  {issue.milestone:>3}  {','.join(issue.owners):<24} {issue.title}")
        args = ["issue", "create", "--repo", repo, "--title", issue.title, "--body-file", "-",
                "--milestone", issue.milestone]
        for label in issue.labels + [f"owner:{o}" for o in issue.owners]:
            args += ["--label", label]
        for owner in issue.owners:
            if team.get(owner):
                args += ["--assignee", team[owner]]
        if project:
            args += ["--project", project]
        create_issue(repo, dry, args, issue)
        if not dry:
            time.sleep(CREATE_PAUSE_S)


def cmd_protect(repo: str, dry: bool, checks: list[str]) -> None:
    print(f"Ruleset '{RULESET_NAME}' on the default branch" + (f" (required checks: {checks})" if checks else ""))
    rules: list[dict] = [
        {"type": "deletion"},
        {"type": "non_fast_forward"},
        {"type": "required_linear_history"},
        {"type": "pull_request", "parameters": {
            "required_approving_review_count": 1,
            "dismiss_stale_reviews_on_push": True,
            "require_code_owner_review": False,
            "require_last_push_approval": False,
            "required_review_thread_resolution": True}},
    ]
    if checks:
        rules.append({"type": "required_status_checks", "parameters": {
            "strict_required_status_checks_policy": True,
            "required_status_checks": [{"context": c} for c in checks]}})
    ruleset = {"name": RULESET_NAME, "target": "branch", "enforcement": "active",
               "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
               "bypass_actors": [], "rules": rules}
    existing = [r for r in gh_json(["api", f"repos/{repo}/rulesets"], dry, []) if r["name"] == RULESET_NAME]
    if existing:
        gh(["api", "-X", "PUT", f"repos/{repo}/rulesets/{existing[0]['id']}", "--input", "-"], dry,
           stdin=json.dumps(ruleset))
    else:
        gh(["api", "-X", "POST", f"repos/{repo}/rulesets", "--input", "-"], dry, stdin=json.dumps(ruleset))


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")  # Windows consoles default to cp1252
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["settings", "labels", "milestones", "issues", "protect", "all"])
    parser.add_argument("--repo", required=True, help="OWNER/NAME")
    parser.add_argument("--dry-run", action="store_true", help="print actions without calling GitHub")
    parser.add_argument("--project", help="title of a GitHub Project to add new issues to")
    parser.add_argument("--checks", default="", help="comma-separated status checks to require (P5+)")
    args = parser.parse_args()

    steps = {
        "settings": lambda: cmd_settings(args.repo, args.dry_run),
        "labels": lambda: cmd_labels(args.repo, args.dry_run),
        "milestones": lambda: cmd_milestones(args.repo, args.dry_run),
        "issues": lambda: cmd_issues(args.repo, args.dry_run, args.project),
        "protect": lambda: cmd_protect(args.repo, args.dry_run, [c for c in args.checks.split(",") if c]),
    }
    try:
        for name in (steps if args.command == "all" else [args.command]):
            steps[name]()
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
