#!/usr/bin/env python3
"""Automated version bumps for this overlay, see .github/autobump/README.md.

Subcommands:
  check    find packages with a newer upstream version (needs portage, nvchecker)
  bump     copy the latest ebuild to a new version and regenerate the Manifest
  drop     remove an old ebuild and regenerate the Manifest
  prompt   render the Claude prompt for a bump
  publish  push branches and open PRs/issues for the results of a run
"""

import argparse
import functools
import json
import os
import shutil
import subprocess
import sys
import tomllib
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / ".github" / "autobump"
CONFIG = HERE / "nvchecker.toml"
REPO = os.environ.get("GITHUB_REPOSITORY", "cy1der/gentoo-overlay")
MODES = ("pr", "ai", "issue")
CLAUDE_TRAILER = "Co-Authored-By: Claude <noreply@anthropic.com>"


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def run(*cmd, cwd=ROOT, capture=False):
    return subprocess.run(
        cmd, cwd=cwd, check=True, text=True, capture_output=capture
    ).stdout


# --- ebuilds -----------------------------------------------------------------


def ebuilds(cp):
    """Return [(pvr, path)] for the non-live ebuilds of cp, oldest first."""
    from portage.versions import catpkgsplit, vercmp

    cat = cp.split("/")[0]
    found = []
    for path in (ROOT / cp).glob("*.ebuild"):
        _, _, ver, rev = catpkgsplit(f"{cat}/{path.stem}")
        if "9999" in ver:
            continue
        found.append((ver if rev == "r0" else f"{ver}-{rev}", path))
    if not found:
        sys.exit(f"{cp}: no ebuilds found")
    return sorted(found, key=functools.cmp_to_key(lambda a, b: vercmp(a[0], b[0])))


def latest(cp):
    return ebuilds(cp)[-1]


def manifest(cp):
    run("pkgdev", "manifest", cwd=ROOT / cp)


# --- GitHub API ----------------------------------------------------------------


def api(method, path, data=None):
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    req = urllib.request.Request(
        f"https://api.github.com{path}",
        method=method,
        data=json.dumps(data).encode() if data is not None else None,
        headers={
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            **({"Authorization": f"Bearer {token}"} if token else {}),
        },
    )
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read()
            return json.loads(body) if body else None
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise RuntimeError(f"{method} {path}: {e.code} {e.read().decode()}") from e


def q(s):
    return urllib.parse.quote(s, safe="")


def branch_name(cp, ver):
    return f"autobump/{cp}-{ver}"


def issue_title(cp, ver):
    return f"{cp}: {ver} available"


def already_handled(cp, ver):
    """True if a branch, PR (in any state) or issue already exists for cp-ver."""
    branch = branch_name(cp, ver)
    owner = REPO.split("/")[0]
    if api("GET", f"/repos/{REPO}/branches/{q(branch)}"):
        return True
    if api("GET", f"/repos/{REPO}/pulls?state=all&head={q(owner + ':' + branch)}"):
        return True
    query = f'repo:{REPO} is:issue in:title "{issue_title(cp, ver)}"'
    found = api("GET", f"/search/issues?q={q(query)}")
    return any(i["title"] == issue_title(cp, ver) for i in found["items"])


# --- check -------------------------------------------------------------------


def nvchecker_results(only):
    exe = shutil.which("nvchecker") or str(Path(sys.executable).parent / "nvchecker")
    cmd = [exe, "-c", str(CONFIG), "--logger", "json"]
    if only:
        cmd += ["-e", only]
    proc = subprocess.run(cmd, cwd=HERE, text=True, capture_output=True)
    results = {}
    for line in proc.stdout.splitlines() + proc.stderr.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "version" in event and event.get("name"):
            results[event["name"]] = event
        elif event.get("level") in ("error", "warning"):
            log(f"nvchecker: {event.get('name', '?')}: {event.get('event')} {event.get('error', '')}")
    return results


