# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake flag-o-matic

DESCRIPTION="Intel® Open Volume Kernel Library is a collection of high performance volume computation kernels."
HOMEPAGE="https://openvkl.org/"
SRC_URI="https://github.com/RenderKit/openvkl/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="
    >=dev-lang/ispc-1.18.0
    media-libs/embree
    media-libs/rkcommon
"

DEPEND="${RDEPEND}"

src_configure() {
	filter-lto

	cmake_src_configure
}