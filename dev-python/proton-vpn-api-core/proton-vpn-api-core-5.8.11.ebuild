# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_EXT=1
DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{11..14} )
RUST_MIN_VER="1.88.0"

CRATES="
	aead@0.5.2
	aho-corasick@1.1.4
	anstream@1.0.0
	anstyle-parse@1.0.0
	anstyle-query@1.1.5
	anstyle-wincon@3.0.11
	anstyle@1.0.14
	anyhow@1.0.102
	arrayvec@0.7.6
	askama@0.13.1
	askama_derive@0.13.1
	askama_parser@0.13.0
	asn1-rs-derive@0.5.1
	asn1-rs-impl@0.2.0
	asn1-rs@0.6.2
	async-broadcast@0.7.2
	async-recursion@1.1.1
	async-trait@0.1.89
	autocfg@1.5.0
	base64@0.13.1
	base64@0.22.1
	basic-toml@0.1.10
	bincode@1.3.3
	bitflags@1.3.2
	bitflags@2.11.1
	blake2@0.10.6
	block-buffer@0.10.4
	bumpalo@3.20.2
	byteorder@1.5.0
	bytes@1.11.1
	camino@1.2.2
	cargo-platform@0.1.9
	cargo_metadata@0.19.2
	cc@1.2.60
	cfg-if@1.0.4
	cfg_aliases@0.2.1
	chacha20@0.10.1
	chacha20@0.9.1
	chacha20poly1305@0.10.1
	cipher@0.4.4
	clap@4.6.1
	clap_builder@4.6.0
	clap_derive@4.6.1
	clap_lex@1.1.0
	colorchoice@1.0.5
	combine@4.6.8
	concurrent-queue@2.5.0
	const-random-macro@0.1.16
	const-random@0.1.18
	convert_case@0.10.0
	convert_case@0.6.0
	cpufeatures@0.2.17
	cpufeatures@0.3.0
	critical-section@1.2.0
	crossbeam-utils@0.8.21
	crunchy@0.2.4
	crypto-common@0.1.7
	curve25519-dalek-derive@0.1.1
	curve25519-dalek@4.1.3
	data-encoding@2.10.0
	defmt-macros@1.0.1
	defmt-parser@1.0.0
	defmt@0.3.100
	defmt@1.0.1
	der-parser@9.0.0
	deranged@0.5.8
	derive_more-impl@1.0.0
	derive_more-impl@2.1.1
	derive_more@1.0.0
	derive_more@2.1.1
	digest@0.10.7
	displaydoc@0.2.5
	dlv-list@0.5.2
	dyn-clone@1.0.20
	endi@1.1.1
	enumflags2@0.7.12
	enumflags2_derive@0.7.12
	env_filter@1.0.1
	env_logger@0.11.10
	equivalent@1.0.2
	errno@0.3.14
	etherparse@0.19.0
	event-listener-strategy@0.5.4
	event-listener@5.4.1
	fastrand@2.4.1
	fiat-crypto@0.2.9
	find-msvc-tools@0.1.9
	foldhash@0.1.5
	form_urlencoded@1.2.2
	fs-err@2.11.0
	futures-channel@0.3.32
	futures-core@0.3.32
	futures-executor@0.3.32
	futures-io@0.3.32
	futures-lite@2.6.1
	futures-macro@0.3.32
	futures-sink@0.3.32
	futures-task@0.3.32
	futures-util@0.3.32
	futures@0.3.32
	generic-array@0.14.7
	getrandom@0.2.17
	getrandom@0.3.4
	getrandom@0.4.2
	glob@0.3.3
	goblin@0.8.2
	hash32@0.3.1
	hashbrown@0.14.5
	hashbrown@0.15.5
	hashbrown@0.17.0
	heapless@0.8.0
	heck@0.5.0
	hex-literal@1.1.0
	hex@0.4.3
	hickory-net@0.26.1
	hickory-proto@0.26.1
	hmac@0.12.1
	icu_collections@2.2.0
	icu_locale_core@2.2.0
	icu_normalizer@2.2.0
	icu_normalizer_data@2.2.0
	icu_properties@2.2.0
	icu_properties_data@2.2.0
	icu_provider@2.2.0
	id-arena@2.3.0
	idna@1.1.0
	idna_adapter@1.2.1
	indexmap@2.14.0
	inout@0.1.4
	ipnet@2.12.0
	ipnetwork@0.21.1
	is_terminal_polyfill@1.70.2
	itoa@1.0.18
	jiff-static@0.2.23
	jiff@0.2.23
	jni-macros@0.22.4
	jni-sys-macros@0.4.1
	jni-sys@0.4.1
	jni@0.22.4
	js-sys@0.3.95
	lazy_static@1.5.0
	leb128fmt@0.1.0
	libc@0.2.189
	linux-raw-sys@0.12.1
	litemap@0.8.2
	lock_api@0.4.14
	log@0.4.29
	managed@0.8.0
	matchers@0.2.0
	memchr@2.8.0
	memoffset@0.9.1
	minimal-lexical@0.2.1
	mio@1.2.2
	mnl-sys@0.2.2
	mnl@0.3.1
	netlink-packet-core@0.8.1
	netlink-packet-route@0.30.0
	netlink-proto@0.12.0
	netlink-sys@0.8.8
	nftnl-sys@0.6.4
	nftnl@0.9.3
	nix@0.27.1
	nix@0.30.1
	nix@0.31.3
	nom@7.1.3
	nom@8.0.0
	nu-ansi-term@0.50.3
	num-bigint@0.4.6
	num-conv@0.2.1
	num-integer@0.1.46
	num-traits@0.2.19
	oid-registry@0.7.1
	once_cell@1.21.4
	once_cell_polyfill@1.70.2
	opaque-debug@0.3.1
	ordered-multimap@0.7.3
	ordered-stream@0.2.0
	parking@2.2.1
	parking_lot@0.12.5
	parking_lot_core@0.9.12
	paste@1.0.15
	percent-encoding@2.3.2
	pin-project-internal@1.1.13
	pin-project-lite@0.2.17
	pin-project@1.1.13
	pkg-config@0.3.33
	plain@0.2.3
	poly1305@0.8.0
	portable-atomic-util@0.2.7
	portable-atomic@1.13.1
	potential_utf@0.1.5
	powerfmt@0.2.0
	ppv-lite86@0.2.21
	prettyplease@0.2.37
	proc-macro-crate@3.5.0
	proc-macro-error-attr2@2.0.0
	proc-macro-error2@2.0.1
	proc-macro2@1.0.106
	pyo3-async-runtimes-macros@0.29.0
	pyo3-async-runtimes@0.29.0
	pyo3-build-config@0.29.2
	pyo3-ffi@0.29.2
	pyo3-macros-backend@0.29.2
	pyo3-macros@0.29.2
	pyo3@0.29.2
	pythonize@0.29.0
	quote@1.0.45
	r-efi@5.3.0
	r-efi@6.0.0
	rand@0.10.2
	rand@0.9.4
	rand_chacha@0.9.0
	rand_core@0.10.1
	rand_core@0.6.4
	rand_core@0.9.5
	rand_xoshiro@0.7.0
	redox_syscall@0.5.18
	regex-automata@0.4.14
	regex-syntax@0.8.10
	regex@1.12.3
	ring@0.17.14
	rtnetlink@0.21.0
	rust-ini@0.21.3
	rustc-hash@2.1.2
	rustc_version@0.4.1
	rusticata-macros@4.1.0
	rustix@1.1.4
	rustls-pemfile@2.2.0
	rustls-pki-types@1.14.0
	rustls-webpki@0.103.13
	rustls@0.23.39
	rustversion@1.0.22
	ryu@1.0.23
	same-file@1.0.6
	scopeguard@1.2.0
	scroll@0.12.0
	scroll_derive@0.12.1
	semver@1.0.28
	serde@1.0.228
	serde_core@1.0.228
	serde_derive@1.0.228
	serde_json@1.0.149
	serde_repr@0.1.20
	serde_yaml@0.9.34+deprecated
	serini@0.2.2
	sha2@0.10.9
	sharded-slab@0.1.7
	shlex@1.3.0
	signal-hook-registry@1.4.8
	simd_cesu8@1.2.0
	simdutf8@0.1.5
	simple-mermaid@0.1.1
	siphasher@0.3.11
	slab@0.4.12
	smallvec@1.15.1
	smawk@0.3.2
	smoltcp@0.12.0
	socket2@0.5.10
	socket2@0.6.5
	spin@0.10.1
	stable_deref_trait@1.2.1
	static_assertions@1.1.0
	strsim@0.11.1
	subtle@2.6.1
	syn@2.0.117
	synstructure@0.13.2
	target-lexicon@0.13.5
	tempfile@3.27.0
	test-log-core@0.2.20
	test-log-macros@0.2.20
	test-log@0.2.20
	textwrap@0.16.2
	thiserror-impl@1.0.69
	thiserror-impl@2.0.18
	thiserror@1.0.69
	thiserror@2.0.18
	thread_local@1.1.9
	time-core@0.1.8
	time-macros@0.2.27
	time@0.3.47
	tiny-keccak@2.0.2
	tinystr@0.8.3
	tinyvec@1.11.0
	tinyvec_macros@0.1.1
	tokio-macros@2.7.0
	tokio-rustls@0.26.4
	tokio@1.52.1
	toml@0.5.11
	toml_datetime@1.1.1+spec-1.1.0
	toml_edit@0.25.11+spec-1.1.0
	toml_parser@1.1.2+spec-1.1.0
	tracing-attributes@0.1.31
	tracing-core@0.1.36
	tracing-log@0.2.0
	tracing-subscriber@0.3.23
	tracing@0.1.44
	typenum@1.20.0
	uds_windows@1.2.1
	unicode-ident@1.0.24
	unicode-segmentation@1.13.2
	unicode-xid@0.2.6
	uniffi@0.29.5
	uniffi_bindgen@0.29.5
	uniffi_build@0.29.5
	uniffi_core@0.29.5
	uniffi_internal_macros@0.29.5
	uniffi_macros@0.29.5
	uniffi_meta@0.29.5
	uniffi_pipeline@0.29.5
	uniffi_udl@0.29.5
	universal-hash@0.5.1
	unsafe-libyaml@0.2.11
	untrusted@0.9.0
	url@2.5.8
	utf8_iter@1.0.4
	utf8parse@0.2.2
	uuid@1.23.1
	valuable@0.1.1
	version_check@0.9.5
	walkdir@2.5.0
	wasi@0.11.1+wasi-snapshot-preview1
	wasip2@1.0.3+wasi-0.2.9
	wasip3@0.4.0+wasi-0.3.0-rc-2026-01-06
	wasm-bindgen-macro-support@0.2.118
	wasm-bindgen-macro@0.2.118
	wasm-bindgen-shared@0.2.118
	wasm-bindgen@0.2.118
	wasm-encoder@0.244.0
	wasm-metadata@0.244.0
	wasmparser@0.244.0
	webpki-roots@1.0.7
	weedle2@5.0.0
	winapi-util@0.1.11
	windows-link@0.2.1
	windows-sys@0.52.0
	windows-sys@0.61.2
	windows-targets@0.52.6
	windows_aarch64_gnullvm@0.52.6
	windows_aarch64_msvc@0.52.6
	windows_i686_gnu@0.52.6
	windows_i686_gnullvm@0.52.6
	windows_i686_msvc@0.52.6
	windows_x86_64_gnu@0.52.6
	windows_x86_64_gnullvm@0.52.6
	windows_x86_64_msvc@0.52.6
	winnow@0.7.15
	winnow@1.0.2
	wit-bindgen-core@0.51.0
	wit-bindgen-rust-macro@0.51.0
	wit-bindgen-rust@0.51.0
	wit-bindgen@0.51.0
	wit-bindgen@0.57.1
	wit-component@0.244.0
	wit-parser@0.244.0
	writeable@0.6.3
	x25519-dalek@2.0.1
	x509-parser@0.16.0
	yoke-derive@0.8.2
	yoke@0.8.2
	zbus@5.14.0
	zbus_macros@5.14.0
	zbus_names@4.3.1
	zerocopy-derive@0.8.48
	zerocopy@0.8.48
	zerofrom-derive@0.1.7
	zerofrom@0.1.7
	zeroize@1.8.2
	zeroize_derive@1.4.3
	zerotrie@0.2.4
	zerovec-derive@0.11.3
	zerovec@0.11.6
	zmij@1.0.21
	zvariant@5.10.0
	zvariant_derive@5.10.0
	zvariant_utils@3.3.0
