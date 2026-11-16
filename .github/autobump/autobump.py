#!/usr/bin/env python3
"""Automated version bumps for this overlay, see .github/autobump/README.md.

Subcommands:
  check    find packages with a newer upstream version (needs portage, nvchecker)
  lint     check nvchecker.toml against the packages in the overlay
  bump     copy the latest ebuild to a new version and regenerate the Manifest
  drop     remove an old ebuild and regenerate the Manifest
  prompt   render the Claude prompt for a bump
  transcript  summarize the output of a Claude round
  publish  push branches and open PRs/issues for the results of a run
  prune-caches  delete superseded Actions cache entries
"""

import argparse
import base64
import functools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / ".github" / "autobump"
CONFIG = HERE / "nvchecker.toml"
REPO = os.environ.get("GITHUB_REPOSITORY", "cy1der/gentoo-overlay")
# Assigned to every issue and PR, and asked to review the PRs
MAINTAINER = os.environ.get("AUTOBUMP_MAINTAINER") or REPO.split("/")[0]
MODES = ("pr", "ai", "issue")
CLAUDE_TRAILER = "Co-Authored-By: Claude <noreply@anthropic.com>"


class AutobumpError(Exception):
    """A problem with one package, which shouldn't stop the others."""


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
        raise AutobumpError("no ebuilds found")
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


def paginate(path, max_pages=0, key=None):
    """Yield the pages of a GitHub list endpoint, 100 items each.

    key: for endpoints that wrap the list in an object.
    """
    sep = "&" if "?" in path else "?"
    page = 1
    while True:
        items = api("GET", f"{path}{sep}per_page=100&page={page}") or []
        if key:
            items = items[key] if items else []
        yield items
        if len(items) < 100 or page == max_pages:
            return
        page += 1


def graphql(query, variables):
    req = urllib.request.Request(
        "https://api.github.com/graphql",
        data=json.dumps({"query": query, "variables": variables}).encode(),
        headers={"Authorization": f"Bearer {os.environ['GH_TOKEN']}"},
    )
    with urllib.request.urlopen(req) as resp:
        result = json.loads(resp.read())
    if result.get("errors"):
        raise RuntimeError(f"GraphQL: {result['errors']}")
    return result["data"]


def q(s):
    return urllib.parse.quote(s, safe="")


def branch_name(cp, ver):
    return f"autobump/{cp}-{ver}"


def issue_title(cp, ver):
    return f"{cp}: {ver} available"


@functools.cache
def autobump_issues():
    """Every issue labelled autobump, open or closed, listed once per run.

    Not with the search API: it allows only 30 requests a minute, and its
    results can lag behind. open_issue and close_issue keep this up to date.
    """
    return [
        issue
        for page in paginate(f"/repos/{REPO}/issues?labels=autobump&state=all")
        for issue in page
        if "pull_request" not in issue
    ]


def find_issues(cp, ver, state=""):
    """Issues titled for cp-ver, optionally only "open" or "closed" ones."""
    title = issue_title(cp, ver)
    return [i for i in autobump_issues() if i["title"] == title and state in ("", i["state"])]


def close_issue(issue, comment, reason):
    api("POST", f"/repos/{REPO}/issues/{issue['number']}/comments", {"body": comment})
    api("PATCH", f"/repos/{REPO}/issues/{issue['number']}", {"state": "closed", "state_reason": reason})
    issue["state"] = "closed"


def open_prs():
    return [pr for page in paginate(f"/repos/{REPO}/pulls?state=open") for pr in page]


def already_handled(cp, ver, check_issues=True):
    """True if a PR (in any state) or issue already exists for cp-ver."""
    branch = branch_name(cp, ver)
    owner = REPO.split("/")[0]
    if api("GET", f"/repos/{REPO}/pulls?state=all&head={q(owner + ':' + branch)}"):
        return True
    if check_issues and find_issues(cp, ver):
        return True
    # Left behind when opening its PR failed. Publish reuses the branch.
    if api("GET", f"/repos/{REPO}/branches/{q(branch)}"):
        log(f"{cp}: {branch} has no PR, bumping {ver} again")
    return False


# --- check -------------------------------------------------------------------


