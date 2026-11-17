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
   already has a PR (open or closed) from an `autobump/<cat>/<pn>-<ver>` branch
   or an issue titled `<cat>/<pn>: <ver> available` (labelled `autobump`).
   Closing a PR without merging it therefore stops that version from being
   proposed again. A branch left without a PR (opening it failed) is bumped
   again.
   - A problem with one package (an nvchecker source that fails, an entry for
     a package that's gone, an unknown `x_mode`) doesn't stop the others. It's
     listed in the run's summary, and the run fails once everything else is
     published, so GitHub tells you.
   - It lists issues and PRs once per run instead of searching for each
     package (the search API allows 30 requests a minute).
   - For entries with `x_signed`, it waits until those release assets have a
     valid signature by `x_signing_key` (see
     [Configuring packages](#configuring-packages)). After 72 hours without
     one, the package is reported as a problem instead. The hours count from
     when the release was published, so one that was staged as a
     pre-release for longer can trip this for a run before it's re-signed.
2. **bump** (per package, up to 4 in parallel, 6 h limit) copies the latest
   ebuild to the new version, runs `pkgdev manifest` and `pkgcheck scan --exit
   error,warning,style` on the new version, and builds it with `gentoo.sh
   build`. That installs only what building it needs (`DEPEND`, `BDEPEND`,
   `IDEPEND`), then builds the package itself with its default USE flags plus
   `verify-sig`, so upstream's signatures are checked against the overlay's
   `sec-keys` packages (only for the package itself: ::gentoo binpkgs are
   built without it, and wouldn't be used with it). Its
   runtime-only dependencies are left out, so a GUI app doesn't compile a
   toolkit it only uses at run time, and a build that needs something only
   listed in `RDEPEND` fails, as it should (it belongs in `BDEPEND`).
   Dependencies come from Gentoo's official binhost, and distfiles and binpkgs
   are cached between runs (see [Cache](#cache)). Dependencies that are only `~amd64` in ::gentoo
   are keyworded automatically
   (`--autounmask-keep-keywords=n`), but `package.mask` is respected.
   - If that fails, or the package is `x_mode = "ai"`, Claude Code edits the
     new ebuild (deps, patches, `CRATES`, ...). The workflow re-runs pkgcheck
     and emerge after each round; Claude saying it's done isn't enough. Each
     round is stopped after `CLAUDE_ROUND_MINUTES` (60).
   - Before Claude starts, the package's build-time dependencies are installed
     (`gentoo.sh deps`), so its toolchain (Rust, Go, .NET, ...) is there and
     Claude can unpack and compare both versions. Nothing is set up per
     language: what gets installed comes from the ebuild. If that fails,
     Claude is shown why.
   - Only changes inside the package directory are kept.
   - The bump step's log shows pkgcheck and the build as they run, when each
     Claude round has to stop, and how many turns it took. The result
     artifact has each round's full transcript (`claude-round-N.jsonl`,
     every command and its output) and Claude's final message
     (`claude-round-N.txt`).
   - Commands Claude wasn't allowed to run are listed in the PR or issue. A
     recurring one means `CLAUDE_TOOLS` in `gentoo.sh` or the container is
     missing something.
   - A bump gives up after `BUDGET_MINUTES` (320, set in the workflow), so
     the job still saves its cache and uploads the result before the 6 h
     limit. It becomes a `needs-human` issue saying it ran out of time.
3. **publish** creates the commits through GitHub's API as the App bot, so
   GitHub signs them (Verified). They follow `CONTRIBUTING.md`
   (`chore(<cat>/<pn>): version <new>`, then `chore(<cat>/<pn>): drop <old>`
   if `x_drop_old`), and opens:
   - a **PR** for a mechanical bump,
   - a **draft PR** labelled `ai-assisted` if Claude changed anything (the
     commit carries a `Co-Authored-By: Claude` trailer),
   - an **issue** labelled `needs-human` if nothing worked, with the logs
     (also when a bump job was cancelled or crashed before it had a result),
   - an **issue** for `x_mode = "issue"` packages.

   PRs and issues quote the release notes of every GitHub release since the
   version in the overlay (for `source = "github"` entries), newest first,
   each in its own collapsed section. Check matches release tags to versions
   the way nvchecker does (`include_regex`, `prefix`, `from_pattern`, ...).
   Past 30,000 characters, the older releases are only linked.

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

`.github/workflows/ci.yml` runs `pkgcheck scan --exit error,warning,style` on
the changed packages and builds the changed ebuilds on every PR, the same way
as bump does (`info` findings are shown but don't fail it). Add the `skip-build` label for packages too heavy for a hosted
runner.

### Cache

Each bump job restores the newest cache of its package (or else the newest
of any package), and saves a new one under `gentoo-<cat>_<pn>-<run id>`.
Before saving, `gentoo.sh prune` (eclean) removes the distfiles and binpkgs
of anything the container didn't install, so a package's cache only holds
what it needs. The `caches` job then deletes all but the newest entry per
package. Without both, entries grow with every run and the repository's
10 GB fills up.

CI restores the PR's own cache, else the package's autobump cache. It
doesn't save one for autobump PRs, whose bump job just saved the same
package.

## Configuring packages

Everything is in [`nvchecker.toml`](nvchecker.toml), one table per package:

```toml
["net-p2p/mkbrr-bin"]
source = "github"            # any nvchecker source works
github = "autobrr/mkbrr"
use_latest_release = true    # or use_max_tag + include_regex for tag-only projects
prefix = "v"                 # strip from the tag to get ${PV}
x_mode = "pr"                # pr | ai | issue (default: issue)
x_drop_old = false           # keep the previous ebuild (default: true, drop it)
```

Use `from_pattern`/`to_pattern` when upstream versions don't map 1:1 to a
Gentoo version (e.g. `1.0b1` → `1.0_beta1`). Versions that still aren't valid
Gentoo versions become issues.

When upstream publishes a release before its signatures are final (Brave
signs with a pre-release key first and replaces the `.asc` files hours
later), a bump in between pins files that are about to change. List those
assets in `x_signed`, and check only proposes the version once each one's
`<asset>.asc` verifies against the keys at `x_signing_key`. It needs
`source = "github"`:

```toml
x_signed = ["foo_{version}_amd64.deb.sha256"]   # {version} is the new version
x_signing_key = "https://example.com/release-keys.asc"
```

This only decides when to bump. The build verifies the files against the
overlay's own `sec-keys` package, which a person updates when upstream's keys
change: give that package `x_mode = "issue"` (see
`sec-keys/openpgp-keys-brave`).

`python3 .github/autobump/autobump.py lint` checks the file against the
overlay. It reports as errors: entries for packages that are gone, unknown
`x_mode` values, `x_` keys it doesn't know (typos) and entries without a
`source`. Packages without an entry are only a warning, since opting in is up
to you. CI runs it on every PR (also when only `nvchecker.toml` changed), and
check runs it daily, so changes pushed straight to `main` are caught too.

## Running it

- **Schedule:** daily at 06:17 UTC.
- **By hand:** Actions → Autobump → Run workflow. `only` limits it to one
  package, `force_mode` overrides `x_mode`, `dry_run` only lists what would
  be bumped.
- **Retrying** a `needs-human` issue (e.g. after fixing the workflow): run it
  with `only` set to the package and `retry` ticked. A PR closes the issue;
  another failure is added to it as a comment. Cancelling a run also leaves
  such issues for the bumps it interrupted, so retry those the same way.
- **Regenerating** a PR (e.g. after changing the workflow, the prompt, or the
  previous ebuild on `main`): run it with `only` set to the package and
  `regenerate` ticked. The version is bumped again from `main` and the open
  PR's branch is replaced with the new commits, discarding anything pushed to
  it since (by `@claude` or by hand). Its description, draft state and
  `ai-assisted` label are updated to match. If it fails, the failure is
  commented on the PR and the PR is left as it was. A version whose PR was
  closed gets a new PR.
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
   limits. `CLAUDE_ROUNDS`, `CLAUDE_MAX_TURNS` and `CLAUDE_ROUND_MINUTES` in `gentoo.sh`, plus
   `max-parallel` in the workflow, keep it bounded. Without this secret, bumps
   that need Claude become `needs-human` issues.

## Security notes

- The bump job (which builds upstream code and runs Claude) has a read-only
  `GITHUB_TOKEN` and no push credentials. Only the publish job gets the App
  token, and it only applies patches and calls the API. The `caches` job's
  token may delete Actions caches (`actions: write`); it runs nothing from
  upstream.
- `main` should have a ruleset that only lets the repository admin update it,
  so neither the bot nor `@claude` can push there directly; they can only
  open PRs.
- Claude is told never to get past a failed signature or checksum check by
  changing `verify-sig`, the key it uses or a `sec-keys` package's
  fingerprints. Check that in any `ai-assisted` PR that touches them.
- Claude runs with a fixed tool allowlist and only receives the OAuth token in
  its own process. Builds that Claude starts itself inherit Claude's
  environment. Setting `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` on the `claude`
  call in `gentoo.sh` should strip it (untested here). If the token ever
  leaks, revoke it at <https://claude.ai/settings>.
- `claude.yml` only reacts to the repository owner. CI on fork PRs runs
  without secrets.

## Known limits

Not a problem yet, but worth knowing as the overlay grows:

- **Late runs.** GitHub delays scheduled workflows under load. Runs set for
  06:17 UTC have started 7 to 10 hours late. That doesn't matter for daily
  bumps. Use *Run workflow* when timing does.
- **API budget.** Check uses the job's `GITHUB_TOKEN`, which allows 1,000
  requests an hour: about one per package for nvchecker, plus a few per
  outdated package. At several hundred packages, give check the App token.
- **Setup per job.** Every bump job sets up its container from scratch
  (`gentoo.sh setup`, a few minutes). A prebuilt image, refreshed daily,
  would save that once there are many bumps a day.
- **Claude usage.** Each new version of an `x_mode = "ai"` package costs a
  Claude session, and horizon-launcher releases about once a day. If that
  hits the plan's limits, a minimum release age or a weekly schedule per
  package (like Renovate's `minimumReleaseAge`) would throttle it.
- **No cap per run.** Apart from GitHub's 256-job matrix limit, nothing
  limits how many bumps a run starts. With `max-parallel: 4`, opting in many
  packages at once can queue many long jobs.
