# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit autotools

DESCRIPTION="Wine's Direct3D 12 implementation on top of Vulkan"
HOMEPAGE="https://gitlab.winehq.org/wine/vkd3d"
SRC_URI="https://dl.winehq.org/vkd3d/source/${P}.tar.xz"

LICENSE="LGPL-2.1+"
SLOT="0"
KEYWORDS="~amd64"
IUSE="ncurses spirv-tools"
# The tests need a Vulkan device
RESTRICT="test"

RDEPEND="
	media-libs/vulkan-loader
	ncurses? ( sys-libs/ncurses:= )
	spirv-tools? ( dev-util/spirv-tools )
"
DEPEND="
	${RDEPEND}
	dev-util/spirv-headers
	>=dev-util/vulkan-headers-1.3.228
"
BDEPEND="
	dev-lang/perl
	dev-perl/JSON
	sys-devel/bison
	sys-devel/flex
	virtual/pkgconfig
"

src_prepare() {
	default

	# Don't force LTO
	sed -i '/VKD3D_CHECK_CFLAGS(\[-flto=auto\])/d' configure.ac || die
	eautoreconf
}

src_configure() {
	local myeconfargs=(
		--disable-demos
		--disable-doxygen-doc
		--disable-static
		--disable-tests
		--without-opengl
		--without-xcb
		$(use_with ncurses)
		$(use_with spirv-tools)
		# The shipped headers are used; Wine's widl would regenerate them
		WIDL=no
		CROSSCC32=no
		CROSSCC64=no
	)
	econf "${myeconfargs[@]}"
}

src_install() {
	default
	find "${ED}" -name '*.la' -delete || die
}