def nvchecker_results(only):
    exe = shutil.which("nvchecker") or str(Path(sys.executable).parent / "nvchecker")
    cmd = [exe, "-c", str(CONFIG), "--logger", "json"]
    if only:
        cmd += ["-e", only]
    with tempfile.NamedTemporaryFile("w", suffix=".toml") as keyfile:
        # nvchecker only reads tokens from a keyfile, not from $GITHUB_TOKEN.
        # Without one, GitHub allows 60 requests an hour per (shared) IP.
        token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
        if token:
            keyfile.write(f'[keys]\ngithub = "{token}"\n')
            keyfile.flush()
            cmd += ["-k", keyfile.name]
        proc = subprocess.run(cmd, cwd=HERE, text=True, capture_output=True)
    results, problems = {}, {}
    for line in proc.stdout.splitlines() + proc.stderr.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "version" in event and event.get("name"):
            results[event["name"]] = event
        elif event.get("level") in ("error", "warning"):
            message = f"{event.get('event')} {event.get('error', '')}".strip()
            log(f"nvchecker: {event.get('name', '?')}: {message}")
            # Errors can carry the whole HTTP response
            if len(message) > 160:
                message = message[:160] + "..."
            problems.setdefault(event.get("name", "?"), []).append(message)
    if problems and not results:
        sys.exit("nvchecker could not check any package")
    # Warnings about a package that still got a version don't matter
    failed = [f"{name}: nvchecker: {'; '.join(msgs)}" for name, msgs in sorted(problems.items()) if name not in results]
    return results, failed


def upstream_version(name, entry, listed):
    """The version nvchecker reports for a tag or release name, None if it is filtered out.

    Mirrors nvchecker's core.apply_list_options (only for sources that list
    several versions) and core.substitute_version.
    """
    if listed:
        for key, keep in (("include_regex", True), ("exclude_regex", False)):
            if entry.get(key) and bool(re.fullmatch(entry[key], name)) != keep:
                return None
        if name in entry.get("ignored", "").split():
            return None
    prefix = entry.get("prefix")
    if prefix and name.startswith(prefix):
        name = name[len(prefix):]
    if entry.get("from_pattern"):
        name = re.sub(entry["from_pattern"], entry["to_pattern"], name)
    return name


def releases_between(entry, old, new, max_pages=5):
    """GitHub releases of entry after old, up to new, newest first, as [{version, url}]."""
    from portage.versions import vercmp, ververify

    if entry.get("source") != "github" or not entry.get("github"):
        return []
    listed = bool(entry.get("use_max_tag") or entry.get("use_max_release"))
    found = {}
    for page in paginate(f"/repos/{entry['github']}/releases", max_pages):
        matched = newer = False
        for release in page:
            if release.get("draft"):
                continue
            # The latest release is never a prerelease, a tag can be
            if release.get("prerelease") and not (listed or entry.get("include_prereleases")):
                continue
            name = release.get("name") if entry.get("use_release_name") else release.get("tag_name")
            version = upstream_version(name or "", entry, listed)
            if not version or not ververify(version):
                continue
            matched = True
            if vercmp(version, old) > 0:
                newer = True
                if vercmp(version, new) <= 0:
                    found.setdefault(version, {"version": version, "url": release["html_url"]})
        # Newest first, so stop at a page with only older releases. Pages without
        # any (other components' releases) don't tell.
        if matched and not newer:
            break
    return sorted(found.values(), key=functools.cmp_to_key(lambda a, b: vercmp(b["version"], a["version"])))


def releases_for(cp, entry, old, new, url):
    """The releases a bump covers, falling back to the one nvchecker found."""
    try:
        releases = releases_between(entry, old, new)
    except Exception as e:  # the bump still works without them
        log(f"{cp}: could not list releases: {e}")
        releases = []
    # Only trust the range if it agrees with nvchecker about the newest one
    if not any(release["version"] == new for release in releases):
        releases = [{"version": new, "url": url}] if url else []
    return releases


def cmd_check(args):
    if args.regenerate and not args.only:
        sys.exit("--regenerate needs --only")
    # Problems with single packages. The others are still bumped, and publish
    # fails the run at the end so they get noticed.
    plan = {"bump": [], "issue": [], "errors": []}
    # Also catches what was pushed to main without CI
    lint_errors, lint_warnings = lint()
    for warning in lint_warnings:
        log(warning)
    if any(error.startswith(CONFIG.name) for error in lint_errors):
        sys.exit("\n".join(lint_errors))
    config = tomllib.loads(CONFIG.read_text())
    broken = {error.split(":")[0] for error in lint_errors}
    prs = open_prs()
    results, plan["errors"] = nvchecker_results(args.only)
    plan["errors"] += lint_errors
    for cp, event in sorted(results.items()):
        if cp in broken:
            continue
        try:
            item = plan_item(cp, event, config.get(cp, {}), args, prs)
        except Exception as e:
            log(f"{cp}: {e}")
            plan["errors"].append(f"{cp}: {e}")
            continue
        if item:
            plan["bump" if item["mode"] != "issue" else "issue"].append(item)
    out = json.dumps(plan, indent=2)
    if args.output:
        Path(args.output).write_text(out)
    print(out)