def cmd_check(args):
    from portage.versions import vercmp, ververify

    config = tomllib.loads(CONFIG.read_text())
    plan = {"bump": [], "issue": []}
    for cp, event in sorted(nvchecker_results(args.only).items()):
        entry = config.get(cp, {})
        old, _ = latest(cp)
        new = event["version"]
        if not ververify(new):
            log(f"{cp}: upstream version {new!r} is not a valid Gentoo version, opening an issue")
            mode = "issue"
        elif vercmp(new, old.split("-r")[0]) <= 0:
            continue
        else:
            mode = args.force_mode or entry.get("x_mode", "issue")
        if mode not in MODES:
            sys.exit(f"{cp}: unknown x_mode {mode!r}")
        if already_handled(cp, new):
            log(f"{cp}: {new} already has a branch, PR or issue, skipping")
            continue
        item = {
            "atom": cp,
            "old": old,
            "new": new,
            "mode": mode,
            "drop_old": bool(entry.get("x_drop_old", False)),
            "url": event.get("url") or "",
            "slug": cp.replace("/", "_"),
            "key": f"{cp.replace('/', '_')}-{new}",
        }
        log(f"{cp}: {old} -> {new} ({mode})")
        plan["bump" if mode != "issue" else "issue"].append(item)
    out = json.dumps(plan, indent=2)
    if args.output:
        Path(args.output).write_text(out)
    print(out)


# --- bump / drop ---------------------------------------------------------------


def cmd_bump(args):
    _, src = latest(args.atom)
    dst = src.with_name(f"{args.atom.split('/')[1]}-{args.new}.ebuild")
    if dst.exists():
        sys.exit(f"{dst.name} already exists")
    shutil.copy2(src, dst)
    log(f"{src.name} -> {dst.name}")
    manifest(args.atom)


def cmd_drop(args):
    path = dict(ebuilds(args.atom)).get(args.old)
    if not path:
        sys.exit(f"{args.atom}: no ebuild for {args.old}")
    run("git", "rm", "-q", str(path.relative_to(ROOT)))
    manifest(args.atom)


# --- prompt --------------------------------------------------------------------


def cmd_prompt(args):
    text = (HERE / "prompt.md").read_text()
    failure = Path(args.log).read_text()[-12000:] if args.log else ""
    for key, value in {
        "ATOM": args.atom,
        "OLD": args.old,
        "NEW": args.new,
        "URL": args.url or "(none)",
        "FAILURE": failure or "(not built yet)",
    }.items():
        text = text.replace("{{" + key + "}}", value)
    print(text)


# --- publish -------------------------------------------------------------------


def tail(path, lines=60):
    if not path.exists():
        return ""
    return "\n".join(path.read_text(errors="replace").splitlines()[-lines:])


def details(summary, body, lang=""):
    if not body.strip():
        return ""
    return f"<details><summary>{summary}</summary>\n\n```{lang}\n{body}\n```\n\n</details>\n"


def open_issue(item, body, labels):
    issue = api(
        "POST",
        f"/repos/{REPO}/issues",
        {"title": issue_title(item["atom"], item["new"]), "body": body, "labels": labels},
    )
    log(f"{item['atom']}: opened issue {issue['html_url']}")


def close_superseded(cp, branch):
    for pr in api("GET", f"/repos/{REPO}/pulls?state=open&per_page=100") or []:
        ref = pr["head"]["ref"]
        if ref.startswith(f"autobump/{cp}-") and ref != branch:
            api("POST", f"/repos/{REPO}/issues/{pr['number']}/comments", {"body": f"Superseded by `{branch}`."})
            api("PATCH", f"/repos/{REPO}/pulls/{pr['number']}", {"state": "closed"})
            api("DELETE", f"/repos/{REPO}/git/refs/heads/{q(ref)}")
            log(f"{cp}: closed superseded PR #{pr['number']}")


