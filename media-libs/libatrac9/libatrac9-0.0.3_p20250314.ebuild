# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit toolchain-funcs

COMMIT="efca2e3af35562a09a9bb6deed90e45b4b824dc4"

DESCRIPTION="Decoder for Sony's ATRAC9 audio codec"
HOMEPAGE="https://github.com/Thealexbarney/LibAtrac9"
SRC_URI="https://github.com/Thealexbarney/LibAtrac9/archive/${COMMIT}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/LibAtrac9-${COMMIT}/C"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~x86"

src_compile() {
	# The Makefile hardcodes -O2, -flto and -s and sets no soname
	emake shared \
		CC="$(tc-getCC)" \
		SFLAGS="${CFLAGS}" \
		SHARED_SFLAGS="${CFLAGS}" \
		LDFLAGS="${LDFLAGS} -shared -Wl,--version-script=libatrac9.version -Wl,-soname,libatrac9.so.0"
}

src_install() {
	newlib.so bin/libatrac9.so libatrac9.so.0
	dosym libatrac9.so.0 /usr/$(get_libdir)/libatrac9.so

	insinto /usr/include/libatrac9
	doins src/libatrac9.h

	insinto /usr/$(get_libdir)/pkgconfig
	newins - libatrac9.pc <<-EOT
		prefix=${EPREFIX}/usr
		libdir=\${prefix}/$(get_libdir)
		includedir=\${prefix}/include/libatrac9

		Name: libatrac9
		Description: ${DESCRIPTION}
		Version: ${PV}
		Libs: -L\${libdir} -latrac9
		Cflags: -I\${includedir}
	EOT
}