def plan_item(cp, event, entry, args, prs):
    """What to do about cp's upstream version, None if nothing."""
    from portage.versions import vercmp, ververify

    old, _ = latest(cp)
    new = event["version"]
    if not ververify(new):
        log(f"{cp}: upstream version {new!r} is not a valid Gentoo version, opening an issue")
        mode = "issue"
    elif vercmp(new, old.split("-r")[0]) <= 0:
        return None
    else:
        mode = args.force_mode or entry.get("x_mode", "issue")
    if mode not in MODES:
        raise AutobumpError(f"unknown x_mode {mode!r}")
    if not args.regenerate and already_handled(cp, new, check_issues=not args.retry):
        log(f"{cp}: {new} already has a PR or issue, skipping")
        return None
    item = {
        "atom": cp,
        "old": old,
        "new": new,
        "mode": mode,
        "drop_old": bool(entry.get("x_drop_old", True)),
        "url": event.get("url") or "",
        # For the changelog: every release since the version we have
        "releases": releases_for(cp, entry, old.split("-r")[0], new, event.get("url"))
        if ververify(new)
        else [],
        "slug": cp.replace("/", "_"),
        "key": f"{cp.replace('/', '_')}-{new}",
        # An open PR for an older version: build on its branch so fixes
        # made there (by Claude or by hand) carry over
        "base": "",
        "base_pr": 0,
        "base_ai": False,
    }
    for pr in prs:
        head_repo = (pr["head"]["repo"] or {}).get("full_name")  # None for deleted forks
        ref = pr["head"]["ref"]
        # Regenerating starts over from main instead of this version's own PR
        if ref.startswith(f"autobump/{cp}-") and ref != branch_name(cp, new) and head_repo == REPO:
            item["base"] = pr["head"]["ref"]
            item["base_pr"] = pr["number"]
            item["base_ai"] = any(label["name"] == "ai-assisted" for label in pr["labels"])
            log(f"{cp}: building on #{pr['number']} ({item['base']})")
            break
    log(f"{cp}: {old} -> {new} ({mode})")
    return item


# --- lint ----------------------------------------------------------------------

# Our own keys in nvchecker.toml, which nvchecker ignores
OWN_KEYS = {"x_mode", "x_drop_old"}


def lint():
    """Problems in nvchecker.toml, as (errors, warnings). Needs no portage."""
    try:
        config = tomllib.loads(CONFIG.read_text())
    except tomllib.TOMLDecodeError as e:
        return [f"{CONFIG.name}: {e}"], []
    # Live ebuilds can't be bumped
    packages = {str(p.parent.relative_to(ROOT)) for p in ROOT.glob("*/*/*.ebuild") if "9999" not in p.stem}
    errors, warnings = [], []
    for cp, entry in config.items():
        if cp == "__config__":
            continue
        if not isinstance(entry, dict):
            errors.append(f"{cp}: not a table")
            continue
        if cp not in packages:
            errors.append(f"{cp}: no such package (or only live ebuilds), remove its entry")
        if "source" not in entry:
            errors.append(f"{cp}: no source")
        if entry.get("x_mode", "issue") not in MODES:
            errors.append(f"{cp}: unknown x_mode {entry['x_mode']!r}, use one of {', '.join(MODES)}")
        if not isinstance(entry.get("x_drop_old", True), bool):
            errors.append(f"{cp}: x_drop_old must be true or false")
        for key in sorted(entry):
            if key.startswith("x_") and key not in OWN_KEYS:
                errors.append(f"{cp}: unknown key {key}, use one of {', '.join(sorted(OWN_KEYS))}")
    for cp in sorted(packages - set(config)):
        warnings.append(f"{cp}: not in {CONFIG.name}, so autobump doesn't check it")
    return errors, warnings


def cmd_lint(args):
    errors, warnings = lint()
    # Annotations in GitHub Actions
    gha = bool(os.environ.get("GITHUB_ACTIONS"))
    for kind, messages in (("error", errors), ("warning", warnings)):
        for message in messages:
            print(f"::{kind}::{message}" if gha else f"{kind}: {message}")
    if errors:
        sys.exit(f"{len(errors)} error(s) in {CONFIG.name}")
    print(f"{CONFIG.name}: ok")


# --- bump / drop ---------------------------------------------------------------


def cmd_bump(args):
    _, src = latest(args.atom)
    dst = src.with_name(f"{args.atom.split('/')[1]}-{args.new}.ebuild")
    if dst.exists():
        sys.exit(f"{dst.name} already exists")
    shutil.copy2(src, dst)
    log(f"{src.name} -> {dst.name}")
    align_with_main(args.atom, dst)
    manifest(args.atom)


