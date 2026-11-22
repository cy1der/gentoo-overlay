# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="A tool to create, inspect and modify torrent files"
HOMEPAGE="https://mkbrr.com/ https://github.com/autobrr/mkbrr"
SRC_URI="
	amd64? ( https://github.com/autobrr/mkbrr/releases/download/v${PV}/mkbrr_${PV}_linux_x86_64.tar.gz )
	arm? ( https://github.com/autobrr/mkbrr/releases/download/v${PV}/mkbrr_${PV}_linux_arm.tar.gz )
	arm64? ( https://github.com/autobrr/mkbrr/releases/download/v${PV}/mkbrr_${PV}_linux_arm64.tar.gz )
"
S="${WORKDIR}"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm ~arm64"

RESTRICT="strip test"

QA_PREBUILT="usr/bin/mkbrr"

src_install() {
	dobin mkbrr
	einstalldocs
}
