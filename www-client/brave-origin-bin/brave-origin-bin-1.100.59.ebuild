# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CHROMIUM_LANGS="af am ar az bg bn bs ca cs da de el en-GB es es-419 et fa fi
	fil fr gu he hi hr hu id it ja ka kk km kn ko lo lt lv mk ml mn mr ms my nb
	nl pl pt-BR pt-PT ro ru si sk sl sq sr sr-Latn sv sw ta te th tr uk ur uz vi
	zh-CN zh-TW"

VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/brave.asc
inherit chromium-2 desktop pax-utils unpacker verify-sig xdg

MY_PN=${PN%-bin}

DESCRIPTION="Brave web browser without Rewards, Wallet, VPN, Leo AI and other extras"
HOMEPAGE="
	https://brave.com/origin/
	https://github.com/brave/brave-browser
"
SRC_URI="
	amd64? (
		https://github.com/brave/brave-browser/releases/download/v${PV}/${MY_PN}_${PV}_amd64.deb
		verify-sig? (
			https://github.com/brave/brave-browser/releases/download/v${PV}/${MY_PN}_${PV}_amd64.deb.sha256
			https://github.com/brave/brave-browser/releases/download/v${PV}/${MY_PN}_${PV}_amd64.deb.sha256.asc
		)
	)
	arm64? (
		https://github.com/brave/brave-browser/releases/download/v${PV}/${MY_PN}_${PV}_arm64.deb
		verify-sig? (
			https://github.com/brave/brave-browser/releases/download/v${PV}/${MY_PN}_${PV}_arm64.deb.sha256
			https://github.com/brave/brave-browser/releases/download/v${PV}/${MY_PN}_${PV}_arm64.deb.sha256.asc
		)
	)
"
S=${WORKDIR}

LICENSE="MPL-2.0"
# Bundled Chromium and its third-party code, see brave://credits
LICENSE+=" Apache-2.0 BSD BSD-2 LGPL-2.1+ MIT Unicode-3.0"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
IUSE="qt6 selinux +telemetry"

# Built with the H.264 and AAC decoders
RESTRICT="bindist strip"

BDEPEND="verify-sig? ( >=sec-keys/openpgp-keys-brave-20250709 )"
RDEPEND="
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-misc/ca-certificates
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	>=dev-libs/nss-3.26
	media-fonts/liberation-fonts
	media-libs/alsa-lib
	media-libs/mesa[gbm(+)]
	net-misc/curl
	net-print/cups
	sys-apps/dbus
	sys-libs/libcap
	virtual/libudev
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	|| (
		x11-libs/gtk+:3[X]
		gui-libs/gtk:4[X]
	)
	x11-libs/libdrm
	>=x11-libs/libX11-1.5.0
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libxcb
	x11-libs/libxkbcommon
	x11-libs/libxshmfence
	x11-libs/pango
	x11-misc/xdg-utils
	qt6? ( dev-qt/qtbase:6[gui,widgets] )
	selinux? ( sec-policy/selinux-chromium )
"

QA_PREBUILT="*"

pkg_setup() {
	chromium_suid_sandbox_check_kernel_config
}

src_unpack() {
	# Upstream signs the .sha256 file, not the .deb itself
	if use verify-sig; then
		local deb=${MY_PN}_${PV}_${ARCH}.deb
		verify-sig_verify_detached "${DISTDIR}"/${deb}.sha256{,.asc}
		# The here-string adds the final newline the file lacks, without
		# which the last (and only) line would be skipped
		pushd "${DISTDIR}" >/dev/null || die
		verify-sig_verify_unsigned_checksums - sha256 ${deb} <<<"$(<${deb}.sha256)"
		popd >/dev/null || die
	fi
}

src_install() {
	local home=opt/brave.com/${MY_PN}

	dodir /
	cd "${ED}" || die
	unpacker ${MY_PN}_${PV}_${ARCH}.deb

	# The daily cron job only maintains the apt repository
	rm -r etc "${home}"/cron || die

	mv usr/share/{appdata,metainfo} || die

	mv usr/share/doc/${MY_PN} usr/share/doc/${PF} || die
	rmdir usr/share/doc/${MY_PN}-stable || die
	gzip -d usr/share/doc/${PF}/changelog.gz || die
	gzip -d usr/share/man/man1/${MY_PN}-stable.1.gz || die
	rm usr/share/man/man1/${MY_PN}.1.gz || die
	dosym ${MY_PN}-stable.1 /usr/share/man/man1/${MY_PN}.1

	# Debian's postinst adds this through update-alternatives
	dosym ${MY_PN}-stable /usr/bin/${MY_PN}

	# Accept the free tier (Linux only) instead of asking on first start
	sed -i 's|"$HERE/brave" "$@"|"$HERE/brave" --skip-origin-startup-dialog "$@"|' "${home}"/${MY_PN} || die
	grep -q -- --skip-origin-startup-dialog "${home}"/${MY_PN} || die "the ${MY_PN} wrapper changed"

	pushd "${home}"/locales >/dev/null || die
	chromium_remove_language_paks
	popd >/dev/null || die

	rm "${home}"/libqt5_shim.so || die
	if ! use qt6; then
		rm "${home}"/libqt6_shim.so || die
	fi

	local size
	for size in 16 24 32 48 64 128 256; do
		newicon -s ${size} "${home}"/product_logo_${size}.png ${MY_PN}.png
	done

	pax-mark m "${home}"/brave

	# Only used when unprivileged user namespaces are unavailable
	fperms 4711 /${home}/chrome-sandbox

	# Every Brave build reads /etc/brave/policies, not just Origin
	if ! use telemetry; then
		insinto /etc/brave/policies/managed
		newins "${FILESDIR}"/no-telemetry.json ${PN}-no-telemetry.json
	fi
}
