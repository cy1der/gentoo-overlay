# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

# This is a copy of dev-python/proton-keyring-linux-0.2.1::guru bumped to the latest version,
# with dependencies for the new libsecret backend

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{11..14} )

inherit distutils-r1

DESCRIPTION="Proton Technologies keyring plugins for linux"
HOMEPAGE="https://github.com/ProtonVPN/python-proton-keyring-linux"
SRC_URI="https://github.com/ProtonVPN/python-proton-keyring-linux/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/python-${P}"
LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="~amd64"
IUSE="test"
RESTRICT="!test? ( test )"

RDEPEND="
	dev-python/keyring[${PYTHON_USEDEP}]
	dev-python/proton-core[${PYTHON_USEDEP}]
	app-crypt/libsecret[introspection]
	dev-python/pygobject[${PYTHON_USEDEP}]
	virtual/secret-service
"

distutils_enable_tests pytest

src_prepare() {
	distutils-r1_src_prepare

	sed -i "/--cov/d" setup.cfg || die
}
