# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# The same major version as the clang upstream's setup downloads to compile the game
LLVM_COMPAT=( 22 )
PYTHON_COMPAT=( python3_{12..14} )
RMLUI_COMMIT="ba95ffe8bfb6370efb2cdcca927eaad4710c5413"

inherit cmake desktop edo flag-o-matic llvm-r2 python-single-r1 toolchain-funcs xdg

DESCRIPTION="Demon's Souls recompiled from your own PS3 copy, running natively"
HOMEPAGE="https://github.com/JonathanDC64/Soulbrandt"
SRC_URI="
	https://github.com/JonathanDC64/Soulbrandt/releases/download/v${PV}/DemonsSoulsRecomp-${PV}-source.zip
	https://github.com/mikke89/RmlUi/archive/${RMLUI_COMMIT}.tar.gz -> RmlUi-${RMLUI_COMMIT:0:8}.tar.gz
"
S="${WORKDIR}/DemonsSoulsRecomp-${PV}"
CMAKE_USE_DIR="${S}/port"

LICENSE="MIT"
# Bundled code (Mbed TLS, Monocypher, Dusklight's UI, the ATRAC3 decoders) and the UI's fonts
LICENSE+=" || ( Apache-2.0 GPL-2+ ) || ( BSD-2 CC0-1.0 ) Apache-2.0 CC0-1.0 LGPL-2.1+ OFL-1.1"
SLOT="0"
# The lifted game code needs x86-64 with SSE4.1
KEYWORDS="-* ~amd64"
IUSE="test"
REQUIRED_USE="${PYTHON_REQUIRED_USE}"
RESTRICT="!test? ( test )"

# FFmpeg is opened at run time, by the major version its headers name
COMMON_DEPEND="
	>=app-emulation/vkd3d-2.1
	>=dev-util/glslang-1.4.363.0:=
	>=dev-util/spirv-tools-1.4.363.0
	>=media-libs/freetype-2.14.3:2
	>=media-libs/libsdl3-3.4.20
	>=media-video/ffmpeg-6:=
	>=net-libs/miniupnpc-2.3.3:=