def align_with_main(cp, keep):
    """Make the bump add only `keep` relative to main.

    On top of an open PR's branch, this removes the version that PR added
    (it is superseded) and restores ebuilds the PR dropped, so dropping old
    versions stays a separate commit. Other changes on the branch are kept.
    """
    try:
        listing = run("git", "ls-tree", "--name-only", "origin/main", f"{cp}/", capture=True)
    except subprocess.CalledProcessError:
        return
    on_main = {Path(line).name for line in listing.splitlines() if line.endswith(".ebuild")}
    here = {path.name for path in (ROOT / cp).glob("*.ebuild")}
    for name in sorted(here - on_main - {keep.name}):
        (ROOT / cp / name).unlink()
        log(f"removed superseded {name}")
    for name in sorted(on_main - here):
        run("git", "checkout", "origin/main", "--", f"{cp}/{name}")
        log(f"restored {name} from main")


def cmd_drop(args):
    path = dict(ebuilds(args.atom)).get(args.old)
    if not path:
        sys.exit(f"{args.atom}: no ebuild for {args.old}")
    run("git", "rm", "-q", str(path.relative_to(ROOT)))
    manifest(args.atom)


# --- prompt --------------------------------------------------------------------


def cmd_prompt(args):
    text = (HERE / "prompt.md").read_text()
    failure = Path(args.log).read_text(errors="replace")[-12000:] if args.log else ""
    if args.deps_log:
        deps_log = Path(args.deps_log).read_text(errors="replace")[-6000:].rstrip()
        deps = (
            "Installing its build-time dependencies failed, so some of them (maybe "
            "its toolchain) are missing:\n\n```\n" + deps_log + "\n```"
        )
    else:
        deps = (
            "Its build-time dependencies are installed, so the toolchain it needs "
            "(Rust, Go, .NET, Python, ...) is there and `ebuild <file> unpack` works "
            "for both versions."
        )
    for key, value in {
        "ATOM": args.atom,
        "OLD": args.old,
        "NEW": args.new,
        "URL": args.url or "(none)",
        "ROUND_MINUTES": str(args.round_minutes),
        "DEPS": deps,
        "FAILURE": failure or "(not built yet)",
    }.items():
        text = text.replace("{{" + key + "}}", value)
    print(text)


# --- transcript ----------------------------------------------------------------


def cmd_transcript(args):
    """Summarize a Claude round's stream-json output.

    Writes Claude's final message (and anything that isn't JSON, such as
    errors) to `text`, appends the commands it was denied to `denied`, and
    prints a one-line status for the step log.
    """
    raw = Path(args.jsonl).read_text(errors="replace")
    # The transcript is uploaded as an artifact, where GitHub doesn't mask secrets
    secret = os.environ.get("REDACT", "")
    if len(secret) >= 8 and secret in raw:
        raw = raw.replace(secret, "[REDACTED]")
        Path(args.jsonl).write_text(raw)
    result, other = None, []
    for line in raw.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            if line.strip():
                other.append(line)
            continue
        if isinstance(event, dict) and event.get("type") == "result":
            result = event
    denied = []
    for denial in (result or {}).get("permission_denials") or []:
        if not isinstance(denial, dict):
            denied.append(str(denial))
            continue
        tool_input = denial.get("tool_input") if isinstance(denial.get("tool_input"), dict) else {}
        what = tool_input.get("command") or tool_input.get("file_path") or tool_input.get("url") or json.dumps(tool_input)
        denied.append(f"{denial.get('tool_name', '?')}: {what}")
    text = (result or {}).get("result") or "(no result)"
    Path(args.text).write_text(text.rstrip() + ("\n\n" + "\n".join(other) if other else "") + "\n")
    if denied:
        with open(args.denied, "a") as f:
            f.writelines(" ".join(d.split())[:300] + "\n" for d in denied)
    if not result:
        print("no result" + (f": {other[-1][:200]}" if other else ""))
        return
    status = f"{result.get('num_turns', '?')} turns"
    if result.get("subtype") == "error_max_turns":
        status += ", stopped at the turn limit"
    elif result.get("is_error"):
        status += f", {result.get('subtype') or 'error'}"
    if denied:
        status += f", {len(denied)} command(s) denied"
    print(status)


# --- publish -------------------------------------------------------------------


def tail(path, lines=60, chars=10000):
    if not path.exists():
        return ""
    # Compiler command lines can be very long
    return "\n".join(path.read_text(errors="replace").splitlines()[-lines:])[-chars:]


def details(summary, body, lang="", markdown=False):
    if not body.strip():
        return ""
    if not markdown:
        body = f"```{lang}\n{body}\n```"
    return f"<details><summary>{summary}</summary>\n\n{body}\n\n</details>\n"


