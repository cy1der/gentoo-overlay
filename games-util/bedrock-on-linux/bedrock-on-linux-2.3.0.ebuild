# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..15} )
DISTUTILS_USE_PEP517=setuptools
DISTUTILS_SINGLE_IMPL=1
inherit distutils-r1 edo optfeature xdg

MY_PN="BedrockOnLinux"

DESCRIPTION="Run Minecraft Bedrock for Windows on Linux"
HOMEPAGE="
	https://wyze3306.github.io/BedrockOnLinux/
	https://github.com/Wyze3306/BedrockOnLinux
"
SRC_URI="https://github.com/Wyze3306/${MY_PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${MY_PN}-${PV}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="crossdev-mingw +gui +webkit"
# the GUI tests import PySide6 (they run on Qt's offscreen platform)
REQUIRED_USE="test? ( gui )"

RDEPEND="
	$(python_gen_cond_dep '
		dev-python/cryptography[${PYTHON_USEDEP}]
		gui? (
			dev-python/pyside[gui,widgets,${PYTHON_USEDEP}]
			dev-python/python-xlib[${PYTHON_USEDEP}]
		)
	')
	app-arch/zstd
	|| ( net-misc/curl net-misc/wget )
	x11-apps/xrandr
	x11-misc/xdg-utils
	webkit? ( net-libs/webkit-gtk:4.1 )
"
BDEPEND="!crossdev-mingw? ( dev-util/mingw64-toolchain )"

PATCHES=(
	"${FILESDIR}"/${PN}-2.2.10-no-pip-bootstrap.patch
)

# Windows helpers that run inside the game's Wine prefix
HELPERS=( injector fullscreen-nudge desktop-bridge )

EPYTEST_PLUGINS=()
distutils_enable_tests pytest

src_prepare() {
	# rebuilt from src/ in src_compile
	rm bol/*.exe || die

	distutils-r1_src_prepare
}

src_compile() {
	use crossdev-mingw || local -x PATH=${BROOT}/usr/lib/mingw64-toolchain/bin:${PATH}

	local cc=x86_64-w64-mingw32-gcc
	type -P ${cc} >/dev/null ||
		die "${cc} not found (USE=crossdev-mingw needs a crossdev mingw toolchain)"

	# host CFLAGS/LDFLAGS are for ${CHOST}, not for the mingw target
	local helper
	for helper in "${HELPERS[@]}"; do
		edo ${cc} -O2 -municode -s -Wl,--no-insert-timestamp \
			src/${helper}.c -o bol/${helper}.exe
	done

	# setuptools packs the helpers as package-data, so build them first
	distutils-r1_src_compile
}

src_install() {
	distutils-r1_src_install

	# the desktop entry opens the launcher window
	if ! use gui; then
		rm -r "${ED}"/usr/share/{applications,icons} || die
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "The managed Wine engine and the game are downloaded into your home"
	elog "directory on first run. Minecraft itself is not included: you need"
	elog "a Microsoft account that owns Minecraft for Windows."
	elog
	elog "The Steam Linux Runtime it runs in needs the en_US.UTF-8 locale."
	elog "Without it every launch takes a few seconds longer; add it to"
	elog "/etc/locale.gen and run locale-gen."

	optfeature "running the game inside gamescope" gui-wm/gamescope
	optfeature "notifications when the game fails to start" x11-libs/libnotify
}
