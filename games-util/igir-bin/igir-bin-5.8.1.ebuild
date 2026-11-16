# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Zero-setup ROM collection manager that sorts, filters, extracts and patches ROMs"
HOMEPAGE="https://igir.io/"
SRC_URI="
	amd64? ( https://github.com/emmercm/igir/releases/download/v${PV}/igir-${PV}-Linux-amd64.tar.gz )
	arm64? ( https://github.com/emmercm/igir/releases/download/v${PV}/igir-${PV}-Linux-arm64v8.tar.gz )
"
S="${WORKDIR}/${P}"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"

RESTRICT="strip test"

QA_PREBUILT="usr/bin/igir"

src_unpack() {
	default

	mkdir -p "${S}" || die
	mv "${WORKDIR}/igir" "${S}/" || die
}

src_install() {
	dobin igir
}