def denied_commands(result_dir):
    """The commands Claude wasn't allowed to run, a sign the tool allowlist or
    the container is missing something."""
    path = result_dir / "denied.txt"
    if not path.exists():
        return ""
    lines = list(dict.fromkeys(line for line in path.read_text(errors="replace").splitlines() if line.strip()))
    return details(f"Commands Claude was not allowed to run ({len(lines)})", "\n".join(lines[:50])) if lines else ""


def small(text):
    return f"\n<sup><sub>{text}</sub></sup>\n"


def headline(cp, old, new, url):
    version = f"[{new}]({url})" if url else new
    return f"`{cp}` {version} (we have {old})"


def release_notes(url, limit=20000):
    """The GitHub release notes behind a release url, made safe to quote."""
    m = re.fullmatch(r"https://github\.com/([^/]+/[^/]+)/releases/tag/(.+)", url or "")
    if not m:
        return ""
    repo, tag = m.groups()
    try:
        release = api("GET", f"/repos/{repo}/releases/tags/{q(urllib.parse.unquote(tag))}")
    except RuntimeError as e:  # the issue or PR is still useful without them
        log(f"{repo}: could not fetch release notes: {e}")
        return ""
    notes = ((release or {}).get("body") or "").strip()
    if not notes:
        return ""
    if len(notes) > limit:
        notes = notes[:limit].rsplit("\n", 1)[0] + f"\n\n... [Full release notes]({url})"
    # Keep upstream's mentions and references from pinging people or showing
    # up on upstream's issues, and point bare #123 at upstream instead of here
    notes = re.sub(r"(?<!\w)@(?=[A-Za-z0-9])", "@\u200b", notes)
    notes = re.sub(r"https://github\.com/(?=[^/\s]+/[^/\s]+/(?:issues|pull|discussions)/)", "https://redirect.github.com/", notes)
    notes = re.sub(
        r"(?<![\w/&\[])(?:([\w.-]+/[\w.-]+))?#(\d+)\b",
        lambda m: f"[{m[0]}](https://redirect.github.com/{m[1] or repo}/issues/{m[2]})",
        notes,
    )
    return notes


def changelog(item, budget=30000):
    """The release notes of every release a bump covers, newest first, one
    collapsed section each. Past the budget, the rest are only linked."""
    releases = item.get("releases") or ([{"version": item["new"], "url": item["url"]}] if item.get("url") else [])
    sections, linked = [], []
    for release in releases:
        notes = release_notes(release["url"], min(20000, budget)) if budget >= 1000 else ""
        if notes:
            sections.append(details(f"Changelog {release['version']}", notes, markdown=True))
            budget -= len(notes)
        else:
            linked.append(release)
    # The headline already links the new version
    if linked and (sections or len(linked) > 1):
        links = ", ".join(f"[{release['version']}]({release['url']})" for release in linked)
        sections.append(f"Other releases in this bump: {links}.\n")
    return "".join(sections)


# GitHub rejects issue and PR bodies over 65536 characters
BODY_LIMIT = 60000


def fit(make_body, item):
    """make_body(changelog) with the release notes, or only links to them if too long."""
    body = make_body(changelog(item))
    if len(body) > BODY_LIMIT:
        body = make_body(changelog(item, budget=0))
    if len(body) > BODY_LIMIT:
        body = body[:BODY_LIMIT] + "\n\n(cut off)\n"
    return body


def open_issue(item, body, labels):
    existing = find_issues(item["atom"], item["new"], "open")
    if existing:
        # A retry that failed again: add to the existing issue
        number = existing[0]["number"]
        api("POST", f"/repos/{REPO}/issues/{number}/comments", {"body": f"Retried, still failing.\n\n{body}"})
        api("POST", f"/repos/{REPO}/issues/{number}/labels", {"labels": labels})
        log(f"{item['atom']}: commented on issue #{number}")
        return
    issue = api(
        "POST",
        f"/repos/{REPO}/issues",
        {
            "title": issue_title(item["atom"], item["new"]),
            "body": body,
            "labels": labels,
            "assignees": [MAINTAINER],
        },
    )
    autobump_issues().append(issue)
    log(f"{item['atom']}: opened issue {issue['html_url']}")
    close_older_issues(item["atom"], item["new"], issue["number"])


def close_older_issues(cp, new, number):
    """Close open autobump issues for older versions of cp, now superseded by #number."""
    for issue in autobump_issues():
        title = issue["title"]
        if (
            issue["state"] == "open"
            and title.startswith(f"{cp}: ")
            and title.endswith(" available")
            and title != issue_title(cp, new)
        ):
            close_issue(issue, f"Superseded by #{number}.", "not_planned")
            log(f"{cp}: closed superseded issue #{issue['number']}")


