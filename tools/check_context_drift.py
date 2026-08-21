#!/usr/bin/env python3
"""
Mechanical staleness pre-check for the hoopsRN context dictionary.

Reads every dictionary entry's `**Scope:**` / `**Verified:**` header, diffs
its owned paths against HEAD, and reports which entries are stale --
*before* an agent rereads anything. Run this first; feed its output to
`context/prompts/refresh-context-dictionary.md` and only reread/restamp the
entries it names as stale or unresolvable. Entries it reports as current
should not be touched.

Usage:
    python3 tools/check_context_drift.py
"""
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CONTEXT_DIR = REPO_ROOT / "context"

# Scope declarations wrap across multiple lines in several entries (long
# path lists), so this captures everything between "**Scope:**" and the
# following "**Verified:**" line rather than just the first line.
HEADER_RE = re.compile(
    r"^\*\*Scope:\*\*\s*(.*?)\n\*\*Verified:\*\*\s*(\d{4}-\d{2}-\d{2})\s*@\s*(\S+)",
    re.MULTILINE | re.DOTALL,
)
SHA_RE = re.compile(r"^[0-9a-f]{7,40}$")


def run_git(*args):
    result = subprocess.run(
        ["git", *args], cwd=REPO_ROOT, capture_output=True, text=True
    )
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def parse_scope(raw):
    raw = raw.strip()
    if raw in ("—", "-", ""):
        return None
    paths = re.findall(r"`([^`]+)`", raw)
    return paths


def entry_files():
    # INDEX.md carries no per-entry Scope/Verified stamp by design -- it's the
    # routing table, refreshed by hand at the end of a pass, not diffed.
    files = sorted(p for p in CONTEXT_DIR.glob("*.md") if p.name != "INDEX.md")
    files += sorted((CONTEXT_DIR / "database").glob("*.md"))
    return files


def owned(path, scope_paths):
    for s in scope_paths:
        s_norm = s.rstrip("/")
        if path == s_norm or path.startswith(s_norm + "/"):
            return True
    return False


def main():
    entries = []
    for f in entry_files():
        text = f.read_text()
        header_match = HEADER_RE.search(text)
        if not header_match:
            print(f"WARN  {f.relative_to(REPO_ROOT)}: missing Scope/Verified header, skipping")
            continue
        scope_raw, date, ref = header_match.groups()
        scope_paths = parse_scope(scope_raw)
        entries.append({
            "file": str(f.relative_to(REPO_ROOT)),
            "scope": scope_paths,
            "date": date,
            "ref": ref,
        })

    code, head, _ = run_git("rev-parse", "--short", "HEAD")
    if code != 0:
        print("Not a git repo, or HEAD unresolvable.", file=sys.stderr)
        sys.exit(1)

    _, dirty, _ = run_git("status", "--porcelain")
    dirty_note = (
        f"  ({len(dirty.splitlines())} uncommitted change(s) in the working tree "
        f"-- included in this check)"
        if dirty else "  (working tree clean)"
    )
    print(f"HEAD @ {head}{dirty_note}\n")

    stale, current, always_revisit, unresolvable = [], [], [], []
    resolved_shas = []

    for e in entries:
        if e["scope"] is None:
            always_revisit.append(e)
            continue

        rc, resolved, _ = run_git("rev-parse", "--short", e["ref"])
        if rc != 0:
            unresolvable.append(e)
            continue

        if not SHA_RE.match(e["ref"]):
            e["ref_is_mutable_name"] = True

        resolved_shas.append((resolved, e["date"]))

        # Deliberately `git diff <ref> -- <scope>` with NO second ref: that
        # compares the verified commit against the **working tree**, not just
        # HEAD, so uncommitted and staged-but-uncommitted work in scope still
        # marks an entry stale. A dictionary that only distrusts itself after
        # a commit lands is trusting itself during exactly the window real
        # work happens in.
        diff_args = ["diff", "--name-only", resolved, "--"] + e["scope"]
        rc, out, _ = run_git(*diff_args)
        changed = [l for l in out.splitlines() if l]
        if changed:
            e["changed"] = changed
            stale.append(e)
        else:
            current.append(e)

    print("=== STALE (scope touched since Verified -- reread these) ===")
    if not stale:
        print("  none")
    for e in stale:
        flag = "  [stamp is a branch/tag name, not a sha]" if e.get("ref_is_mutable_name") else ""
        print(f"  {e['file']}  (verified {e['date']} @ {e['ref']}){flag}")
        for c in e["changed"]:
            print(f"      {c}")

    print("\n=== UNRESOLVABLE (ref doesn't resolve -- reread in full) ===")
    if not unresolvable:
        print("  none")
    for e in unresolvable:
        print(f"  {e['file']}  (ref '{e['ref']}' does not resolve)")

    print("\n=== ALWAYS REVISIT (no scope to diff -- check by hand every pass) ===")
    for e in always_revisit:
        print(f"  {e['file']}")

    print("\n=== CURRENT (leave untouched, do not restamp) ===")
    if not current:
        print("  none")
    for e in current:
        flag = "  [stamp is a branch/tag name -- fine today, fragile if that ref moves]" if e.get("ref_is_mutable_name") else ""
        print(f"  {e['file']}{flag}")

    if resolved_shas:
        oldest_sha = min(resolved_shas, key=lambda t: t[1])[0]
        # Same reasoning as above: no second ref, so this includes whatever
        # is sitting uncommitted in the working tree right now.
        rc, out, _ = run_git("diff", "--name-only", oldest_sha)
        all_changed = [l for l in out.splitlines() if l]
        all_scoped_paths = [p for e in entries if e["scope"] for p in e["scope"]]
        # Drop paths that no longer exist on disk -- a file renamed or deleted
        # since the oldest verification point shows up in the diff but isn't
        # a scope gap anyone needs to fix, just historical churn.
        unowned = [
            f for f in all_changed
            if not owned(f, all_scoped_paths)
            and not f.startswith("context/")
            and (REPO_ROOT / f).exists()
        ]
        print(f"\n=== UNOWNED CHANGES (since oldest verified point {oldest_sha}, "
              f"matches no entry's Scope) ===")
        if not unowned:
            print("  none")
        for f in unowned:
            print(f"  {f}")


if __name__ == "__main__":
    main()
