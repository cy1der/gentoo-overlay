# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MY_PN=VulkanMemoryAllocator
inherit cmake

DESCRIPTION="Easy to integrate Vulkan memory allocation library"
HOMEPAGE="https://gpuopen.com/vulkan-memory-allocator/"
SRC_URI="https://github.com/GPUOpen-LibrariesAndSDKs/${MY_PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${MY_PN}-${PV}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64 ~x86"

RDEPEND="dev-util/vulkan-headers"

src_configure() {
	local mycmakeargs=(
		-DVMA_BUILD_DOCUMENTATION=OFF
		-DVMA_BUILD_SAMPLES=OFF
		-DVMA_ENABLE_INSTALL=ON
	)
	cmake_src_configure
}
