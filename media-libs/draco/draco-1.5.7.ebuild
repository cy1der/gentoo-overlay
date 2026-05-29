# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake

DESCRIPTION="Library for compressing and decompressing 3D geometric meshes and point clouds."
HOMEPAGE="https://google.github.io/draco"
SRC_URI="https://github.com/google/draco/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE="test"

RESTRICT="!test? ( test )"

src_configure() {
	local mycmakeargs=(
		-DBUILD_SHARED_LIBS=ON
		-DDRACO_TESTS=$(usex test)
		-DDRACO_TRANSCODER_SUPPORTED=OFF
	)
	cmake_src_configure
}