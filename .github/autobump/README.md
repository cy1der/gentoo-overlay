# Autobump

Renovate-style version bumps for this overlay. A daily GitHub Actions run
checks every package's upstream with
[nvchecker](https://nvchecker.readthedocs.io). For each new version it bumps the
package in a `gentoo/stage3` container, builds it, and opens a PR (or an issue
if it can't).

## How it works

```
check (ubuntu)                bump (one job per package)                 publish
nvchecker vs ebuilds  ──►  copy ebuild, Manifest, pkgcheck, emerge  ──►  PR / issue
dedupe vs PRs/issues          └─ failed or x_mode=ai: Claude, ≤3 rounds,  (GitHub App
                                 each re-verified by pkgcheck + emerge     token)
```

1. **check** builds the current version of each package from the ebuild
   filenames, asks nvchecker for upstream's latest, and skips anything that
   already has an `autobump/<cat>/<pn>-<ver>` branch, a PR (open or closed) or an
   issue titled `<cat>/<pn>: <ver> available`. Closing a PR without merging it
   therefore stops that version from being proposed again.
2. **bump** (per package, up to 4 in parallel, 6 h limit) copies the latest
   ebuild to the new version, runs `pkgdev manifest` and `pkgcheck scan --exit
   error`, and builds it with `emerge`. Dependencies come from Gentoo's official
   binhost, and distfiles and binpkgs are cached between runs.
   - If that fails, or the package is `x_mode = "ai"`, Claude Code edits the
     new ebuild (deps, patches, `CRATES`, ...). The workflow re-runs pkgcheck
     and emerge after each round; Claude saying it's done isn't enough.
   - Only changes inside the package directory are kept.
3. **publish** creates the commits through GitHub's API as the App bot, so
   GitHub signs them (Verified). They follow `CONTRIBUTING.md`
   (`chore(<cat>/<pn>): version <new>`, then `chore(<cat>/<pn>): drop <old>`
   if `x_drop_old`), and opens:
   - a **PR** for a mechanical bump,
   - a **draft PR** labelled `ai-assisted` if Claude changed anything (the
     commit carries a `Co-Authored-By: Claude` trailer),
   - an **issue** labelled `needs-human` if nothing worked, with the logs,
   - an **issue** for `x_mode = "issue"` packages.

   Every issue and PR is assigned to the repository owner, and PRs request
   their review (set the `AUTOBUMP_MAINTAINER` environment variable on the
   publish step to use someone else).

   **When a newer version comes out first:** if the package still has an open
   bump PR, the new bump is built on top of that PR's branch, so fixes made
   there (by Claude, `@claude` or by hand) carry over. The intermediate
   ebuild is left out, and the PR is marked `ai-assisted` if the carried
   changes were. Once the new PR is open, the older PR is closed and its
   branch deleted, and open issues for older versions of the package are
   closed as superseded. If the newer version fails, the older PR stays open
   so it can still be merged.

Mention `@claude` in any issue or PR comment (owner only) to have Claude work
on it interactively (`.github/workflows/claude.yml`). That runs without
portage, so the CI workflow on the PR does the build check.

`.github/workflows/ci.yml` runs pkgcheck and builds the changed ebuilds on
every PR. Add the `skip-build` label for packages too heavy for a hosted
runner.

## Configuring packages

Everything is in [`nvchecker.toml`](nvchecker.toml), one table per package:

```toml
["net-p2p/mkbrr-bin"]
source = "github"            # any nvchecker source works
github = "autobrr/mkbrr"
use_latest_release = true    # or use_max_tag + include_regex for tag-only projects
prefix = "v"                 # strip from the tag to get ${PV}
x_mode = "pr"                # pr | ai | issue (default: issue)
x_drop_old = true            # also drop the previous ebuild (default: false)
```

Use `from_pattern`/`to_pattern` when upstream versions don't map 1:1 to a
Gentoo version (e.g. `1.0b1` → `1.0_beta1`). Versions that still aren't valid
Gentoo versions become issues.

## Running it

- **Schedule:** daily at 06:17 UTC.
- **By hand:** Actions → Autobump → Run workflow. `only` limits it to one
  package, `force_mode` overrides `x_mode`, `dry_run` only lists what would
  be bumped.
- **Retrying** a `needs-human` issue (e.g. after fixing the workflow): run it
  with `only` set to the package and `retry` ticked. A PR closes the issue;
  another failure is added to it as a comment.
- **Locally**, to see what's outdated: `pip install nvchecker`, then
  `GITHUB_TOKEN=$(gh auth token) python3 .github/autobump/autobump.py check`.

## One-time setup

1. **GitHub App** for the bot identity. PRs opened with the default
   `GITHUB_TOKEN` don't trigger other workflows, so CI wouldn't run on them.
   - <https://github.com/settings/apps/new>: name it e.g. `cy1der-autobump`,
     untick *Webhook → Active*. Repository permissions: *Contents*, *Issues*,
     *Pull requests*: read & write.
   - Generate a private key, then *Install App* on this repository only.
   - `gh variable set AUTOBUMP_CLIENT_ID` (the app's *Client ID*) and
     `gh secret set AUTOBUMP_APP_KEY < key.pem`.
2. **Claude:** run `claude setup-token` (needs a Pro or Max plan), then
   `gh secret set CLAUDE_CODE_OAUTH_TOKEN`. Usage counts against your plan's
   limits. `CLAUDE_ROUNDS` and `CLAUDE_MAX_TURNS` in `gentoo.sh`, plus
   `max-parallel` in the workflow, keep it bounded. Without this secret, bumps
   that need Claude become `needs-human` issues.

## Security notes

- The bump job (which builds upstream code and runs Claude) has a read-only
  `GITHUB_TOKEN` and no push credentials. Only the publish job gets the App
  token, and it only applies patches and calls the API.
- `main` should have a ruleset that only lets the repository admin update it,
  so neither the bot nor `@claude` can push there directly; they can only
  open PRs.
- Claude runs with a fixed tool allowlist and only receives the OAuth token in
  its own process. Builds that Claude starts itself inherit Claude's
  environment. Setting `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` on the `claude`
  call in `gentoo.sh` should strip it (untested here). If the token ever
  leaks, revoke it at <https://claude.ai/settings>.
- `claude.yml` only reacts to the repository owner. CI on fork PRs runs
  without secrets.
