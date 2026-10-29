# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DOTNET_PKG_COMPAT="8.0"
NUGETS="
	avalonia@11.2.3
	avalonia.angle.windows.natives@2.1.22045.20230930
	avalonia.buildservices@0.0.29
	avalonia.desktop@11.2.3
	avalonia.freedesktop@11.2.3
	avalonia.native@11.2.3
	avalonia.remote.protocol@11.2.3
	avalonia.skia@11.2.3
	avalonia.themes.fluent@11.2.3
	avalonia.win32@11.2.3
	avalonia.x11@11.2.3
	harfbuzzsharp@7.3.0.3
	harfbuzzsharp.nativeassets.linux@7.3.0.3
	harfbuzzsharp.nativeassets.macos@7.3.0.3
	harfbuzzsharp.nativeassets.webassembly@7.3.0.3
	harfbuzzsharp.nativeassets.win32@7.3.0.3
	microcom.runtime@0.11.0
	skiasharp@2.88.9
	skiasharp.nativeassets.linux@2.88.9
	skiasharp.nativeassets.macos@2.88.9
	skiasharp.nativeassets.webassembly@2.88.9
	skiasharp.nativeassets.win32@2.88.9
	system.io.pipelines@8.0.0
	system.windows.extensions@8.0.0
	tmds.dbus.protocol@0.20.0
"
PYTHON_COMPAT=( python3_{11..15} )

inherit cmake desktop dotnet-pkg-base edo flag-o-matic python-single-r1 toolchain-funcs xdg

DESCRIPTION="Runs your own Bloodborne dump natively, with its graphics on Vulkan"
HOMEPAGE="https://github.com/Awakenchan/LanternEngine"
SRC_URI="
	https://github.com/Awakenchan/LanternEngine/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	https://github.com/Awakenchan/LanternEngine/releases/download/v${PV}/LanternEngine-v${PV}-linux-x64.tar.gz
		-> ${P}-linux-x64.tar.gz
	gui? ( ${NUGET_URIS} )
"
S="${WORKDIR}/LanternEngine-${PV}"
CMAKE_USE_DIR="${S}/engine/gpu"

LICENSE="GPL-3+ dlss? ( NVIDIA-RTX-SDK )"
SLOT="0"
# The game's own x86-64 code runs directly on the CPU
KEYWORDS="-* ~amd64"
IUSE="dlss +gui"
REQUIRED_USE="${PYTHON_REQUIRED_USE}"
# Replaces dotnet-pkg-base's package-wide RESTRICT=strip: only the launcher and the DLSS
# runtime are kept unstripped (dostrip -x in src_install)
RESTRICT="mirror dlss? ( bindist )"

DEPEND="
	>=dev-cpp/cpp-httplib-0.60:=[ssl,zlib]
	>=dev-cpp/magic_enum-0.9.7
	dev-cpp/nlohmann_json
	>=dev-cpp/robin-map-1.4
	dev-libs/boost
	dev-libs/half
	>=dev-libs/libfmt-12:=
	>=dev-libs/miniz-3.1.0:=
	dev-libs/openssl:=
	>=dev-libs/protobuf-29.5:=
	>=dev-libs/xbyak-7.24
	dev-libs/xxhash
	dev-libs/zydis:=
	dev-util/spirv-headers
	>=dev-util/vulkan-headers-1.4.357
	dev-util/vulkan-memory-allocator
	media-libs/libatrac9
	>=media-libs/libsdl3-3.4
	media-libs/vulkan-loader
	>=media-video/ffmpeg-7.1:=
	net-libs/miniupnpc:=
	virtual/zlib:=
	x11-libs/libX11
"
RDEPEND="
	${PYTHON_DEPS}
	>=dev-cpp/cpp-httplib-0.60:=[ssl,zlib]
	>=dev-libs/libfmt-12:=
	>=dev-libs/miniz-3.1.0:=
	dev-libs/openssl:=
	>=dev-libs/protobuf-29.5:=
	dev-libs/xxhash
	dev-libs/zydis:=
	media-libs/libatrac9
	>=media-libs/libsdl3-3.4
	media-libs/vulkan-loader
	>=media-video/ffmpeg-7.1:=
	net-libs/miniupnpc:=
	virtual/zlib:=
	x11-libs/libX11
	gui? (
		${DOTNET_PKG_RDEPS}
		media-libs/fontconfig
		x11-libs/libICE
		x11-libs/libSM
		x11-libs/libXcursor
		x11-libs/libXi
		x11-libs/libXrandr
	)
"
BDEPEND="
	dev-util/glslang
	virtual/pkgconfig
	gui? (
		${DOTNET_PKG_BDEPS}
		media-gfx/icoutils
	)
"

