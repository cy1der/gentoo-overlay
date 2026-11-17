# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# This is a copy of net-vpn/proton-vpn-gtk-app-4.17.1::guru bumped to the latest version,
# with dependencies matching dev-python/proton-vpn-api-core-5.8.7::cy1der

EAPI=8

DISTUTILS_SINGLE_IMPL=true
DISTUTILS_USE_PEP517=setuptools

PYTHON_COMPAT=( python3_{11..14} )

inherit desktop distutils-r1

DESCRIPTION="Proton VPN GTK app"
HOMEPAGE="https://github.com/ProtonVPN/proton-vpn-gtk-app"
SRC_URI="https://github.com/ProtonVPN/proton-vpn-gtk-app/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="test"

# The network manager backend and local agent are part of proton-vpn-api-core since 5.x
RDEPEND="
	gui-libs/gtk:4[introspection]
	x11-libs/libnotify[introspection]
	$(python_gen_cond_dep '
		dev-python/dbus-python[${PYTHON_USEDEP}]
		dev-python/distro[${PYTHON_USEDEP}]
		dev-python/packaging[${PYTHON_USEDEP}]
		dev-python/proton-core[${PYTHON_USEDEP}]
		dev-python/proton-keyring-linux[${PYTHON_USEDEP}]
		>=dev-python/proton-vpn-api-core-5.8.1[${PYTHON_USEDEP}]
		dev-python/pycairo[${PYTHON_USEDEP}]
		dev-python/pygobject[${PYTHON_USEDEP}]
		dev-python/requests[${PYTHON_USEDEP}]
	')
"
# Translations are compiled with msgfmt
BDEPEND="sys-devel/gettext"

src_install() {
	distutils-r1_src_install

	doicon rpmbuild/SOURCES/proton-vpn-logo.svg
	domenu rpmbuild/SOURCES/proton.vpn.app.gtk.desktop
}