def close_superseded(cp, branch):
    for pr in open_prs():
        ref = pr["head"]["ref"]
        if ref.startswith(f"autobump/{cp}-") and ref != branch:
            api("POST", f"/repos/{REPO}/issues/{pr['number']}/comments", {"body": f"Superseded by `{branch}`, which carries over the changes from this PR."})
            api("PATCH", f"/repos/{REPO}/pulls/{pr['number']}", {"state": "closed"})
            api("DELETE", f"/repos/{REPO}/git/refs/heads/{q(ref)}")
            log(f"{cp}: closed superseded PR #{pr['number']}")


CREATE_COMMIT = """
mutation($input: CreateCommitOnBranchInput!) {
  createCommitOnBranch(input: $input) { commit { oid } }
}
"""


def push_commits(branch, commits):
    """Create branch from origin/main with one commit per (patch, message).

    The commits are made through the API rather than pushed, so GitHub signs
    them as the App and they show as Verified. The patches are also applied
    to a local checkout to work out which files each commit changes.

    An existing branch (a regenerated PR) is only moved once the commits are
    made on a staging branch: GitHub closes a PR whose head is reset to main.
    """
    head = run("git", "rev-parse", "origin/main", capture=True).strip()
    target = f"/repos/{REPO}/git/refs/heads/{q(branch)}"
    work = f"autobump-staging/{branch}" if api("GET", target) else branch
    ref = f"/repos/{REPO}/git/refs/heads/{q(work)}"
    if api("GET", ref):
        api("PATCH", ref, {"sha": head, "force": True})
    else:
        api("POST", f"/repos/{REPO}/git/refs", {"ref": f"refs/heads/{work}", "sha": head})
    run("git", "checkout", "-q", "-B", branch, "origin/main")

    for patch, message in commits:
        run("git", "apply", "--index", str(patch))
        additions, deletions = [], []
        changed = run("git", "diff", "--cached", "--name-status", "--no-renames", capture=True)
        for line in changed.splitlines():
            state, path = line.split("\t", 1)
            if state == "D":
                deletions.append({"path": path})
            else:
                contents = base64.b64encode((ROOT / path).read_bytes()).decode()
                additions.append({"path": path, "contents": contents})
        headline, _, body = message.partition("\n\n")
        data = graphql(
            CREATE_COMMIT,
            {
                "input": {
                    "branch": {"repositoryNameWithOwner": REPO, "branchName": work},
                    "expectedHeadOid": head,
                    "message": {"headline": headline, "body": body},
                    "fileChanges": {"additions": additions, "deletions": deletions},
                }
            },
        )
        head = data["createCommitOnBranch"]["commit"]["oid"]
        run("git", "commit", "-q", "-m", message)

    if work != branch:
        api("PATCH", target, {"sha": head, "force": True})
        api("DELETE", ref)


def open_pr(cp, new, branch, body, ai, draft):
    pr = api(
        "POST",
        f"/repos/{REPO}/pulls",
        {
            "title": f"chore({cp}): version {new}",
            "head": branch,
            "base": "main",
            "body": body,
            "draft": draft,
        },
    )
    labels = ["autobump"] + (["ai-assisted"] if ai else [])
    api("POST", f"/repos/{REPO}/issues/{pr['number']}/labels", {"labels": labels})
    api("POST", f"/repos/{REPO}/issues/{pr['number']}/assignees", {"assignees": [MAINTAINER]})
    try:
        api("POST", f"/repos/{REPO}/pulls/{pr['number']}/requested_reviewers", {"reviewers": [MAINTAINER]})
    except RuntimeError as e:  # the PR is still useful without the request
        log(f"{cp}: could not request a review: {e}")
    log(f"{cp}: opened PR {pr['html_url']}")
    return pr


SET_DRAFT = """
mutation($id: ID!) { convertPullRequestToDraft(input: {pullRequestId: $id}) { clientMutationId } }
"""
SET_READY = """
mutation($id: ID!) { markPullRequestReadyForReview(input: {pullRequestId: $id}) { clientMutationId } }
"""


def update_pr(cp, pr, body, ai, draft):
    """Bring a regenerated PR's description, draft state and labels up to date."""
    number = pr["number"]
    api("PATCH", f"/repos/{REPO}/pulls/{number}", {"body": body})
    if pr["draft"] != draft:
        graphql(SET_DRAFT if draft else SET_READY, {"id": pr["node_id"]})
    api("POST", f"/repos/{REPO}/issues/{number}/labels", {"labels": ["autobump"] + (["ai-assisted"] if ai else [])})
    if not ai and any(label["name"] == "ai-assisted" for label in pr["labels"]):
        api("DELETE", f"/repos/{REPO}/issues/{number}/labels/ai-assisted")
    url = run_url()
    run_link = f" in [this run]({url})" if url else ""
    api("POST", f"/repos/{REPO}/issues/{number}/comments", {"body": f"Regenerated from `main`{run_link}, replacing the previous commits."})
    log(f"{cp}: regenerated PR {pr['html_url']}")
    return pr


