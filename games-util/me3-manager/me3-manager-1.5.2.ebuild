# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_SINGLE_IMPL=1
DISTUTILS_USE_PEP517=uv-build
PYTHON_COMPAT=( python3_{13..15} )

inherit desktop distutils-r1 virtualx xdg

DESCRIPTION="GUI manager for Mod Engine 3 mods and profiles"
HOMEPAGE="
	https://me3-manager.github.io/me3-manager-help/
	https://github.com/2Pz/me3-manager
"
SRC_URI="https://github.com/2Pz/me3-manager/archive/refs/tags/${PV}.tar.gz -> ${P}.gh.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

# The manager's own installer is patched out, so it uses the system me3
RDEPEND="
	games-util/me3-bin
	$(python_gen_cond_dep '
		app-arch/patool[${PYTHON_USEDEP}]
		dev-python/ansi2html[${PYTHON_USEDEP}]
		dev-python/certifi[${PYTHON_USEDEP}]
		dev-python/configupdater[${PYTHON_USEDEP}]
		dev-python/pyside[gui,network,widgets,${PYTHON_USEDEP}]
		dev-python/requests[${PYTHON_USEDEP}]
		dev-python/tomli-w[${PYTHON_USEDEP}]
		dev-python/tomlkit[${PYTHON_USEDEP}]
		dev-python/websocket-client[${PYTHON_USEDEP}]
	')
"

PATCHES=(
	"${FILESDIR}"/${PN}-1.5.2-system-resources.patch
	"${FILESDIR}"/${PN}-1.5.2-system-me3.patch
)

EPYTEST_PLUGINS=( pytest-mock pytest-qt )
distutils_enable_tests pytest

src_test() {
	virtx distutils-r1_src_test
}

src_install() {
	distutils-r1_src_install

	insinto /usr/share/${PN}
	doins -r resources

	domenu resources/linux/${PN}.desktop
	newicon -s 256 resources/icon/icon.png ${PN}.png
}

pkg_postinst() {
	xdg_pkg_postinst

	[[ -n ${REPLACING_VERSIONS} ]] && return

	elog "me3 and the manager are updated through portage: the manager's me3 installer"
	elog "and its update checks are turned off."
}
