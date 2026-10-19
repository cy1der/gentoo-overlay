# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{11..14} )

inherit desktop distutils-r1 pypi systemd xdg-utils

DESCRIPTION="Graphical monitor configurator for Hyprland, Sway and Niri"
HOMEPAGE="https://github.com/ToRvaLDz/monique"
SRC_URI="https://github.com/ToRvaLDz/monique/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd +udev"

RDEPEND="
	dev-python/pygobject[${PYTHON_USEDEP}]
	gui-libs/libadwaita
	gui-libs/gtk:4
	udev? ( dev-python/pyudev[${PYTHON_USEDEP}] )
"

DEPEND="${RDEPEND}"
BDEPEND="dev-python/setuptools[${PYTHON_USEDEP}]"

python_install_all() {
	distutils-r1_python_install_all

	domenu data/com.github.monique.desktop

	insinto /usr/share/icons/hicolor/scalable/apps
	doins data/com.github.monique.svg

	insinto /usr/share/polkit-1/rules.d
	doins data/com.github.monique.rules

	if use systemd; then
		systemd_douserunit data/moniqued.service
	fi
}

pkg_postinst() {
	xdg_icon_cache_update

	if use systemd; then
		elog "To enable the moniqued daemon: systemctl --user enable --now moniqued"
	fi
}

pkg_postrm() {
	xdg_icon_cache_update
}