"

# Crates only published on Proton's own registry
PROTON_CRATES="
	proton-boringtun@3.0.0
	proton-os-interface@0.2.6
	proton-pfff@0.13.0
	proton-pfff-config@0.1.0
	proton-pfff-core@0.1.2
	proton-pfff-module@0.8.6
	proton-tls-parser@0.4.0
	proton-vpn-binary-status@3.0.0
	proton-vpn-haproxyv2@0.1.0
	proton-vpn-netstack@0.6.5
	proton-vpn-toolkit@0.1.0
	proton-vpn-yaourt@0.2.2
	pvpnclient@3.0.3
"

# Git submodule, so it is missing from the release tarball. Must match the version in Cargo.lock
PROTUN_PV="2.2.1"

inherit cargo distutils-r1 systemd

DESCRIPTION="Proton AG VPN Core API"
HOMEPAGE="https://github.com/ProtonVPN/python-proton-vpn-api-core"

SRC_URI="
	https://github.com/ProtonVPN/python-proton-vpn-api-core/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	https://github.com/ProtonVPN/protun/archive/refs/tags/v${PROTUN_PV}.tar.gz -> protun-${PROTUN_PV}.tar.gz
	${CARGO_CRATE_URIS}
"
for crate in ${PROTON_CRATES}; do
	SRC_URI+=" https://rust-registry.proton.me/downloads/${crate}.crate -> ${crate/@/-}.crate"
