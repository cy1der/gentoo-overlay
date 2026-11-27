# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
	aes@0.8.4
	allocator-api2@0.2.21
	android_system_properties@0.1.5
	anstream@0.6.20
	anstyle-parse@0.2.7
	anstyle-query@1.1.4
	anstyle-wincon@3.0.10
	anstyle@1.0.11
	anyhow@1.0.100
	approx@0.5.1
	arc-swap@1.7.1
	atomicwrites@0.4.4
	autocfg@1.5.0
	bitflags@2.13.2
	block-buffer@0.10.4
	block-padding@0.3.3
	bumpalo@3.19.0
	by_address@1.2.1
	castaway@0.2.4
	cbc@0.1.2
	cc@1.2.39
	cfg-if@1.0.3
	chrono@0.4.42
	cipher@0.4.4
	clap@4.5.48
	clap_builder@4.5.48
	clap_derive@4.5.47
	clap_lex@0.7.5
	colorchoice@1.0.4
	compact_str@0.9.1
	console@0.16.1
	convert_case@0.7.1
	core-foundation-sys@0.8.7
	cpufeatures@0.2.17
	crossbeam-deque@0.8.6
	crossbeam-epoch@0.9.18
	crossbeam-utils@0.8.21
	crossterm@0.29.0
	crossterm_winapi@0.9.1
	crypto-common@0.1.6
	darling@0.20.11
	darling_core@0.20.11
	darling_macro@0.20.11
	deranged@0.5.8
	derive_more-impl@2.0.1
	derive_more@2.0.1
	destructure_traitobject@0.2.0
	digest@0.10.7
	document-features@0.2.12
	either@1.15.0
	encode_unicode@1.0.0
	equivalent@1.0.2
	errno@0.3.14
	fastrand@2.5.0
	find-msvc-tools@0.1.2
	fnv@1.0.7
	foldhash@0.2.0
	fs2@0.4.3
	generic-array@0.14.7
	getrandom@0.3.3
	hashbrown@0.16.0
	hashbrown@0.17.1
	heck@0.5.0
	hermit-abi@0.5.2
	hex@0.4.3
	humantime@2.3.0
	iana-time-zone-haiku@0.1.2
	iana-time-zone@0.1.64
	ident_case@1.0.1
	indexmap@2.11.4
	indicatif@0.18.0
	indoc@2.0.7
	inout@0.1.4
	instability@0.3.10
	is_terminal_polyfill@1.70.1
	itertools@0.14.0
	itoa@1.0.15
	js-sys@0.3.81
	kasuari@0.4.12
	libc@0.2.190
	libm@0.2.16
	line-clipping@0.3.8
	linux-raw-sys@0.12.1
	linux-raw-sys@0.4.15
	litrs@1.0.0
	lock_api@0.4.13
	log-mdc@0.1.0
	log4rs@1.4.0
	log@0.4.28
	lru@0.18.5
	memchr@2.7.6
	mio@1.2.4
	mock_instant@0.6.0
	num-conv@0.2.2
	num-traits@0.2.19
	num_cpus@1.17.0
	num_threads@0.1.7
	once_cell@1.21.3
	once_cell_polyfill@1.70.1
	ordered-float@2.10.1
	palette@0.7.7
	palette_derive@0.7.7
	palette_math@0.7.7
	parking_lot@0.12.4
	parking_lot_core@0.9.11
	portable-atomic@1.15.0
	powerfmt@0.2.0
	ppv-lite86@0.2.21
	proc-macro2@1.0.101
	quote@1.0.40
	r-efi@5.3.0
	rand@0.9.2
	rand_chacha@0.9.0
	rand_core@0.9.3
	ratatui-core@0.1.2
	ratatui-crossterm@0.1.2
	ratatui-widgets@0.3.2
	ratatui@0.30.2
	rayon-core@1.13.0
	rayon@1.11.0
	redox_syscall@0.5.17
	rustix@0.38.44
	rustix@1.1.5
	rustversion@1.0.22
	ryu@1.0.20
	same-file@1.0.6
	scopeguard@1.2.0
	serde-value@0.7.0
	serde@1.0.228
	serde_core@1.0.228
	serde_derive@1.0.228
	serde_json@1.0.145
	serde_yaml@0.9.34+deprecated
	sha2@0.10.9
	shlex@1.3.0
	signal-hook-mio@0.2.5
	signal-hook-registry@1.4.8
	signal-hook@0.3.18
	smallvec@1.15.1
	static_assertions@1.1.0
	strsim@0.11.1
	strum@0.28.0
	strum_macros@0.28.0
	syn@2.0.106
	tempfile@3.27.0
	thiserror-impl@2.0.16
	thiserror@2.0.16
	thread-id@5.0.0
	time-core@0.1.9
	time@0.3.55
	typemap-ors@1.0.0
	typenum@1.18.0
	unicode-ident@1.0.19
	unicode-segmentation@1.12.0
	unicode-truncate@2.0.1
	unicode-width@0.2.1
	unicode-xid@0.2.6
	unit-prefix@0.5.1
	unsafe-any-ors@1.0.0
	unsafe-libyaml@0.2.11
	utf8parse@0.2.2
	version_check@0.9.5
	wasi@0.11.1+wasi-snapshot-preview1
	wasi@0.14.7+wasi-0.2.4
	wasip2@1.0.1+wasi-0.2.4
	wasm-bindgen-backend@0.2.104
	wasm-bindgen-macro-support@0.2.104
	wasm-bindgen-macro@0.2.104
	wasm-bindgen-shared@0.2.104
	wasm-bindgen@0.2.104
	web-time@1.1.0
	winapi-i686-pc-windows-gnu@0.4.0
	winapi-util@0.1.11
	winapi-x86_64-pc-windows-gnu@0.4.0
	winapi@0.3.9
	windows-core@0.62.1
	windows-implement@0.60.1
	windows-interface@0.59.2
	windows-link@0.2.0
	windows-result@0.4.0
	windows-strings@0.5.0
	windows-sys@0.52.0
	windows-sys@0.59.0
	windows-sys@0.60.2
	windows-sys@0.61.1
	windows-targets@0.52.6
	windows-targets@0.53.4
	windows_aarch64_gnullvm@0.52.6
	windows_aarch64_gnullvm@0.53.0
	windows_aarch64_msvc@0.52.6
	windows_aarch64_msvc@0.53.0
	windows_i686_gnu@0.52.6
	windows_i686_gnu@0.53.0
	windows_i686_gnullvm@0.52.6
	windows_i686_gnullvm@0.53.0
	windows_i686_msvc@0.52.6
	windows_i686_msvc@0.53.0
	windows_x86_64_gnu@0.52.6
	windows_x86_64_gnu@0.53.0
	windows_x86_64_gnullvm@0.52.6
	windows_x86_64_gnullvm@0.53.0
	windows_x86_64_msvc@0.52.6
	windows_x86_64_msvc@0.53.0
	wit-bindgen@0.46.0
	zerocopy-derive@0.8.27
	zerocopy@0.8.27