"
RDEPEND="
	${COMMON_DEPEND}
	${PYTHON_DEPS}
	media-libs/vulkan-loader
	$(llvm_gen_dep '
		llvm-core/clang:${LLVM_SLOT}
		llvm-core/lld:${LLVM_SLOT}
	')
"
DEPEND="
	${COMMON_DEPEND}
	>=dev-libs/stb-20260415
	>=dev-util/vulkan-headers-1.4.363.0
"
BDEPEND="
	${PYTHON_DEPS}
	app-arch/unzip
	virtual/pkgconfig
	$(llvm_gen_dep 'llvm-core/clang:${LLVM_SLOT}')
"

PATCHES=(
	"${FILESDIR}"/${PN}-0.2.0-system-libs.patch
	"${FILESDIR}"/${PN}-0.2.0-no-self-update.patch
	"${FILESDIR}"/${PN}-0.2.0-data-dir.patch
)

pkg_setup() {
	llvm-r2_pkg_setup
	python-single-r1_pkg_setup
}

src_prepare() {
	cmake_src_prepare
	CMAKE_USE_DIR="${S}"/ps3recomp cmake_prepare

	# They test the release tooling, with files from .github/ that the source zip leaves out
	rm tools/setup/tests/test_{llvm_pack,third_party_sources}.py || die
}

src_configure() {
	# The split build (des_host beside a game module) needs clang
	if ! tc-is-clang; then
		export CC=${CHOST}-clang-${LLVM_SLOT} CXX=${CHOST}-clang++-${LLVM_SLOT}
		strip-unsupported-flags
	fi

	# des_host takes one file from a lift, and it is ps3recomp's own (as upstream's CI makes it)
	mkdir "${T}"/host_lift || die
	edo "${EPYTHON}" ps3recomp/tools/gen_hle_nids.py --all --out "${T}"/host_lift/hle_nid_table.cpp

	# The runtime library, as upstream's Linux host is built (.github/workflows/host.yml)
	local mycmakeargs=(
		-DFETCHCONTENT_FULLY_DISCONNECTED=ON
		-DPS3RECOMP_BUILD_TESTS=OFF
		-DPS3RECOMP_FFMPEG_INCLUDE_DIR="${ESYSROOT}"/usr/include
		-DPS3RECOMP_FFMPEG_RUNTIME=ON
		-DPS3RECOMP_GAME_SPLIT=ON
		-DPS3RECOMP_NO_DECRYPT=ON
		-DPS3RECOMP_RSX_D3D12_VKD3D=ON
		-DPS3RECOMP_RSX_HAL=ON
	)
	CMAKE_USE_DIR="${S}"/ps3recomp BUILD_DIR="${WORKDIR}"/runtime_build cmake_src_configure

	# The program alone: the game module is built on the player's PC, by setup
	mycmakeargs=(
		# The bundled RmlUi is linked in
		-DBUILD_SHARED_LIBS=OFF
		# The program is installed from the build tree
		-DCMAKE_SKIP_RPATH=ON
		-DDES_DEV=OFF
		-DDES_HOST_ONLY=ON
		-DDES_REQUIRE_PIN=ON
		-DDES_SPLIT=ON
		-DDES_SPLIT_FREESTANDING=ON
		-DDES_VKD3D=ON
		-DFETCHCONTENT_FULLY_DISCONNECTED=ON
		-DFETCHCONTENT_SOURCE_DIR_RMLUI="${WORKDIR}"/RmlUi-${RMLUI_COMMIT}
		-DFETCHCONTENT_SOURCE_DIR_STB="${ESYSROOT}"/usr/include/stb
		-DPS3RECOMP_BUILD_DIR="${WORKDIR}"/runtime_build
		-DPS3RECOMP_SPLIT_LIB="${WORKDIR}"/runtime_build/libps3recomp_runtime.a
		-DRECOMP_DIR="${T}"/host_lift
	)
	BUILD_DIR="${WORKDIR}"/host_build cmake_src_configure
}

src_compile() {
	BUILD_DIR="${WORKDIR}"/runtime_build cmake_src_compile ps3recomp_runtime
	BUILD_DIR="${WORKDIR}"/host_build cmake_src_compile des_host
}

src_test() {
	cd tools/setup || die
	local -x PYTHONDONTWRITEBYTECODE=1
	edo "${EPYTHON}" -m unittest discover -s tests -v
}

src_install() {
	# Laid out as upstream's Linux download: the program, and setup/ beside it
	local dist=/usr/$(get_libdir)/${PN}

	exeinto ${dist}
	newexe "${WORKDIR}"/host_build/des_host Soulbrandt

	# setup/: the files of the tree that the download takes (tools/release/player-files.txt), in the tree's layout:
	# setup's engine, the lifters, and what the game module is compiled from
	"${EPYTHON}" - > "${T}"/setup-files <<-EOF || die
		import os, sys
		sys.path.insert(0, "tools/release")
		import package
		patterns = [rx for _line, rx in package.player_patterns()]
		for root, dirs, files in os.walk("."):
		    dirs[:] = [d for d in dirs if d not in (".git", "__pycache__")]
		    for name in files:
		        rel = os.path.relpath(os.path.join(root, name), ".")
		        if any(rx.match(rel) for rx in patterns):
		            print(rel)
	EOF
	[[ -s ${T}/setup-files ]] || die "no files for setup/"
	local f
	while read -r f; do
		insinto ${dist}/setup/$(dirname "${f}")
		doins "${f}"
	done < "${T}"/setup-files

	cp release-info.txt "${T}" || die
	echo "exe=Soulbrandt" >> "${T}"/release-info.txt || die
	insinto ${dist}/setup
	doins "${T}"/release-info.txt
	python_optimize "${ED}"${dist}/setup

	sed -e "s|@DIST@|${EPREFIX}${dist}|" \
		-e "s|@PYTHON@|${PYTHON}|" \
		-e "s|@CLANG@|${EPREFIX}/usr/lib/llvm/${LLVM_SLOT}/bin/clang|" \
		"${FILESDIR}"/${PN}-0.2.0-wrapper.sh > "${T}"/${PN} || die
	dobin "${T}"/${PN}

	make_desktop_entry ${PN} Soulbrandt applications-games "Game;ActionGame;RolePlaying"

	dodoc README.md port/ui/NOTICE.md
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "No game files are included. You need your own copy of Demon's Souls for the PS3, as a"
	elog "folder with PS3_GAME in it: the US (BLUS30443) or European (BLES00932) disc at 1.00, or"
	elog "the Japanese (BCJS30022) or Asian (BCAS20071) disc with its 1.04 update."
	elog "Setup unlocks the game's encrypted files with RPCS3, or takes files you decrypted yourself."
	elog
	elog "Start it with 'soulbrandt'. Setup then lifts the game and compiles it with the"
	elog "system's clang ${LLVM_SLOT} and Python, in \${XDG_DATA_HOME:-~/.local/share}/DemonsSoulsRecomp"
	elog "(about 4 GB, and about 2 GB of memory per compile job). Saves, settings and logs go to"
	elog "\${XDG_DATA_HOME:-~/.local/share}/DemonsSoulsRecomp/DemonsSouls."
	elog "Updates come through portage; the program's own updater is turned off. Run setup again"
	elog "(it offers to) after each upgrade."
}
