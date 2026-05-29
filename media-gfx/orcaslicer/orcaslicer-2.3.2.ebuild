# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

WX_GTK_VER="3.2-gtk3"

inherit check-reqs cmake flag-o-matic toolchain-funcs multiprocessing wxwidgets xdg

DESCRIPTION="G-code generator for 3D printers (Bambu, Prusa, Voron, VzBot, RatRig, Creality, etc.)"
HOMEPAGE="https://www.orcaslicer.com/"
SRC_URI="https://github.com/OrcaSlicer/OrcaSlicer/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/OrcaSlicer-${PV}"

LICENSE="AGPL-3"
SLOT="0"
KEYWORDS="~amd64"
IUSE="test"

RESTRICT="!test? ( test )"

PATCHES=(
	# From the stuff overlay (https://gpo.zugaina.org/AJAX/Ebuild/56487906/View)
	"${FILESDIR}/${P}-link-webkit2gtk.patch"
	"${FILESDIR}/${P}-mediactrl-audio-sink-guard.patch"
	"${FILESDIR}/${P}-opencascade-tkdestep.patch"
	"${FILESDIR}/${P}-wx-noop-assert-handler.patch"
	# andreili low-key the goat
	"${FILESDIR}/${P}-pr11803-ambiguous-overload.patch"
	"${FILESDIR}/${P}-pr13536-update-boost.patch"
	"${FILESDIR}/${P}-pr13557-update-cgal.patch"
	"${FILESDIR}/${P}-pr13822-opencv-world.patch"
)

RDEPEND="
	app-crypt/libsecret
	dev-cpp/gstreamermm
	>=dev-libs/boost-1.91.0
	dev-libs/libmspack 
	dev-libs/openssl
	media-gfx/openvdb
	media-libs/draco
	media-libs/glew
	media-libs/glfw
	media-libs/gst-plugins-base:1.0
	media-libs/gstreamer:1.0
	media-libs/libnoise
	media-libs/opencv:=
	media-libs/qhull
	media-plugins/gst-plugins-gtk:1.0
	net-libs/webkit-gtk:4.1
	net-misc/curl
	sci-libs/nlopt
	sci-libs/opencascade:=
	sci-mathematics/clipper2
	sys-apps/dbus
	x11-libs/gtk+:3
	x11-libs/wxGTK:${WX_GTK_VER}[curl,keyring,webkit]
"

DEPEND="
	${RDEPEND}
	dev-cpp/eigen:3
	dev-libs/cereal
	gui-libs/eglexternalplatform
	>=sci-mathematics/cgal-6.0
	media-libs/qhull[static-libs]
"

BDEPEND="
	dev-build/autoconf
	dev-build/cmake
	dev-build/libtool
	dev-build/ninja
	dev-vcs/git
	kde-frameworks/extra-cmake-modules
	sys-apps/file
	sys-apps/texinfo
	sys-devel/gettext
	virtual/pkgconfig
"

pkg_pretend() {
    if [[ ${MERGE_TYPE} != binary ]]; then
        CHECKREQS_DISK_BUILD="12G"
        CHECKREQS_MEMORY="$(($(makeopts_jobs) * 3))G"
        check-reqs_pkg_pretend
    fi
}

pkg_setup() {
    if [[ ${MERGE_TYPE} != binary ]]; then
        CHECKREQS_DISK_BUILD="12G"
        CHECKREQS_MEMORY="$(($(makeopts_jobs) * 3))G"
        check-reqs_pkg_setup
    fi
}

src_prepare() {
	cmake_src_prepare

	sed -i -e "s/+UNKNOWN/_Gentoo/" version.inc || die
	sed -i -e '/find_package.*Boost/ s/\bsystem\b//g' CMakeLists.txt || die
}

src_configure() {
	setup-wxwidgets

	filter-lto

	append-cppflags "$($(tc-getPKG_CONFIG) --cflags opencv4)"

	local mycmakeargs=(
		-DBUILD_TESTS=$(usex test)
		-DORCA_TOOLS=ON
		-DSLIC3R_FHS=ON
		-DSLIC3R_GTK=3
		-DSLIC3R_GUI=ON
		-DSLIC3R_PCH=OFF
		-DSLIC3R_STATIC=OFF
		-DOPENVDB_FIND_MODULE_PATH="/usr/$(get_libdir)/cmake/OpenVDB"
		-DwxWidgets_CONFIG_EXECUTABLE="${WX_CONFIG}"
		-Wno-dev
	)

	cmake_src_configure
}

src_install() {
    cmake_src_install

    rm "${ED}/usr/LICENSE.txt" || die
}