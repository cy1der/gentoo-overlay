This is a Gentoo ebuild repository (overlay) with `masters = gentoo` and thin
Manifests. Follow `CONTRIBUTING.md` for commit messages, ebuild style, patch
naming and binary packages.

When bumping a package:
- Copy the latest ebuild to the new version; don't edit the old one.
- Keep keywords as testing (`~arch`); `-bin` packages keep `-*` and only list
  the arches upstream ships.
- Regenerate the Manifest with `pkgdev manifest` and check with
  `pkgcheck scan --exit error -- <cat>/<pn>`.
- Touch one package per commit.

Version detection and automated bumps are configured in
`.github/autobump/`, see its `README.md`.
