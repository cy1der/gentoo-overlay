# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{9..14} )

inherit cmake python-single-r1

# Git submodules, which the release tarball doesn't include
NANOGUI_COMMIT="6452dd6944d2ba5c0c9bc0042a1894f703ce1ace"
NANOVG_COMMIT="bf2320d1175122374a9b806d91e9e666c9336375"
GLFW_COMMIT="e130e55a990998c78fd323f21076e798e0efe8a4"
IMGUI_COMMIT="9aae45eb4a05a5a1f96be1ef37eb503a12ceb889"
IMGUI_NODE_EDITOR_COMMIT="2f99b2d613a400f6579762bd7e7c343a0d844158"

DESCRIPTION="Open standard for exchanging rich material and look-development content"
HOMEPAGE="https://materialx.org/"
SRC_URI="
	https://github.com/AcademySoftwareFoundation/MaterialX/releases/download/v${PV}/MaterialX-${PV}.tar.gz
	viewer? (
		https://github.com/mitsuba-renderer/nanogui/archive/${NANOGUI_COMMIT}.tar.gz
			-> nanogui-${NANOGUI_COMMIT}.tar.gz
		https://github.com/wjakob/nanovg/archive/${NANOVG_COMMIT}.tar.gz
			-> nanovg-${NANOVG_COMMIT}.tar.gz
		https://github.com/wjakob/glfw/archive/${GLFW_COMMIT}.tar.gz
			-> glfw-${GLFW_COMMIT}.tar.gz
	)
	graph-editor? (
		https://github.com/ocornut/imgui/archive/${IMGUI_COMMIT}.tar.gz
			-> imgui-${IMGUI_COMMIT}.tar.gz
		https://github.com/thedmd/imgui-node-editor/archive/${IMGUI_NODE_EDITOR_COMMIT}.tar.gz
			-> imgui-node-editor-${IMGUI_NODE_EDITOR_COMMIT}.tar.gz
	)
"
S="${WORKDIR}/MaterialX-${PV}"

LICENSE="Apache-2.0 graph-editor? ( MIT ZLIB ) viewer? ( BSD ZLIB )"
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
	if use viewer; then
		local nanogui="${S}/source/MaterialXView/NanoGUI"
		rm -rf "${nanogui}" || die
		mv "${WORKDIR}/nanogui-${NANOGUI_COMMIT}" "${nanogui}" || die
		rm -rf "${nanogui}"/ext/{nanovg,glfw} || die
		mv "${WORKDIR}/nanovg-${NANOVG_COMMIT}" "${nanogui}/ext/nanovg" || die
		mv "${WORKDIR}/glfw-${GLFW_COMMIT}" "${nanogui}/ext/glfw" || die
	fi

	if use graph-editor; then
		local external="${S}/source/MaterialXGraphEditor/External"
		rm -rf "${external}"/{ImGui,ImGuiNodeEditor} || die
		mv "${WORKDIR}/imgui-${IMGUI_COMMIT}" "${external}/ImGui" || die
		mv "${WORKDIR}/imgui-node-editor-${IMGUI_NODE_EDITOR_COMMIT}" "${external}/ImGuiNodeEditor" || die
	fi

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
