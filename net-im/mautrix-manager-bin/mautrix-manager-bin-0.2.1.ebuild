# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

MY_PN="${PN%-bin}"

DESCRIPTION="Electron app to help with logging into mautrix bridges"
HOMEPAGE="https://github.com/mautrix/manager"
SRC_URI="
	https://raw.githubusercontent.com/mautrix/manager/v${PV}/icon.png -> ${P}.png
	amd64? (
		https://github.com/mautrix/manager/releases/download/v${PV}/${MY_PN}-linux-x64-${PV}.zip
	)
	arm64? (
		https://github.com/mautrix/manager/releases/download/v${PV}/${MY_PN}-linux-arm64-${PV}.zip
	)
"
S="${WORKDIR}"

LICENSE="AGPL-3+"
# Bundled Electron/Chromium and node modules
LICENSE+=" BSD LGPL-2.1+ MIT MPL-2.0"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"

RESTRICT="strip test"

BDEPEND="app-arch/unzip"
RDEPEND="
	app-accessibility/at-spi2-core:2
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	dev-libs/openssl:0/3
	media-libs/alsa-lib
	media-libs/mesa[gbm(+)]
	net-print/cups
	sys-apps/dbus
	virtual/udev
	x11-libs/cairo
	x11-libs/gtk+:3
	x11-libs/libX11
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libxcb
	x11-libs/libxkbcommon
	x11-libs/pango
	x11-misc/xdg-utils
"

QA_PREBUILT="opt/${MY_PN}/*"

src_unpack() {
	local arch
	case ${ARCH} in
		amd64) arch=x64 ;;
		arm64) arch=arm64 ;;
	esac
	unpack ${MY_PN}-linux-${arch}-${PV}.zip
	mv ${MY_PN}-linux-${arch} ${MY_PN} || die
}

src_prepare() {
	default

	# The passkey module ships prebuilt copies for every platform; keep
	# only the one for this arch
	local arch
	case ${ARCH} in
		amd64) arch=x64 ;;
		arm64) arch=arm64 ;;
	esac
	find ${MY_PN}/resources/app.asar.unpacked/node_modules/@beeper \
		-name '*.node' ! -name "*.linux-${arch}-gnu.node" -delete || die

	rm ${MY_PN}/{LICENSE,LICENSES.chromium.html} || die
}

src_install() {
	insinto /opt
	doins -r ${MY_PN}

	local f
	pushd ${MY_PN} >/dev/null || die
	for f in ${MY_PN} chrome-sandbox chrome_crashpad_handler *.so *.so.*; do
		fperms +x /opt/${MY_PN}/${f}
	done
	popd >/dev/null || die
	fperms u+s /opt/${MY_PN}/chrome-sandbox

	dosym ../../opt/${MY_PN}/${MY_PN} /usr/bin/${MY_PN}

	newicon -s 256 "${DISTDIR}"/${P}.png ${MY_PN}.png
	make_desktop_entry "${MY_PN} %u" mautrix-manager ${MY_PN} "Network;Chat;" \
		"MimeType=x-scheme-handler/${MY_PN};"
}
