# Contributing

## Commit messages

Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
with the package atom as the scope:

```
<type>(<category>/<package>): <summary>
```

- Write the summary in lowercase, imperative mood, with no trailing period
- Keep the subject line under 72 characters
- Make one logical change per commit, and touch one package per commit
- Add a body (after a blank line) only when the *why* isn't obvious, e.g.
  linking an upstream issue or explaining a workaround.

### Types

| Type    | Use for                                                       |
| ------- | ------------------------------------------------------------- |
| `feat`  | Adding a new package or a new feature to an existing package (like a new USE flag or something)                                          |
| `chore` | Version bumps, syncing changes from `::gentoo`, removing old versions, other maintenance |
| `fix`   | Fixing a broken ebuild: build failures, missing deps, wrong license, typos |

### Common scenarios

| Scenario                         | Example                                                          |
| -------------------------------- | ---------------------------------------------------------------- |
| New package                      | `feat(net-p2p/mkbrr-bin): new ebuild`                            |
| Version bump                     | `chore(gui-apps/monique): version 0.8.3`                         |
| Pull changes from `::gentoo`     | `chore(sci-libs/vtk): python 3.14 and new patch from ::gentoo`   |
| Drop an old version              | `chore(gui-apps/monique): drop 0.6.7`                            |
| Remove a package                 | `chore(media-libs/libnoise): remove package`                     |
| Missing dependencies             | `fix(dev-python/proton-vpn-api-core): add missing runtime dependencies` |
| Build failure                    | `fix(media-gfx/f3d): fix failure to prepare when VTK was compiled with CUDA` |
| Metadata or license correction   | `fix(gui-apps/monique): change license to the same one gentoo repo uses` |
| Repo-wide change (no package)    | `chore(licenses): add TOST-1.0` or `chore(profiles): ...`        |

## Ebuild style

- Use `EAPI=8` and the standard Gentoo header:
  ```
  # Copyright 1999-2026 Gentoo Authors
  # Distributed under the terms of the GNU General Public License v2
  ```
- Indent with tabs
- New versions get testing keywords only (`~amd64`, `~arm64`, ...)
- Manifests are thin (`DIST` entries only). Regenerate them with
  `pkgdev manifest` or `ebuild <file> manifest`
- Add a `metadata.xml` with at least an `<upstream>` `remote-id` where one
  exists, and descriptions for any USE flags not described in `::gentoo`
- Fetch release tarballs rather than git checkouts (`git-r3`) for versioned
  ebuilds
- Keep only the newest version of a package unless an older one is still
  needed; drop the previous version when bumping
- `pkgcheck scan --exit error,warning,style -- <cat>/<pn>` must pass before
  committing (CI enforces this on PRs). `info` findings such as
  `PythonCompatUpdate` don't block, but fix them when it's easy

### Patches

- Put patches in `files/`, named after the version they were first written
  for: `${PN}-<version>-<short-description>.patch` (e.g.
  `rkcommon-1.15.2-fix-type-punning.patch`)
- Refer to them with that literal version, not `${PV}`/`${P}`
  (`"${FILESDIR}"/${PN}-1.15.2-fix-type-punning.patch`), so a bump can keep
  using a patch unchanged. Only add a new file, named for the new version,
  when the patch itself has to change
- If a patch comes from an upstream PR, include the PR number in the name
  (`${PN}-<version>-pr<number>-<short-description>.patch`)
- Drop patches that are no longer used by any ebuild in the directory

### Binary packages

- Prebuilt upstream binaries use the `-bin` suffix (e.g. `igir-bin`)
- Set `KEYWORDS="-* ~amd64 ..."` to list only the arches upstream ships,
  set `RESTRICT="strip"`, and list the installed binaries in `QA_PREBUILT`

## Automated bumps

A daily workflow checks upstream for new versions and opens PRs (see
[`.github/autobump/README.md`](.github/autobump/README.md)). To opt a package
in, add an entry for it to
[`.github/autobump/nvchecker.toml`](.github/autobump/nvchecker.toml) and pick
an `x_mode`:

| `x_mode` | What happens on a new upstream version                                   |
| -------- | ------------------------------------------------------------------------ |
| `pr`     | Copy the ebuild, regenerate the Manifest, check and build it, open a PR. If that fails, Claude tries to fix it |
| `ai`     | Claude does the bump (patches, vendored crates, dependency changes) and opens a draft PR |
| `issue`  | Only open an issue (for packages too heavy to build on a hosted runner)  |

Bump PRs drop the previous version unless the package sets `x_drop_old =
false`. Bot and Claude commits follow the same rules as everything else in
this file, including the pkgcheck rule above.
PRs labelled `ai-assisted` contain changes written by Claude; review them like
any other contribution before marking them ready. Comment `@claude` on an
issue or PR to have Claude work on it.