def run_url():
    """This workflow run's page, when running in GitHub Actions."""
    run_id = os.environ.get("GITHUB_RUN_ID")
    return f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{REPO}/actions/runs/{run_id}" if run_id else ""


def failure_note(res):
    """Why a failed bump failed, when that isn't in its logs."""
    reason = res.get("reason")
    if reason == "timeout":
        return (
            f"It ran out of time and was stopped after {res.get('budget') or '?'} minutes, usually "
            "because a dependency takes too long to compile on a hosted runner. The build log shows "
            "what was compiling. Bump it by hand (the `skip-build` label skips the CI build on its PR).\n\n"
        )
    if reason == "no-result":
        url = run_url()
        return (
            "The bump job ended without a result: it was cancelled, hit the job's time limit, or the "
            f"runner failed{f' (see [the run]({url}))' if url else ''}. Its logs are below if it "
            "uploaded any. Once that's sorted out, run the workflow with `only` set to this package "
            "and `retry` ticked.\n\n"
        )
    return ""


def publish_result(result_dir, item, res):
    cp, old, new, status = res["atom"], res["old"], res["new"], res["status"]
    # Changes carried over from an ai-assisted PR still need a careful review
    ai = status == "ai" or (status != "failed" and item.get("base_ai", False))
    ai_summary = (result_dir / "ai-summary.md").read_text() if (result_dir / "ai-summary.md").exists() else ""
    denied = denied_commands(result_dir)
    pkgcheck = tail(result_dir / "pkgcheck.txt", 40)
    build = tail(result_dir / "build.log", 60)
    branch = branch_name(cp, new)
    owner = REPO.split("/")[0]
    # Only there when regenerating
    existing = (api("GET", f"/repos/{REPO}/pulls?state=open&head={q(owner + ':' + branch)}") or [None])[0]

    if status == "failed" and existing:
        body = (
            "Regenerating failed, the PR is unchanged.\n\n"
            + failure_note(res)
            + (f"## Claude's notes\n\n{ai_summary}\n\n" if ai_summary else "")
            + denied
            + details("pkgcheck", pkgcheck)
            + details("Build log (tail)", build)
        )
        api("POST", f"/repos/{REPO}/issues/{existing['number']}/comments", {"body": body})
        log(f"{cp}: regenerating #{existing['number']} failed")
        return
    if status == "failed":
        body = fit(
            lambda notes: (
                f"{headline(cp, old, new, res['url'])}.\n\n"
                + "Autobump failed.\n\n"
                + failure_note(res)
                + (f"## Claude's notes\n\n{ai_summary}\n\n" if ai_summary else "")
                + denied
                + notes
                + details("pkgcheck", pkgcheck)
                + details("Build log (tail)", build)
                + small("Comment `@claude <instructions>` to have Claude try again, or bump it by hand.")
            ),
            item,
        )
        open_issue(res, body, ["autobump", "needs-human"])
        return

    message = f"chore({cp}): version {new}"
    if ai:
        message += f"\n\n{CLAUDE_TRAILER}"
    commits = [(result_dir / "bump.patch", message)]
    drop = result_dir / "drop.patch"
    if drop.exists() and drop.stat().st_size:
        commits.append((drop, f"chore({cp}): drop {old}"))
    push_commits(branch, commits)

    body = fit(
        lambda notes: (
            f"{headline(cp, old, new, res['url'])}.\n\n"
            + (f"Supersedes #{item['base_pr']}.\n\n" if item.get("base_pr") else "")
            + (f"## Claude's summary\n\n{ai_summary or '(no summary written)'}\n\n" if status == "ai" else "")
            + denied
            + notes
            + details("pkgcheck", pkgcheck)
            + details("Build log (tail)", build)
            + small("Comment `@claude <instructions>` to have Claude make changes.")
        ),
        item,
    )
    if existing:
        pr = update_pr(cp, existing, body, ai, draft=status == "ai")
    else:
        pr = open_pr(cp, new, branch, body, ai, draft=status == "ai")
    for issue in find_issues(cp, new, "open"):
        close_issue(issue, f"Retried in #{pr['number']}.", "completed")
        log(f"{cp}: closed issue #{issue['number']}")
    close_older_issues(cp, new, pr["number"])
    close_superseded(cp, branch)