done
unset crate

S="${WORKDIR}/python-${P}"
LICENSE="GPL-3+ GPL-3"
# Dependent crate licenses
LICENSE+="
	0BSD Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD CC0-1.0
	CDLA-Permissive-2.0 ISC MIT MPL-2.0 Unicode-3.0 ZLIB
"
# Most crates from Proton's registry do not declare a license
LICENSE+=" all-rights-reserved"
SLOT="0"
KEYWORDS="~amd64"
IUSE="test"
RESTRICT="bindist mirror !test? ( test )"

PATCHES=(
	"${FILESDIR}"/${PN}-5.8.7-remove-calls-to-apt.patch
)

DEPEND="
	>=net-libs/libnftnl-1.2.0
	net-libs/libmnl
"
# sentry-sdk is only imported when crash reporting is enabled
RDEPEND="
	${DEPEND}
	net-misc/networkmanager[introspection]
	net-vpn/networkmanager-openvpn
	sys-apps/dbus
	dev-python/cryptography[${PYTHON_USEDEP}]
	dev-python/dbus-fast[${PYTHON_USEDEP}]
	dev-python/distro[${PYTHON_USEDEP}]
	dev-python/fido2[${PYTHON_USEDEP}]
	dev-python/jinja2[${PYTHON_USEDEP}]
	dev-python/packaging[${PYTHON_USEDEP}]
	>=dev-python/proton-core-0.5.0[${PYTHON_USEDEP}]
	dev-python/pycairo[${PYTHON_USEDEP}]
	dev-python/pygobject[${PYTHON_USEDEP}]
	dev-python/pynacl[${PYTHON_USEDEP}]