def publish_result(result_dir):
    res = json.loads((result_dir / "result.json").read_text())
    cp, old, new, status = res["atom"], res["old"], res["new"], res["status"]
    release = f"Upstream release: {res['url']}\n\n" if res["url"] else ""
    ai_summary = (result_dir / "ai-summary.md").read_text() if (result_dir / "ai-summary.md").exists() else ""
    pkgcheck = tail(result_dir / "pkgcheck.txt", 40)
    build = tail(result_dir / "build.log", 60)

    if status == "failed":
        body = (
            f"Automation could not bump `{cp}` from {old} to {new} (mode `{res['mode']}`).\n\n"
            + release
            + (f"## Claude's notes\n\n{ai_summary}\n\n" if ai_summary else "")
            + details("pkgcheck", pkgcheck)
            + details("Build log (tail)", build)
            + "\nComment `@claude <instructions>` to have Claude try again, or bump it by hand.\n"
        )
        open_issue(res, body, ["autobump", "needs-human"])
        return

    branch = branch_name(cp, new)
    run("git", "checkout", "-q", "-B", branch, "origin/main")
    message = f"chore({cp}): latest version"
    if status == "ai":
        message += f"\n\n{CLAUDE_TRAILER}"
    run("git", "apply", "--index", str(result_dir / "bump.patch"))
    run("git", "commit", "-q", "-m", message)
    drop = result_dir / "drop.patch"
    if drop.exists() and drop.stat().st_size:
        run("git", "apply", "--index", str(drop))
        run("git", "commit", "-q", "-m", f"chore({cp}): drop {old}")
    run("git", "push", "-q", "--force", "origin", branch)

    if status == "ai":
        intro = (
            "Claude made changes beyond a plain version bump. **Review the diff carefully** "
            "before marking this ready.\n\n"
            f"## Claude's summary\n\n{ai_summary or '(no summary written)'}\n\n"
        )
    else:
        intro = "Mechanical bump: the ebuild was copied unchanged and the Manifest regenerated.\n\n"
    body = (
        f"Bumps `{cp}` from {old} to {new}.\n\n"
        + release
        + intro
        + "pkgcheck passed and `emerge` built the new version in a `gentoo/stage3` container.\n\n"
        + details("pkgcheck", pkgcheck)
        + details("Build log (tail)", build)
    )
    pr = api(
        "POST",
        f"/repos/{REPO}/pulls",
        {
            "title": f"chore({cp}): latest version ({new})",
            "head": branch,
            "base": "main",
            "body": body,
            "draft": status == "ai",
        },
    )
    labels = ["autobump"] + (["ai-assisted"] if status == "ai" else [])
    api("POST", f"/repos/{REPO}/issues/{pr['number']}/labels", {"labels": labels})
    log(f"{cp}: opened PR {pr['html_url']}")
    close_superseded(cp, branch)


def cmd_publish(args):
    failures = 0
    plan = json.loads(Path(args.plan).read_text()) if args.plan else {"issue": []}
    for item in plan["issue"]:
        body = (
            f"`{item['atom']}` {item['new']} is available (we have {item['old']}).\n\n"
            + (f"Upstream release: {item['url']}\n\n" if item["url"] else "")
            + "This package is set to `x_mode = \"issue\"` in `.github/autobump/nvchecker.toml`, "
            "so it needs a manual bump. Comment `@claude <instructions>` for help.\n"
        )
        try:
            open_issue(item, body, ["autobump"])
        except Exception as e:  # keep going so one failure doesn't hide the rest
            log(f"{item['atom']}: {e}")
            failures += 1
    # download-artifact nests each artifact in its own directory only when
    # there is more than one, so look at any depth
    results = sorted(Path(args.results).rglob("result.json")) if args.results else []
    if len(results) < len(plan.get("bump", [])):
        log(f"expected {len(plan['bump'])} bump result(s), found {len(results)}")
        failures += len(plan["bump"]) - len(results)
    for result in results:
        try:
            publish_result(result.parent)
        except Exception as e:
            log(f"{result.parent.name}: {e}")
            failures += 1
    if failures:
        sys.exit(f"{failures} item(s) failed to publish")


# --- main ----------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("check")
    p.add_argument("--only", help="only check this atom")
    p.add_argument("--force-mode", choices=MODES + ("",), help="override x_mode")
    p.add_argument("--output", help="also write the plan to this file")
    p.set_defaults(func=cmd_check)

    p = sub.add_parser("bump")
    p.add_argument("atom")
    p.add_argument("new")
    p.set_defaults(func=cmd_bump)

    p = sub.add_parser("drop")
    p.add_argument("atom")
    p.add_argument("old")
    p.set_defaults(func=cmd_drop)

    p = sub.add_parser("prompt")
    p.add_argument("atom")
    p.add_argument("old")
    p.add_argument("new")
    p.add_argument("--url")
    p.add_argument("--log", help="build log of the failed attempt")
    p.set_defaults(func=cmd_prompt)

    p = sub.add_parser("publish")
    p.add_argument("--plan", help="plan.json from check (for issue-mode items)")
    p.add_argument("--results", help="directory of per-package result dirs")
    p.set_defaults(func=cmd_publish)

    args = parser.parse_args()
    if getattr(args, "only", None) == "":
        args.only = None
    if getattr(args, "force_mode", None) == "":
        args.force_mode = None
    args.func(args)


if __name__ == "__main__":
    main()
