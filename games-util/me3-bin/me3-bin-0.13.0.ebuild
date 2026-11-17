# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

DESCRIPTION="Mod loader for FromSoftware games (Mod Engine 3)"
HOMEPAGE="
	https://me3.help/
	https://github.com/garyttierney/me3
"
SRC_URI="https://github.com/garyttierney/me3/releases/download/v${PV}/me3-linux-amd64.tar.gz -> ${P}-linux-amd64.tar.gz"
S="${WORKDIR}"

LICENSE="|| ( Apache-2.0 MIT )"
SLOT="0"
KEYWORDS="-* ~amd64"

RESTRICT="strip"

RDEPEND="
	dev-libs/openssl:0/3
	elibc_glibc? ( >=sys-libs/glibc-2.39 )
"

QA_PREBUILT="usr/bin/me3"

src_install() {
	dobin bin/me3

	# The launcher and mod host run under Proton. me3 looks for them here
	# (the path is hardcoded, not $(get_libdir))
	insinto /usr/lib64/me3/x86_64-windows
	doins bin/win64/me3-launcher.exe bin/win64/me3_mod_host.dll

	# Opens .me3 profiles with 'me3 launch'. The logo (dist/me3.png) is all
	# rights reserved, so it isn't installed
	domenu dist/me3-launch.desktop
	insinto /usr/share/mime/packages
	doins dist/me3.xml

	docinto examples
	dodoc ./*.me3
	docompress -x /usr/share/doc/${PF}/examples
}

pkg_postinst() {
	xdg_pkg_postinst

	[[ -n ${REPLACING_VERSIONS} ]] && return

	elog "me3 launches games through Steam with the Proton version set for each game."
	elog "Profiles are kept in ~/.config/me3/profiles. Create one with 'me3 profile create',"
	elog "or copy the examples from ${EROOT}/usr/share/doc/${PF}/examples."
	elog
	elog "A copy installed by upstream's installer.sh (~/.local/bin/me3 and"
	elog "~/.local/share/me3/windows-bin) takes precedence over this one; remove it."
}
