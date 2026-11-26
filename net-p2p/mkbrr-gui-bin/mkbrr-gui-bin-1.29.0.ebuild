# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

DESCRIPTION="Graphical interface for mkbrr, a torrent file creation and inspection tool"
HOMEPAGE="https://mkbrr.com/ https://github.com/autobrr/mkbrr"
SRC_URI="
	https://github.com/autobrr/mkbrr/releases/download/v${PV}/mkbrr-gui_v${PV}_linux_amd64.tar.gz
	https://raw.githubusercontent.com/autobrr/mkbrr/v${PV}/gui/build/appicon.png -> ${P}.png
"
S="${WORKDIR}"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="-* ~amd64"

RESTRICT="strip test"

RDEPEND="
	dev-libs/glib:2
	net-libs/libsoup:3.0
	net-libs/webkit-gtk:4.1
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
"

QA_PREBUILT="usr/bin/mkbrr-gui"

src_unpack() {
	unpack mkbrr-gui_v${PV}_linux_amd64.tar.gz
}

src_install() {
	dobin mkbrr-gui
	newicon "${DISTDIR}/${P}.png" mkbrr-gui.png
	make_desktop_entry mkbrr-gui mkbrr mkbrr-gui "Network;P2P;"
}
