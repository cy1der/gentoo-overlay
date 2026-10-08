# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# This is a copy of dev-python/proton-vpn-api-core-4.19.1::guru with an added patch to remove calls to apt

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{11..14} )

inherit distutils-r1

DESCRIPTION="Proton AG VPN Core API"
HOMEPAGE="https://github.com/ProtonVPN/python-proton-vpn-api-core"

SRC_URI="
	https://github.com/ProtonVPN/python-proton-vpn-api-core/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
"

S="${WORKDIR}/python-${P}"
LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="~amd64"
IUSE="test"
RESTRICT="!test? ( test )"

PATCHES=(
	"${FILESDIR}/${P}-remove-calls-to-apt.patch"
)

BDEPEND="test? ( dev-python/pytest-asyncio[${PYTHON_USEDEP}] )"

# sentry-sdk is only imported when crash reporting is enabled
RDEPEND="
	net-misc/networkmanager[introspection]
	net-vpn/networkmanager-openvpn
	dev-python/cryptography[${PYTHON_USEDEP}]
	dev-python/distro[${PYTHON_USEDEP}]
	dev-python/fido2[${PYTHON_USEDEP}]
	dev-python/jinja2[${PYTHON_USEDEP}]
	dev-python/packaging[${PYTHON_USEDEP}]
	>=dev-python/proton-core-0.5.0[${PYTHON_USEDEP}]
	>=dev-python/proton-vpn-local-agent-1.5.0[${PYTHON_USEDEP}]
	dev-python/pycairo[${PYTHON_USEDEP}]
	dev-python/pygobject[${PYTHON_USEDEP}]
	dev-python/pynacl[${PYTHON_USEDEP}]
"

distutils_enable_sphinx docs
distutils_enable_tests pytest

src_prepare() {
	distutils-r1_src_prepare

	sed -i "/--cov/d" setup.cfg || die
}

python_test() {
	# VPN connection cannot be tested within sandbox
	local EPYTEST_IGNORE=(
		tests/connection
		tests/core/refresher
		tests/core/test_{connection,settings}.py
	)

	XDG_RUNTIME_DIR="${T}/python_test" epytest
}