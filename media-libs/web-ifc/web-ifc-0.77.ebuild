# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake

# Bundled third-party code
TINYNURBS_COMMIT="47115cd9b6e922b27bbc4ab01fdeac2e9ea597a4"
EARCUT_COMMIT="4811a2b69b91f6127a75e780de6e2113609ddabb"
CDT_COMMIT="4d0c9026b8ec846fe544897e7111f8f9080d5f8a"
STDUUID_COMMIT="3afe7193facd5d674de709fccc44d5055e144d7a"
UNORDERED_DENSE_COMMIT="3234af2c03549bc85656bfd3a86993bf1cd8aef1"
TINYCPPTEST_COMMIT="12e42c8ac6e032ce450fb3f772ebdfd1ddc6008c"

DESCRIPTION="Native C++ library for reading/writing IFC (from engine_web-ifc)"
HOMEPAGE="https://github.com/ThatOpen/engine_web-ifc"
SRC_URI="
	https://github.com/ThatOpen/engine_web-ifc/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz
	https://github.com/QuimMoya/tinynurbs/archive/${TINYNURBS_COMMIT}.tar.gz
		-> tinynurbs-${TINYNURBS_COMMIT}.tar.gz
	https://github.com/mapbox/earcut.hpp/archive/${EARCUT_COMMIT}.tar.gz
		-> earcut.hpp-${EARCUT_COMMIT}.tar.gz
	https://github.com/artem-ogre/CDT/archive/${CDT_COMMIT}.tar.gz
		-> CDT-${CDT_COMMIT}.tar.gz
	https://github.com/mariusbancila/stduuid/archive/${STDUUID_COMMIT}.tar.gz
		-> stduuid-${STDUUID_COMMIT}.tar.gz
	https://github.com/martinus/unordered_dense/archive/${UNORDERED_DENSE_COMMIT}.tar.gz
		-> unordered_dense-${UNORDERED_DENSE_COMMIT}.tar.gz
	test? (
		https://github.com/kovacsv/TinyCppTest/archive/${TINYCPPTEST_COMMIT}.tar.gz
			-> TinyCppTest-${TINYCPPTEST_COMMIT}.tar.gz
	)
"
S="${WORKDIR}/engine_web-ifc-${PV}/src/cpp"

LICENSE="MPL-2.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE="test"

DEPEND="
	media-libs/glm
	dev-libs/spdlog
	dev-cpp/fast_float
"
RDEPEND="${DEPEND}"
BDEPEND="virtual/pkgconfig"

RESTRICT="!test? ( test )"

PATCHES=(
	"${FILESDIR}"/${PN}-0.77-no-fetchcontent.patch
)

src_prepare() {
	cmake_src_prepare

	mkdir -p "${S}/third_party" || die

	rm -rf "${S}/third_party/tinynurbs" || die
	mv "${WORKDIR}/tinynurbs-${TINYNURBS_COMMIT}" "${S}/third_party/tinynurbs" || die

	rm -rf "${S}/third_party/earcut.hpp" || die
	mv "${WORKDIR}/earcut.hpp-${EARCUT_COMMIT}" "${S}/third_party/earcut.hpp" || die

	rm -rf "${S}/third_party/CDT" || die
	mv "${WORKDIR}/CDT-${CDT_COMMIT}" "${S}/third_party/CDT" || die

	rm -rf "${S}/third_party/stduuid" || die
	mv "${WORKDIR}/stduuid-${STDUUID_COMMIT}" "${S}/third_party/stduuid" || die

	rm -rf "${S}/third_party/unordered_dense" || die
	mv "${WORKDIR}/unordered_dense-${UNORDERED_DENSE_COMMIT}" "${S}/third_party/unordered_dense" || die

	if use test; then
		rm -rf "${S}/third_party/TinyCppTest" || die
		mv "${WORKDIR}/TinyCppTest-${TINYCPPTEST_COMMIT}" "${S}/third_party/TinyCppTest" || die
	fi
}

src_configure() {
	CMAKE_BUILD_TYPE=Release

	local mycmakeargs=(
		-DBUILD_TESTING=$(usex test)
		-DCMAKE_POSITION_INDEPENDENT_CODE=ON
	)

	cmake_src_configure
}

src_test() {
	ctest --test-dir "${BUILD_DIR}" --output-on-failure || die
}

src_install() {
	cmake_src_install

	insinto /usr/include/mapbox
	doins "${S}/third_party/earcut.hpp/include/mapbox/earcut.hpp"
}
