#!/usr/bin/env bash
# Runs inside a gentoo/stage3 container with the overlay mounted at /overlay,
# see .github/autobump/README.md.
#
#   gentoo.sh setup                           sync ::gentoo and install the tools
#   gentoo.sh verify <cat/pn> <ver> <log>     pkgcheck + emerge one version
#   gentoo.sh job <cat/pn> <old> <new> <mode> <drop_old> <url>
#                                             bump one package, results go to .autobump-out/
set -euo pipefail

OVERLAY=/overlay
OUT=${OVERLAY}/.autobump-out
AUTOBUMP=(python3 "${OVERLAY}/.github/autobump/autobump.py")
CLAUDE_ROUNDS=${CLAUDE_ROUNDS:-3}
CLAUDE_MAX_TURNS=${CLAUDE_MAX_TURNS:-80}
export PATH="${HOME}/.local/bin:${PATH}"
CLAUDE_TOOLS="Read,Edit,Write,Glob,Grep,WebFetch,Bash(ebuild:*),Bash(emerge:*),Bash(pkgdev:*),Bash(pkgcheck:*),Bash(pycargoebuild:*),Bash(git diff:*),Bash(git status:*),Bash(git log:*),Bash(diff:*),Bash(tar:*),Bash(ls:*),Bash(find:*),Bash(grep:*),Bash(cat:*),Bash(head:*),Bash(tail:*)"

setup() {
	# A restored actions/cache belongs to the runner user, but portage and
	# pkgdev fetch as the portage user
	chown -R portage:portage /var/cache/distfiles
	chmod 2775 /var/cache/distfiles
	# The workflows mount ::gentoo from the gentoo/portage image, which avoids
	# emerge-webrsync's dependency on a reachable OpenPGP keyserver
	[[ -d /var/db/repos/gentoo/metadata ]] || emerge-webrsync --quiet
	cat >> /etc/portage/make.conf <<-EOF
		FEATURES="\${FEATURES} getbinpkg buildpkg -ipc-sandbox -network-sandbox -pid-sandbox"
		ACCEPT_LICENSE="*"
		MAKEOPTS="-j$(nproc)"
		CONFIG_PROTECT_MASK="/etc/portage"
		EMERGE_DEFAULT_OPTS="--quiet-build=y --autounmask-continue=y"
	EOF
	mkdir -p /etc/portage/repos.conf /etc/portage/package.accept_keywords
	# pkgcore ignores portage's built-in default once /etc/portage/repos.conf exists
	printf '[DEFAULT]\nmain-repo = gentoo\n\n[gentoo]\nlocation = /var/db/repos/gentoo\n' \
		> /etc/portage/repos.conf/gentoo.conf
	printf '[cy1der]\nlocation = %s\n' "${OVERLAY}" > /etc/portage/repos.conf/cy1der.conf
	echo "*/*::cy1der ~amd64" > /etc/portage/package.accept_keywords/cy1der
	getuto
	emerge --oneshot --noreplace dev-vcs/git dev-util/pkgdev dev-util/pkgcheck app-portage/pycargoebuild
	git config --global --add safe.directory "${OVERLAY}"
}

# Every command needs "|| return 1": set -e is off when called from an if.
verify() {
	local cp=$1 ver=$2 log=$3
	{
		echo ">>> pkgcheck scan ${cp}"
		(cd "${OVERLAY}" && pkgcheck scan --exit error -- "${cp}") > "${OUT}/pkgcheck.txt" 2>&1 \
			|| { cat "${OUT}/pkgcheck.txt"; return 1; }
		cat "${OUT}/pkgcheck.txt"
		echo ">>> emerge =${cp}-${ver}"
		# Never reuse a binpkg of the package under test, always build it
		emerge --oneshot --usepkg-exclude "${cp}" --buildpkg-exclude "${cp}" "=${cp}-${ver}" || return 1
	} > "${log}" 2>&1
}

install_claude() {
	command -v claude > /dev/null || curl -fsSL https://claude.ai/install.sh | bash > /dev/null
}

