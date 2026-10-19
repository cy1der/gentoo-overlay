# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{9..14} )

inherit cmake python-single-r1

DESCRIPTION="Universal Scene Description"
HOMEPAGE="https://openusd.org/"
SRC_URI="https://github.com/PixarAnimationStudios/OpenUSD/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/OpenUSD-${PV}"

LICENSE="TOST-1.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE="alembic doc draco embree +examples hdf +imaging materialx opencolorio openimageio +opengl osl ptex +python test +tools +usdview"
REQUIRED_USE="
	python? ( ${PYTHON_REQUIRED_USE} )
	embree? ( imaging )
	opencolorio? ( imaging )
	openimageio? ( imaging )
	ptex? ( imaging )
	tools? ( python )
	usdview? ( imaging opengl python )
	hdf? ( alembic )
"

RESTRICT="!test? ( test )"

RDEPEND="
	>=dev-cpp/tbb-2020.3
	python? (
		${PYTHON_DEPS}
		$(python_gen_cond_dep '
			dev-python/numpy[${PYTHON_USEDEP}]
		')
	)
	imaging? ( >=media-libs/opensubdiv-3.6.1 )
	usdview? (
		>=dev-python/pyside-6.3.1
		>=dev-python/pyopengl-3.1.5
	)
	opengl? ( virtual/opengl )
	materialx? ( >=media-libs/materialx-1.39.4 )
	osl? ( >=media-libs/osl-1.13.11 )
	ptex? ( >=media-libs/ptex-2.4.2 )
	openimageio? ( >=media-libs/openimageio-2.5.16.0 )
	opencolorio? ( >=media-libs/opencolorio-2.2.1 )
	embree? ( >=media-libs/embree-4.3.3 )
	alembic? (
		hdf? ( sci-libs/hdf5 )
		>=media-gfx/alembic-1.8.5
		>=media-libs/openexr-3.1.13
	)
	draco? ( >=media-libs/draco-1.5.6 )
"

DEPEND="${RDEPEND}"

BDEPEND="
	doc? (
		app-text/doxygen
		media-gfx/graphviz
	)
"

src_prepare() {
	cmake_src_prepare

	local flags='CMAKE_CXX_FLAGS_${config} ${CMAKE_CXX_FLAGS_${config}}'
	local quoted='CMAKE_CXX_FLAGS_${config} "${CMAKE_CXX_FLAGS_${config}}"'
	sed -i -e "s|${flags}|${quoted}|g" \
		pxr/external/boost/python/CMakeLists.txt || die "Failed to patch Boost.Python CMakeLists"
}

src_configure() {
	use python && python_setup

	# Create a mock pyside6-uic to work around Gentoo's PySide6 libexec path and whatnot
	if use usdview; then
		local qt6_libexec

		for d in /usr/lib64/qt6/libexec /usr/lib/qt6/libexec /usr/libexec/qt6; do
			if [[ -x "${d}/uic" ]]; then
				qt6_libexec="${d}"
				break
			fi
		done

		if [[ -z "${qt6_libexec}" ]]; then
			die "Could not find Qt6 uic. Ensure dev-qt/qtbase:6 is properly installed."
		fi

		mkdir -p "${T}/bin" || die

		cat > "${T}/bin/pyside6-uic" <<EOF || die
#!/bin/sh
exec "${qt6_libexec}/uic" -g python "\$@"
EOF
		chmod +x "${T}/bin/pyside6-uic" || die

		export PATH="${T}/bin:${PATH}"
	fi

	local mycmakeargs=(
		-DPXR_BUILD_TESTS=$(usex test)
		-DPXR_BUILD_DOCUMENTATION=$(usex doc)
		-DPXR_BUILD_USD_TOOLS=$(usex tools)
		-DPXR_BUILD_EXAMPLES=$(usex examples)
		-DPXR_BUILD_TUTORIALS=$(usex examples)
		-DPXR_BUILD_IMAGING=$(usex imaging)
		-DPXR_BUILD_USDVIEW=$(usex usdview)
		-DPXR_BUILD_OPENIMAGEIO_PLUGIN=$(usex openimageio)
		-DPXR_BUILD_OPENCOLORIO_PLUGIN=$(usex opencolorio)
		-DPXR_BUILD_EMBREE_PLUGIN=$(usex embree)
		-DPXR_BUILD_ALEMBIC_PLUGIN=$(usex alembic)
		-DPXR_BUILD_DRACO_PLUGIN=$(usex draco)
		-DPXR_ENABLE_HDF5_SUPPORT=$(usex hdf)
		-DPXR_ENABLE_GL_SUPPORT=$(usex opengl)
		-DPXR_ENABLE_PTEX_SUPPORT=$(usex ptex)
		-DPXR_ENABLE_OSL_SUPPORT=$(usex osl)
		-DPXR_ENABLE_MATERIALX_SUPPORT=$(usex materialx)
		-DPXR_ENABLE_PYTHON_SUPPORT=$(usex python)
	)

	cmake_src_configure
}

src_install() {
	cmake_src_install

	if [[ -d "${ED}/usr/docs" ]]; then
		if use doc; then
			dodoc -r "${ED}/usr/docs/"*
		fi
		rm -r "${ED}/usr/docs" || die
	fi

	if [[ -d "${ED}/usr/tests" ]]; then
		rm -r "${ED}/usr/tests" || die
	fi

	sed -i 's|cmake/pxrTargets.cmake|pxrTargets.cmake|g' "${ED}/usr/pxrConfig.cmake" || die

	# Two more levels up, as pxrTargets.cmake moves out of cmake/
	local up='get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)'
	sed -i "s|${up}|${up}\n${up}\n${up}|" "${ED}/usr/cmake/pxrTargets.cmake" || die

	local libdir=$(get_libdir)

	if [[ "${libdir}" != "lib" && -d "${ED}/usr/lib" ]]; then
		mkdir -p "${ED}/usr/${libdir}" || die

		mv "${ED}"/usr/lib/libusd* "${ED}/usr/${libdir}/" || die

		sed -i -e "s|/usr/lib/|/usr/${libdir}/|g" \
				-e "s|\${_IMPORT_PREFIX}/lib/|\${_IMPORT_PREFIX}/${libdir}/|g" \
				-e "s|/usr/${libdir}/python|/usr/lib/python|g" \
			"${ED}/usr/pxrConfig.cmake" \
			"${ED}"/usr/cmake/*.cmake || die
	fi

	insinto /usr/${libdir}/cmake/pxr
	doins "${ED}/usr/pxrConfig.cmake"
	doins -r "${ED}"/usr/cmake/*
	rm "${ED}/usr/pxrConfig.cmake" || die
	rm -r "${ED}/usr/cmake" || die

	insinto /usr/share/usd/plugin
	doins -r "${ED}"/usr/plugin/*
	rm -r "${ED}"/usr/plugin || die

	cat > "${T}/99openusd" <<-EOF
		PXR_PLUGINPATH_NAME="/usr/share/usd/plugin"
	EOF
	doenvd "${T}/99openusd"
}