def cmd_publish(args):
    failures = 0
    plan = json.loads(Path(args.plan).read_text()) if args.plan else {"issue": []}
    for item in plan["issue"]:
        try:
            body = fit(
                lambda notes: (
                    f"{headline(item['atom'], item['old'], item['new'], item['url'])}.\n\n"
                    + notes
                    + small("Comment `@claude <instructions>` for help.")
                ),
                item,
            )
            open_issue(item, body, ["autobump"])
        except Exception as e:  # keep going so one failure doesn't hide the rest
            log(f"{item['atom']}: {e}")
            failures += 1
    bumps = plan.get("bump", [])
    root = Path(args.results or "results")
    # download-artifact nests each artifact in its own directory only when
    # there is more than one, so look at any depth
    found = {}
    for path in sorted(root.rglob("result.json")) if root.is_dir() else []:
        try:
            res = json.loads(path.read_text())
            found[(res["atom"], res["new"])] = (path.parent, res)
        except Exception as e:
            log(f"{path}: {e}")
    for item in bumps:
        result_dir, res = found.get((item["atom"], item["new"]), (None, None))
        if res is None:
            # Cancelled or crashed. Record it anyway, or the next run tries again.
            log(f"{item['atom']}: no result for {item['new']}")
            failures += 1
            nested = root / f"result-{item['key']}"
            result_dir = nested if nested.is_dir() or len(bumps) > 1 else root
            res = {key: item[key] for key in ("atom", "old", "new", "mode", "url")}
            res |= {"status": "failed", "reason": "no-result"}
        try:
            publish_result(result_dir, item, res)
        except Exception as e:
            log(f"{item['atom']}: {e}")
            failures += 1
    # Found by check. Reported last, so they don't hold up the other packages.
    for error in plan.get("errors", []):
        log(f"check: {error}")
    if failures or plan.get("errors"):
        sys.exit(f"{failures} item(s) failed to publish, check found {len(plan.get('errors', []))} problem(s)")


# --- prune-caches --------------------------------------------------------------


def cmd_prune_caches(args):
    """Delete all but the newest Actions cache entry of each package and CI PR.

    The keys end in the run ID, so each run saves new entries next to the old
    ones, and GitHub only evicts them once the repository is over its limit.
    """
    caches = [
        cache
        for page in paginate(f"/repos/{REPO}/actions/caches?sort=created_at&direction=desc", key="actions_caches")
        for cache in page
    ]
    newest, freed = set(), 0
    for cache in caches:  # newest first
        m = re.fullmatch(r"(gentoo-.+)-\d+", cache["key"])
        if not m:
            continue
        if (cache["ref"], m[1]) not in newest:
            newest.add((cache["ref"], m[1]))
            continue
        if not args.dry_run:
            api("DELETE", f"/repos/{REPO}/actions/caches/{cache['id']}")
        freed += cache["size_in_bytes"]
        log(f"{'would delete' if args.dry_run else 'deleted'} {cache['key']} ({cache['size_in_bytes'] / 1e9:.2f} GB)")
    log(f"kept {len(newest)} cache entries, {'would free' if args.dry_run else 'freed'} {freed / 1e9:.2f} GB")


# --- main ----------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("check")
    p.add_argument("--only", help="only check this atom")
    p.add_argument("--force-mode", choices=MODES + ("",), help="override x_mode")
    p.add_argument("--output", help="also write the plan to this file")
    p.add_argument("--retry", action="store_true", help="retry versions that only have an issue")
    p.add_argument("--regenerate", action="store_true", help="redo versions that already have a PR (needs --only)")
    p.set_defaults(func=cmd_check)

    p = sub.add_parser("lint")
    p.set_defaults(func=cmd_lint)

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
    p.add_argument("--deps-log", help="log of a failed attempt to install the build-time dependencies")
    p.add_argument("--round-minutes", type=int, default=60, help="time limit of each Claude round")
    p.set_defaults(func=cmd_prompt)

    p = sub.add_parser("publish")
    p.add_argument("--plan", help="plan.json from check (for issue-mode items)")
    p.add_argument("--results", help="directory of per-package result dirs")
    p.set_defaults(func=cmd_publish)

    p = sub.add_parser("transcript")
    p.add_argument("jsonl", help="claude -p --output-format stream-json output")
    p.add_argument("text", help="write Claude's final message here")
    p.add_argument("denied", help="append the commands Claude was denied here")
    p.set_defaults(func=cmd_transcript)

    p = sub.add_parser("prune-caches")
    p.add_argument("--dry-run", action="store_true", help="only list what would be deleted")
    p.set_defaults(func=cmd_prune_caches)

    args = parser.parse_args()
    if getattr(args, "only", None) == "":
        args.only = None
    if getattr(args, "force_mode", None) == "":
        args.force_mode = None
    try:
        args.func(args)
    except AutobumpError as e:
        sys.exit(f"{getattr(args, 'atom', '')}: {e}" if getattr(args, "atom", None) else str(e))


if __name__ == "__main__":
    main()
