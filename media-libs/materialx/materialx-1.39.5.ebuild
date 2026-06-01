# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{9..14} )

inherit cmake python-single-r1 git-r3

DESCRIPTION="Open standard for the exchange of rich material and look-development content across applications and renderers."
HOMEPAGE="https://materialx.org/"
EGIT_REPO_URI="https://github.com/AcademySoftwareFoundation/MaterialX.git"
EGIT_COMMIT="v${PV}"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE="doc viewer graph-editor opencolorio openimageio python"
REQUIRED_USE="python? ( ${PYTHON_REQUIRED_USE} )"

RDEPEND="
    python? (
        ${PYTHON_DEPS}
        $(python_gen_cond_dep '
            >=dev-python/pybind11-2.12.0[${PYTHON_USEDEP}]
        ')
    )
    openimageio? ( >=media-libs/openimageio-2.2 )
    opencolorio? ( >=media-libs/opencolorio-2.4 )
    viewer? ( virtual/opengl )
    graph-editor? ( virtual/opengl )
"

DEPEND="${RDEPEND}"

BDEPEND="
    doc? ( app-text/doxygen )
"

src_prepare() {
    cmake_src_prepare

    # Fix sandbox violation
    if use python; then
        sed -i -e 's|${CMAKE_INSTALL_PREFIX}/python|${CMAKE_CURRENT_BINARY_DIR}/python|g' \
            python/CMakeLists.txt || die "Failed to patch python/CMakeLists.txt"
    fi
}

src_configure() {
	local mycmakeargs=(
        -DMATERIALX_BUILD_PYTHON=$(usex python)
        -DMATERIALX_BUILD_DOCS=$(usex doc)
        -DMATERIALX_BUILD_VIEWER=$(usex viewer)
        -DMATERIALX_BUILD_GRAPH_EDITOR=$(usex graph-editor)
        -DMATERIALX_BUILD_OIIO=$(usex openimageio)
        -DMATERIALX_BUILD_OCIO=$(usex opencolorio)
	)

	cmake_src_configure
}

src_install() {
    cmake_src_install

    if [[ -d "${ED}/usr/documents" ]]; then
        dodoc -r "${ED}/usr/documents/"*
        rm -r "${ED}/usr/documents" || die
    fi

    dodoc "${ED}/usr/CHANGELOG.md" "${ED}/usr/README.md" "${ED}/usr/THIRD-PARTY.md"
    rm "${ED}/usr/CHANGELOG.md" "${ED}/usr/README.md" "${ED}/usr/THIRD-PARTY.md" "${ED}/usr/LICENSE" || die

    insinto /usr/share/${PN}
    doins -r "${ED}/usr/libraries" "${ED}/usr/resources"
    rm -r "${ED}/usr/libraries" "${ED}/usr/resources" || die

    sed -i \
        -e 's|PACKAGE_PREFIX_DIR}/libraries|PACKAGE_PREFIX_DIR}/share/'"${PN}"'/libraries|g' \
        -e 's|PACKAGE_PREFIX_DIR}/resources|PACKAGE_PREFIX_DIR}/share/'"${PN}"'/resources|g' \
        -e 's|"/usr/libraries"|"/usr/share/'"${PN}"'/libraries"|g' \
        -e 's|"/usr/resources"|"/usr/share/'"${PN}"'/resources"|g' \
        "${ED}"/usr/lib*/cmake/MaterialX/MaterialXConfig.cmake || die

    if use python; then
        python_domodule "${ED}/usr/python/"*
        rm -r "${ED}/usr/python" || die

        local pysitedir=$(python_get_sitedir)

        sed -i \
            -e 's|${PACKAGE_PREFIX_DIR}/python|'"${pysitedir}"'|g' \
            -e 's|/usr/python|'"${pysitedir}"'|g' \
            "${ED}"/usr/lib*/cmake/MaterialX/MaterialXConfig.cmake
    fi
}