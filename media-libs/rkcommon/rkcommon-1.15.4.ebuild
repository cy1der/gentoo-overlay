# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake

DESCRIPTION="Intel® RenderKit common C++/CMake infrastructure"
HOMEPAGE="https://github.com/RenderKit/rkcommon"
SRC_URI="https://github.com/RenderKit/rkcommon/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"

PATCHES=(
	"${FILESDIR}"/${PN}-1.15.2-fix-type-punning.patch
)

RDEPEND=">=dev-cpp/tbb-4.4.3"
DEPEND="${RDEPEND}"