PATCHES=(
	"${FILESDIR}"/${PN}-0.9.37-build-fixes.patch
	"${FILESDIR}"/${PN}-0.9.37-no-self-update.patch
	"${FILESDIR}"/${PN}-0.9.37-steam-shortcut.patch
	"${FILESDIR}"/${PN}-0.9.37-system-libs.patch
)

QA_PREBUILT="
	usr/share/${PN}/launcher/*
	usr/lib*/${PN}/engine/out/libnvidia-ngx-dlss.so.*
"

pkg_setup() {
	python-single-r1_pkg_setup
	use gui && dotnet-pkg-base_setup
}

src_unpack() {
	unpack ${P}.tar.gz

	# Only the data that isn't in the repository: the FSR 4 shaders, the shader catalog, the
	# shipped settings and NVIDIA's DLSS runtime. Everything else is built here.
	mkdir "${WORKDIR}"/release || die
	local release=(
		lantern.ini
		package.json
		engine/fsr4_shaders
		engine/gamecontrollerdb.txt
		engine/shader-catalog
	)
	use dlss && release+=(
		engine/out/LICENSE-DLSS-SDK.txt
		engine/out/libnvidia-ngx-dlss.so.*
	)
	tar -xzf "${DISTDIR}"/${P}-linux-x64.tar.gz -C "${WORKDIR}"/release --strip-components=1 \
		--wildcards "${release[@]/#/LanternEngine/}" || die

	if use gui; then
		nuget_link-system-nugets
		nuget_link-nuget-archives
	fi
}

src_prepare() {
	rm -r engine/gpu/bbnet/third_party/httplib \
		engine/gpu/third_party/half \
		engine/gpu/third_party/sirit/externals/SPIRV-Headers \
		engine/third_party/LibAtrac9 || die

	cmake_src_prepare

	use gui && nuget_writeconfig "${S}"/launcher/windows/
}

src_configure() {
	# AMD's FidelityFX SDK (bundled in FSR-Vulkan) type-puns pointers, and FSR-Vulkan links
	# several versions of it that define the same types differently (ODR violations under LTO)
	append-flags -fno-strict-aliasing
	filter-lto

	local mycmakeargs=(
		-DBB_LTO=OFF
		-DBB_MARCH=
		-DBB_PGO=off
		# The bundled sirit is linked into libbbgpu.so
		-DBUILD_SHARED_LIBS=OFF
		# Nothing is installed with CMake: give the programs their final RUNPATH right away
		-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
		-DCMAKE_INSTALL_RPATH="${EPREFIX}"/usr/$(get_libdir)/${PN}/engine/out/gpu
	)
	cmake_src_configure

	if use gui; then
		dotnet-pkg-base_restore launcher/windows/LanternLauncher/LanternLauncher.csproj
	fi
}

# The GPU cache's identity, as engine/build.sh computes it: the shipped shader catalog and the
# players' caches are kept while it stays the same.
gpu_cache_sources() {
	local vc=gpu/shadps4/video_core
	find gpu/shadps4/shader_recompiler ${vc}/amdgpu gpu/shadps4/common/serdes.h \
		${vc}/cache_storage.cpp ${vc}/cache_storage.h \
		${vc}/renderer_vulkan/liverpool_to_vk.* ${vc}/renderer_vulkan/vk_*pipeline* \
		${vc}/renderer_vulkan/pipeline_cache_blob.h ${vc}/renderer_vulkan/vk_object_motion.* \
		-type f \( -name '*.cpp' -o -name '*.h' -o -name '*.inc' \) | LC_ALL=C sort
	assert
}

src_compile() {
	cmake_src_compile bbgpu bb-engine-assets bb-shader-lab

	pushd engine >/dev/null || die
	local pkgs=( vulkan sdl3 ) cflags libs
	cflags=( -std=gnu11 ${CPPFLAGS} ${CFLAGS} -pthread )
	cflags+=( $($(tc-getPKG_CONFIG) --cflags "${pkgs[@]}" libatrac9) ) || die
	libs=( $($(tc-getPKG_CONFIG) --libs "${pkgs[@]}") ) || die

	# The same programs and options as engine/build.sh. bb-probe stays non-PIE: the game's
	# memory layout depends on it.
	edo $(tc-getCC) "${cflags[@]}" -I. -Isrc src/probe.c src/runtime*.c src/vulkan_smoke.c \
		${LDFLAGS} -latrac9 -lm -L"${BUILD_DIR}" -lbbgpu \
		-Wl,-rpath,"${EPREFIX}"/usr/$(get_libdir)/${PN}/engine/out/gpu -rdynamic \
		"${libs[@]}" -no-pie -o "${T}"/bb-probe
	edo $(tc-getCC) "${cflags[@]}" tools/gpu_capabilities.c ${LDFLAGS} "${libs[@]}" \
		-o "${T}"/bb-gpu-capabilities

	# Files and lines that store nothing in the caches (build.sh leaves them out)
	local skip_files='vk_(graphics|compute)_pipeline\.cpp$|vk_pipeline_common\.(cpp|h)$'
	skip_files+='|pipeline_compile_queue\.h$|native/capture\.(cpp|h)$'
	local skip_lines='Shader::Native::Capture|shader_recompiler/native/capture\.h|lab_flat|fetch_override'
	gpu_cache_sources | grep -v -E "${skip_files}" | xargs cat | tr -d '\r' | grep -v -E "${skip_lines}" |
		sed -E 's#^[[:space:]]*//.*$##; s/[[:space:]]+$//' | grep -v '^$' |
		sha256sum | cut -c1-16 > "${T}"/gpu-cache.id
	assert
	gpu_cache_sources | xargs cat | sha256sum | cut -c1-16 > "${T}"/gpu-cache.legacy.id
	assert
	popd >/dev/null || die

	if use gui; then
		dotnet-pkg-base_build -p:Version=${PV} -p:InformationalVersion=${PV}+gentoo \
			launcher/windows/LanternLauncher/LanternLauncher.csproj
	fi
}

