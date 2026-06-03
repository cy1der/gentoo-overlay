# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..14} )

EGIT_LFS="yes"

inherit cmake cuda python-single-r1 java-pkg-opt-2 git-r3 xdg

DESCRIPTION="Fast and minimalist 3D viewer."
HOMEPAGE="https://f3d.app/"
EGIT_REPO_URI="https://github.com/f3d-app/f3d.git"
EGIT_COMMIT="v${PV}"
EGIT_LFS_CLONE_TYPE="single"

LICENSE="BSD-3-Clause"
SLOT="0"
KEYWORDS="~amd64"
IUSE="cuda raytracing openexr +imgui webp clipboard +hdf opencascade assimp alembic draco usd openvdb pdal web-ifc python java cxx test"
REQUIRED_USE="python? ( ${PYTHON_REQUIRED_USE} )"

RESTRICT="!test? ( test )"

RDEPEND="
    >=sci-libs/vtk-9.4.0[rendering,cuda?,openvdb?,pdal?,opencascade?]
    raytracing? ( >=sci-libs/vtk-9.4.0[ospray] )
    hdf? ( >=sci-libs/vtk-9.4.0[netcdf] )
    assimp? ( >=media-libs/assimp-5.4.0 )
    alembic? ( >=media-gfx/alembic-1.8.5 )
    openvdb? ( >=media-gfx/openvdb-12.0.0 )
    usd? ( >=media-libs/openusd-24.08 )
    pdal? ( >=sci-libs/pdal-2.0.0 )
    draco? ( >=media-libs/draco-1.5.6 )
    openexr? ( >=media-libs/openexr-3.0.1 )
    webp? ( >=media-libs/libwebp-1.2.4 )
    java? ( >=virtual/jre-17:* )
    web-ifc? ( >=media-libs/web-ifc-0.75 )
    python? (
        ${PYTHON_DEPS}
        $(python_gen_cond_dep '
            >=dev-python/pybind11-2.9.2[${PYTHON_USEDEP}]
        ')
    )
"

DEPEND="
    ${RDEPEND}
    java? ( >=virtual/jdk-17:* )
"

BDEPEND="cuda? ( dev-util/nvidia-cuda-toolkit )"

pkg_setup() {
    use python && python-single-r1_pkg_setup
    use java && java-pkg-opt-2_pkg_setup
}

src_prepare() {
    cmake_src_prepare
    use cuda && cuda_src_prepare

    sed -i -E 's/int test_([a-zA-Z0-9_]+)\((void)?\)/int test_\1(int argc, char* argv[])/g' c/testing/*.c || die

    if use webp; then
        mkdir -p "${T}/cmake" || die
        cat <<-EOF > "${T}/cmake/WebPConfig.cmake" || die
            find_package(PkgConfig REQUIRED)
            pkg_check_modules(WebP REQUIRED GLOBAL IMPORTED_TARGET libwebp libwebpmux libwebpdemux)
            add_library(WebP::webp ALIAS PkgConfig::WebP)
            add_library(WebP::webpmux ALIAS PkgConfig::WebP)
            add_library(WebP::libwebpmux ALIAS PkgConfig::WebP)
            add_library(WebP::webpdemux ALIAS PkgConfig::WebP)
            set(WebP_FOUND TRUE)
EOF
    fi

    cat <<-EOF > "${T}/cmake/FindPEGTL.cmake" || die
		find_package(taocpp-pegtl CONFIG REQUIRED)
		set(PEGTL_FOUND TRUE)
EOF

    cat <<-EOF > "${T}/cmake/GentooInject.cmake" || die
        if(NOT GENTOO_INJECT_MACRO_SET)
            set(GENTOO_INJECT_MACRO_SET TRUE CACHE INTERNAL "Prevent macro recursion")
            macro(find_package _name)
                if("\${_name}" STREQUAL "PEGTL" AND TARGET taocpp::pegtl)
                    set(PEGTL_FOUND TRUE)
                else()
                    _find_package(\${ARGV})
                endif()
            endmacro()
        endif()

        find_package(OpenGL QUIET)
        find_package(glm QUIET)
        find_package(Ptex QUIET)
        find_package(spdlog QUIET)
        find_package(FastFloat QUIET)
        if(TARGET Ptex::Ptex AND NOT TARGET Ptex::Ptex_dynamic)
            add_library(Ptex::Ptex_dynamic ALIAS Ptex::Ptex)
        endif()
        if(TARGET spdlog::spdlog AND NOT TARGET spdlog::spdlog_header_only)
            add_library(spdlog::spdlog_header_only ALIAS spdlog::spdlog)
        endif()
EOF
}

src_configure() {
    local mycmakeargs=(
        -DBUILD_TESTING=$(usex test ON OFF)
        -DF3D_MODULE_RAYTRACING=$(usex raytracing)
        -DF3D_MODULE_EXR=$(usex openexr)
        -DF3D_MODULE_UI=$(usex imgui)
        -DF3D_MODULE_WEBP=$(usex webp)
        -DF3D_MODULE_CLIP=$(usex clipboard)
        -DF3D_PLUGIN_BUILD_HDF=$(usex hdf)
        -DF3D_PLUGIN_BUILD_OCCT=$(usex opencascade)
        -DF3D_PLUGIN_BUILD_ASSIMP=$(usex assimp)
        -DF3D_PLUGIN_BUILD_ALEMBIC=$(usex alembic)
        -DF3D_PLUGIN_BUILD_DRACO=$(usex draco)
        -DF3D_PLUGIN_BUILD_USD=$(usex usd)
        -DF3D_PLUGIN_BUILD_VDB=$(usex openvdb)
        -DF3D_PLUGIN_BUILD_PDAL=$(usex pdal)
        -DF3D_PLUGIN_BUILD_WEBIFC=$(usex web-ifc)
        -DF3D_BINDINGS_C=$(usex cxx)
        -DF3D_BINDINGS_JAVA=$(usex java)
        -DF3D_BINDINGS_PYTHON=$(usex python)
        -DF3D_BINDINGS_PYTHON_GENERATE_STUBS=OFF
        -DCMAKE_CUDA_HOST_COMPILER="$(cuda_gccdir)/gcc"
        -DCMAKE_PREFIX_PATH="${T}/cmake"
        -DCMAKE_MODULE_PATH="${T}/cmake"
        -DCMAKE_PROJECT_INCLUDE="${T}/cmake/GentooInject.cmake"
    )

    cmake_src_configure
}

src_install() {
    cmake_src_install

    if use python; then
        local libdir=$(get_libdir)
        if [[ "${libdir}" != "lib" && -d "${ED}/usr/${libdir}/${EPYTHON}" ]]; then
            mkdir -p "${ED}/usr/lib" || die
            mv "${ED}/usr/${libdir}/${EPYTHON}" "${ED}/usr/lib/" || die
        fi

        python_optimize
    fi
}
