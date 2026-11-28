# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop java-pkg-2 optfeature xdg

MY_PN="${PN%-bin}"
MY_JAR="${MY_PN}-${PV}-all.jar"

# The GUI needs these at run time. Upstream's launcher downloads them on first
# start; install them instead. Versions come from BootstrapConstants in the
# release jar, src_unpack checks they match.
SKIKO_PV="0.150.2"
JNA_PV="5.19.1"
OSHI_PV="7.8.0"

MAVEN="https://repo1.maven.org/maven2"

DESCRIPTION="Desktop app and CLI for patching Android apps with Morphe"
HOMEPAGE="https://morphe.software/ https://github.com/MorpheApp/morphe-desktop"
SRC_URI="
	https://github.com/MorpheApp/${MY_PN}/releases/download/v${PV}/${MY_JAR}
	${MAVEN}/org/jetbrains/skiko/skiko-awt/${SKIKO_PV}/skiko-awt-${SKIKO_PV}.jar
	amd64? (
		${MAVEN}/org/jetbrains/skiko/skiko-awt-runtime-linux-x64/${SKIKO_PV}/skiko-awt-runtime-linux-x64-${SKIKO_PV}.jar
	)
	arm64? (
		${MAVEN}/org/jetbrains/skiko/skiko-awt-runtime-linux-arm64/${SKIKO_PV}/skiko-awt-runtime-linux-arm64-${SKIKO_PV}.jar
	)
	${MAVEN}/net/java/dev/jna/jna/${JNA_PV}/jna-${JNA_PV}.jar
	${MAVEN}/net/java/dev/jna/jna-platform/${JNA_PV}/jna-platform-${JNA_PV}.jar
	${MAVEN}/com/github/oshi/oshi-core/${OSHI_PV}/oshi-core-${OSHI_PV}.jar
	${MAVEN}/com/github/oshi/oshi-common/${OSHI_PV}/oshi-common-${OSHI_PV}.jar
"
S="${WORKDIR}"

LICENSE="GPL-3 Apache-2.0 BSD MIT || ( Apache-2.0 LGPL-2.1+ )"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"

RDEPEND=">=virtual/jre-21:*"
BDEPEND="app-arch/unzip"

# Runtime jars in upstream's classpath order.
morphe_libs() {
	local target
	use amd64 && target=linux-x64
	use arm64 && target=linux-arm64
	echo \
		skiko-awt-runtime-${target}-${SKIKO_PV}.jar \
		skiko-awt-${SKIKO_PV}.jar \
		jna-${JNA_PV}.jar \
		jna-platform-${JNA_PV}.jar \
		oshi-core-${OSHI_PV}.jar \
		oshi-common-${OSHI_PV}.jar
}

src_unpack() {
	unzip -q "${DISTDIR}/${MY_JAR}" \
		app/morphe/engine/BootstrapConstants.class morphe_logo.png || die

	# Upstream pins each runtime jar by SHA-256. A bump that changes them
	# has to update the versions above.
	local jar sum
	for jar in $(morphe_libs); do
		sum=$(sha256sum "${DISTDIR}/${jar}" | cut -d' ' -f1) || die
		grep -aqF "${sum}" app/morphe/engine/BootstrapConstants.class \
			|| die "${MY_JAR} doesn't expect ${jar}, update the versions"
	done
}

src_install() {
	java-pkg_newjar "${DISTDIR}/${MY_JAR}" ${MY_PN}.jar

	# DISTDIR has symlinks, which java-pkg_dojar would install as such
	local jar
	for jar in $(morphe_libs); do
		java-pkg_newjar "${DISTDIR}/${jar}" "${jar%-*}.jar"
	done

	java-pkg_dolauncher morphe \
		--main app.morphe.MorpheLauncherKt \
		--java_args "--enable-native-access=ALL-UNNAMED" \
		-pre "${FILESDIR}"/morphe-launcher-pre.bash

	newicon morphe_logo.png morphe.png
	make_desktop_entry morphe Morphe morphe "Development;" \
		"StartupWMClass=app-morphe-MorpheLauncherKt"
}

pkg_postinst() {
	xdg_pkg_postinst
	optfeature "installing patched apps on a device over ADB" dev-util/android-tools
}
