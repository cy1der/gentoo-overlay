# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Framework for Steam client themes and plugins (Steambrew)"
HOMEPAGE="
	https://steambrew.app/
	https://github.com/SteamClientHomebrew/Millennium
"
SRC_URI="https://github.com/SteamClientHomebrew/Millennium/releases/download/v${PV}/millennium-v${PV}-linux-x86_64.tar.gz"
S="${WORKDIR}/usr/lib/millennium"

LICENSE="MIT"
SLOT="0"
KEYWORDS="-* ~amd64"
# The 32-bit files are only for Steam's legacy 32-bit client
IUSE="abi_x86_32"

RESTRICT="strip"

RDEPEND="
	app-arch/brotli:0/1
	app-arch/xz-utils
	app-arch/zstd:0/1
	dev-libs/openssl:0/3
	elibc_glibc? ( >=sys-libs/glibc-2.43 )
	abi_x86_32? ( dev-libs/openssl:0/3[abi_x86_32(-)] )
"

QA_PREBUILT="usr/lib/millennium/*"

src_install() {
	insinto /usr/lib/millennium
	exeinto /usr/lib/millennium

	local f
	for f in *; do
		if [[ ${f} == *_x86 || ${f} == *_x86.so ]] && ! use abi_x86_32; then
			continue
		fi

		if [[ ${f} == *.so ]]; then
			doins "${f}"
		else
			doexe "${f}"
		fi
	done

	dobin "${FILESDIR}"/millennium-link
}

pkg_postinst() {
	[[ -n ${REPLACING_VERSIONS} ]] && return

	elog "For each user, with Steam closed, run: millennium-link"
	elog "'millennium-link status' shows which client Steam runs and whether it is hooked"
	if ! use abi_x86_32; then
		elog "Steam's legacy 32-bit client needs USE=abi_x86_32"
	fi
}

pkg_postrm() {
	[[ -n ${REPLACED_BY_VERSION} ]] && return

	elog "Remove the symlinks from each user's Steam directory:"
	elog "  rm -f ~/.steam/steam/{ubuntu12_32,ubuntu12_64,steamrt64}/libXtst.so.6"
	elog "  rm -f ~/.steam/steam/ubuntu12_64/libmillennium_hhx64.so"
}
