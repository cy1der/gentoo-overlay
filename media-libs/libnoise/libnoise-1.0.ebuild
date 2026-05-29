# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake

DESCRIPTION="A general-purpose library that generates three-dimensional coherent noise modified for OrcaSlicer."
HOMEPAGE="https://github.com/SoftFever/Orca-deps-libnoise"
SRC_URI="https://github.com/SoftFever/Orca-deps-libnoise/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/Orca-deps-${PN}-${PV}"

LICENSE="LGPL-2.1+"
SLOT="0"
KEYWORDS="~amd64"