src_install() {
	# Laid out as upstream's Linux package (engine/packaging/linux/build.sh)
	local dist=/usr/$(get_libdir)/${PN}

	insinto ${dist}
	doins "${WORKDIR}"/release/package.json LICENSE NOTICE
	exeinto ${dist}
	doexe engine/packaging/linux/lantern.sh

	insinto ${dist}/engine
	doins -r engine/{data,licenses,patches,scripts} \
		"${WORKDIR}"/release/engine/{fsr4_shaders,gamecontrollerdb.txt,shader-catalog}
	newins "${WORKDIR}"/release/lantern.ini lantern.default.ini
	exeinto ${dist}/engine
	doexe engine/run.sh
	python_fix_shebang "${ED}"${dist}/engine/scripts
	chmod +x "${ED}"${dist}/engine/scripts/*.py || die

	exeinto ${dist}/engine/out
	doexe "${T}"/{bb-probe,bb-gpu-capabilities} engine/packaging/linux/bb-start \
		"${BUILD_DIR}"/{bb-engine-assets,bb-shader-lab}
	insinto ${dist}/engine/out
	doins "${T}"/gpu-cache{,.legacy}.id
	exeinto ${dist}/engine/out/gpu
	doexe "${BUILD_DIR}"/libbbgpu.so

	if use dlss; then
		exeinto ${dist}/engine/out
		doexe "${WORKDIR}"/release/engine/out/libnvidia-ngx-dlss.so.*
		insinto ${dist}/engine/out
		doins "${WORKDIR}"/release/engine/out/LICENSE-DLSS-SDK.txt
		dostrip -x ${dist}/engine/out/libnvidia-ngx-dlss.so.*
	fi

	# The .NET runtime is found as dotnet-pkg-base_dolauncher finds it
	local dotnet_roots="${EPREFIX}/usr/$(get_libdir)/dotnet-sdk-${DOTNET_PKG_COMPAT}"
	dotnet_roots+=" ${EPREFIX}/opt/dotnet-sdk-bin-${DOTNET_PKG_COMPAT}"
	sed -e "s|@DIST@|${EPREFIX}${dist}|" \
		-e "s|@PYTHON@|${PYTHON}|" \
		-e "s|@LAUNCHER@|${EPREFIX}/usr/share/${PN}/launcher/Lantern Engine|" \
		-e "s|@LAUNCHER_SCRIPT@|${EPREFIX}/usr/bin/${PN}-launcher|" \
		-e "s|@DOTNET_ROOTS@|${dotnet_roots}|" \
		"${FILESDIR}"/${PN}-0.9.37-wrapper.sh > "${T}"/${PN} || die
	dobin "${T}"/${PN}

	if use gui; then
		dotnet-pkg-base_install /usr/share/${PN}/launcher
		dostrip -x /usr/share/${PN}/launcher
		dosym ${PN} /usr/bin/${PN}-launcher

		icotool -x -o "${T}" launcher/windows/BloodborneLauncher/app.ico || die
		local size
		for size in 16 24 32 48 64 128 256; do
			newicon -s ${size} "${T}"/app_*_${size}x${size}x32.png ${PN}.png
		done
		make_desktop_entry ${PN}-launcher "Lantern Engine" ${PN} "Game;Emulator"
	fi

	dodoc README.md engine/packaging/linux/README-linux.txt
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "No game files are included: you need your own decrypted dump of Bloodborne"
	elog "(CUSA03173) with update 1.09."
	elog
	elog "Start it with 'lantern-engine /path/to/CUSA03173'$(usex gui " or 'lantern-engine-launcher'" "")."
	elog "Settings, saves, mods and logs are kept in \${XDG_DATA_HOME:-~/.local/share}/lantern-engine"
	elog "(LANTERN_ENGINE_HOME overrides it). Updates come through portage; the launcher's"
	elog "self-update is turned off."
}
