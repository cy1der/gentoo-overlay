# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_SINGLE_IMPL=true
DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{11..14} )

inherit distutils-r1 systemd

DESCRIPTION="Proton VPN daemon providing split tunneling"
HOMEPAGE="https://github.com/ProtonVPN/proton-vpn-daemon"
SRC_URI="https://github.com/ProtonVPN/proton-vpn-daemon/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="~amd64"
# Tests need root and a kernel that can load eBPF programs
RESTRICT="test"

PATCHES=(
	"${FILESDIR}"/${PN}-0.13.8-cgroup-without-systemd.patch
	"${FILESDIR}"/${PN}-0.13.8-dbus-fixes.patch
)

# systemd-python is listed upstream but never imported
RDEPEND="
	sys-apps/dbus
	$(python_gen_cond_dep '
		>=dev-util/bcc-0.26.0[python,${PYTHON_USEDEP}]
		dev-python/dbus-fast[${PYTHON_USEDEP}]
		dev-python/packaging[${PYTHON_USEDEP}]
		>=dev-python/proton-vpn-api-core-5.3.1[${PYTHON_USEDEP}]
		dev-python/psutil[${PYTHON_USEDEP}]
	')
"

src_prepare() {
	distutils-r1_src_prepare

	sed -i "/--cov/d" setup.cfg || die
	sed -i "s|^Exec=.*|Exec=${EPREFIX}/usr/bin/${EPYTHON} -m proton.vpn.daemon|" \
		rpmbuild/SOURCES/dbus.service || die
	sed -i "s|^ExecStart=.*|ExecStart=${EPREFIX}/usr/bin/${EPYTHON} -m proton.vpn.daemon|" \
		rpmbuild/SOURCES/systemd.service || die
}

src_install() {
	distutils-r1_src_install

	insinto /usr/share/dbus-1/system.d
	newins rpmbuild/SOURCES/dbus.conf me.proton.vpn.split_tunneling.conf

	insinto /usr/share/dbus-1/system-services
	newins rpmbuild/SOURCES/dbus.service me.proton.vpn.split_tunneling.service

	systemd_newunit rpmbuild/SOURCES/systemd.service me.proton.vpn.split_tunneling.service

	sed "s|@PYTHON@|${EPREFIX}/usr/bin/${EPYTHON}|" "${FILESDIR}/${PN}.initd" > "${T}/${PN}" || die
	doinitd "${T}/${PN}"
}

pkg_postinst() {
	elog "The Proton VPN app only offers split tunneling while this daemon is running."
	elog "OpenRC:  rc-update add ${PN} default && rc-service ${PN} start"
	elog "systemd: systemctl enable --now me.proton.vpn.split_tunneling.service"
}