"
BDEPEND="
	virtual/pkgconfig
	test? ( dev-python/pytest-asyncio[${PYTHON_USEDEP}] )
"

QA_FLAGS_IGNORED="usr/lib/python3.*/site-packages/proton/vpn/platform.abi3.so"

distutils_enable_sphinx docs
distutils_enable_tests pytest

src_unpack() {
	cargo_src_unpack

	# Use the vendored crates for Proton's registry too
	cat >> "${ECARGO_HOME}/config.toml" <<- EOF || die
	[source.proton]
	registry = "sparse+https://rust-registry.proton.me/index/"
	replace-with = "gentoo"
	EOF
}

src_prepare() {
	rmdir dependencies/protun || die
	mv "${WORKDIR}/protun-${PROTUN_PV}" dependencies/protun || die

	distutils-r1_src_prepare

	sed -i "/--cov/d" setup.cfg || die
	sed -i "s|^program=.*|program=${EPREFIX}/usr/libexec/nm-protun-service|" \
		resources/nm-protun.name || die
}

src_compile() {
	python_setup
	export PYO3_PYTHON="${PYTHON}"
	cargo_src_compile

	# abi3 extension, shared by all Python implementations
	cp "$(cargo_target_dir)/libproton_vpn_platform.so" proton/vpn/platform.abi3.so || die

	distutils-r1_src_compile
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

src_install() {
	distutils-r1_src_install

	exeinto /usr/libexec
	doexe "$(cargo_target_dir)"/{nm-protun-service,proton-vpn-kill-switch-service}

	insinto /usr/lib/NetworkManager/VPN
	doins resources/nm-protun.name

	insinto /usr/share/dbus-1/system.d
	doins resources/nm-protun-service.conf
	newins resources/proton-vpn-kill-switch.conf me.proton.vpn.kill_switch.conf

	insinto /usr/share/dbus-1/system-services
	newins resources/proton-vpn-kill-switch.dbus-service me.proton.vpn.kill_switch.service

	systemd_dounit resources/proton-vpn-kill-switch-boot.service
}