"
PYTHON_COMPAT=( python3_{11..14} )
RUST_MIN_VER="1.88.0"

inherit cargo python-any-r1

DESCRIPTION="Decrypts Redump PS3 disc images with their disc keys"
HOMEPAGE="https://github.com/Redrrx/ps3dec"
SRC_URI="
	https://github.com/Redrrx/ps3dec/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	${CARGO_CRATE_URIS}
"

LICENSE="MIT"
# Dependent crate licenses
LICENSE+=" 0BSD Apache-2.0 MIT Unicode-3.0 ZLIB"
SLOT="0"
KEYWORDS="~amd64"
IUSE="test"
RESTRICT="!test? ( test )"

# The end-to-end test makes an encrypted image of its own
BDEPEND="
	test? (
		${PYTHON_DEPS}
		app-cdr/cdrtools
		dev-libs/openssl
	)
"

pkg_setup() {
	use test && python-any-r1_pkg_setup
	rust_pkg_setup
}

src_configure() {
	cargo_src_configure --bin ps3dec
}

src_test() {
	# It runs a debug build; use the one that was built
	sed -i "s|ROOT / \"target\" / \"debug\"|Path(\"$(cargo_target_dir)\")|" tests/e2e.py || die
	"${EPYTHON}" -B tests/e2e.py || die
}

src_install() {
	cargo_src_install --bin ps3dec
	dodoc README.md
}
