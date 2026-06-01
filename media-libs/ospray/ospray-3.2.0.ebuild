# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake flag-o-matic

IMGUI_PV="1.90.9"
STB_COMMIT="013ac3beddff3dbffafd5177e7972067cd2b5083"
DESCRIPTION="An Open, Scalable, Portable, Ray Tracing Based Rendering Engine for High-Fidelity Visualization."
HOMEPAGE="https://ospray.org/"
SRC_URI="https://github.com/RenderKit/ospray/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
    examples? (
        https://github.com/ocornut/imgui/archive/refs/tags/v${IMGUI_PV}.tar.gz -> imgui-${IMGUI_PV}.tar.gz
        https://github.com/nothings/stb/archive/${STB_COMMIT}.tar.gz -> stb-${STB_COMMIT}.tar.gz
    )
    test? (
        https://github.com/ocornut/imgui/archive/refs/tags/v${IMGUI_PV}.tar.gz -> imgui-${IMGUI_PV}.tar.gz
        https://github.com/nothings/stb/archive/${STB_COMMIT}.tar.gz -> stb-${STB_COMMIT}.tar.gz
    )
"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE="denoiser mpi +volume examples test"

RESTRICT="!test? ( test )"

RDEPEND="
    >=dev-lang/ispc-1.23.0
    >=media-libs/embree-4.3.3[ispc]
    media-libs/rkcommon
    denoiser? ( >=media-libs/oidn-2.3.0 )
    volume? ( >=media-libs/openvkl-2.0.1 )
    mpi? (
        virtual/mpi
        app-arch/snappy
    )
    examples? (
        virtual/opengl
        media-libs/glfw
        dev-cpp/gtest
        dev-cpp/benchmark
    )
    test? (
        virtual/opengl
        media-libs/glfw
        dev-cpp/gtest
        dev-cpp/benchmark
    )
"

DEPEND="${RDEPEND}"

src_prepare() {
    cmake_src_prepare

    sed -i -e '/find_package(rkcommon/s/ EXACT//' cmake/ospray_options.cmake || die
}

src_configure() {
    append-cxxflags -include cstdint -include algorithm

    cat <<- EOF > "${T}/ispc-wrapper"
		#!/bin/sh
		exec $(type -P ispc) --woff "\$@"
	EOF
	chmod +x "${T}/ispc-wrapper"

    local enable_apps="OFF"
	if use examples || use test; then
		enable_apps="ON"
	fi

	local mycmakeargs=(
        -DISPC_EXECUTABLE="${T}/ispc-wrapper"
        -DFETCHCONTENT_FULLY_DISCONNECTED=ON
        -DOSPRAY_ENABLE_VOLUMES=$(usex volume)
        -DOSPRAY_MODULE_DENOISER=$(usex denoiser)
        -DOSPRAY_MODULE_MPI=$(usex mpi)
        -DOSPRAY_ENABLE_APPS="${enable_apps}"
        -DOSPRAY_ENABLE_APPS_EXAMPLES=$(usex examples)
        -DOSPRAY_ENABLE_APPS_TUTORIALS=$(usex examples)
		-DOSPRAY_ENABLE_APPS_TESTING=$(usex test)
	)

    if use examples || use test; then
		mycmakeargs+=(
			-DFETCHCONTENT_SOURCE_DIR_IMGUI="${WORKDIR}/imgui-${IMGUI_PV}"
            -DFETCHCONTENT_SOURCE_DIR_STB="${WORKDIR}/stb-${STB_COMMIT}"
		)
	fi

	cmake_src_configure
}