claude_round() {
	local round=$1
	local args=(-p --max-turns "${CLAUDE_MAX_TURNS}" --permission-mode acceptEdits --allowedTools "${CLAUDE_TOOLS}")
	((round > 1)) && args+=(--continue)
	(cd "${OVERLAY}" && CLAUDE_CODE_OAUTH_TOKEN=${claude_token} claude "${args[@]}") \
		> "${OUT}/claude-round-${round}.txt" 2>&1
}

# Fingerprint of the package directory, to tell whether Claude changed anything
pkg_state() {
	git add -A -- "$1" && git diff --cached -- "$1" | sha1sum
}

job() {
	local cp=$1 old=$2 new=$3 mode=$4 drop_old=$5 url=$6
	local status=failed bumped=false round
	# Only the claude process gets the token, our own builds don't see it
	local claude_token=${CLAUDE_CODE_OAUTH_TOKEN:-}
	unset CLAUDE_CODE_OAUTH_TOKEN

	rm -rf "${OUT}"
	mkdir -p "${OUT}"
	cd "${OVERLAY}"
	git config user.name autobump
	git config user.email autobump@localhost

	echo ">>> ${cp}: ${old} -> ${new} (${mode})"
	if "${AUTOBUMP[@]}" bump "${cp}" "${new}" > "${OUT}/build.log" 2>&1; then
		bumped=true
		# ai-mode packages go straight to Claude, unless there is no token
		if [[ ${mode} == pr || -z ${claude_token} ]] && verify "${cp}" "${new}" "${OUT}/build.log"; then
			status="pr"
		fi
	fi
	echo ">>> mechanical bump: $([[ ${status} == pr ]] && echo built || echo "not built")"

	if [[ ${status} == failed && -n ${claude_token} ]]; then
		install_claude
		local prompt_args=(--url "${url}")
		# Hand over the log only when something actually failed
		if [[ ${mode} == pr || ${bumped} == false ]]; then
			prompt_args+=(--log "${OUT}/build.log")
		fi
		local before claude_ok
		before=$(pkg_state "${cp}")
		for ((round = 1; round <= CLAUDE_ROUNDS; round++)); do
			echo ">>> Claude round ${round}"
			claude_ok=true
			if ((round == 1)); then
				"${AUTOBUMP[@]}" prompt "${cp}" "${old}" "${new}" "${prompt_args[@]}" | claude_round 1 \
					|| claude_ok=false
			else
				{
					echo "Verification failed again. Fix it and update .autobump-out/ai-summary.md."
					echo "Tail of the verification log:"
					echo '```'
					tail -n 150 "${OUT}/build.log"
					echo '```'
				} | claude_round "${round}" || claude_ok=false
			fi
			if verify "${cp}" "${new}" "${OUT}/build.log"; then
				# Unchanged by Claude means it was a mechanical bump after all
				if [[ $(pkg_state "${cp}") == "${before}" ]]; then
					status="pr"
				else
					status="ai"
				fi
				break
			fi
			if [[ ${claude_ok} == false ]]; then
				echo ">>> Claude exited with an error, see claude-round-${round}.txt"
				break
			fi
		done
	fi
	echo ">>> result: ${status}"

	# Only changes inside the package directory are kept. Diff against main,
	# which publish applies the patch to, even when building on a PR branch.
	local main
	main=$(git rev-parse -q --verify origin/main || git rev-parse HEAD)
	git add -A -- "${cp}"
	git diff --cached --binary "${main}" -- "${cp}" > "${OUT}/bump.patch"
	if [[ ${status} != failed && ${drop_old} == true ]]; then
		git commit -q -m "tmp: bump"
		if "${AUTOBUMP[@]}" drop "${cp}" "${old}" >> "${OUT}/build.log" 2>&1; then
			git add -A -- "${cp}"
			git diff --cached --binary > "${OUT}/drop.patch"
		fi
	fi

	python3 -c 'import json, sys; json.dump(dict(zip(("atom", "old", "new", "mode", "status", "url"), sys.argv[2:])), open(sys.argv[1], "w"))' \
		"${OUT}/result.json" "${cp}" "${old}" "${new}" "${mode}" "${status}" "${url}"
}

"$@"
