#!/usr/bin/env bash
# Runs inside a gentoo/stage3 container with the overlay mounted at /overlay,
# see .github/autobump/README.md.
#
#   gentoo.sh setup                           sync ::gentoo and install the tools
#   gentoo.sh deps =<cat/pn>-<ver>            install the build-time deps of one version
#   gentoo.sh build =<cat/pn>-<ver>           build one version (build-time deps only)
#   gentoo.sh verify <cat/pn> <ver> <log>     pkgcheck + build one version
#   gentoo.sh prune [<cat/pn>...]             drop distfiles and binpkgs of what isn't installed
#   gentoo.sh job <cat/pn> <old> <new> <mode> <drop_old> <url>
#                                             bump one package, results go to .autobump-out/
set -euo pipefail

OVERLAY=/overlay
OUT=${OVERLAY}/.autobump-out
AUTOBUMP=(python3 "${OVERLAY}/.github/autobump/autobump.py")
SELF=${OVERLAY}/.github/autobump/gentoo.sh
CLAUDE_ROUNDS=${CLAUDE_ROUNDS:-3}
CLAUDE_MAX_TURNS=${CLAUDE_MAX_TURNS:-80}
# Each Claude round is stopped after this long. The whole bump has
# BUDGET_MINUTES (set by autobump.yml, no limit when unset).
CLAUDE_ROUND_MINUTES=${CLAUDE_ROUND_MINUTES:-60}
export PATH="${HOME}/.local/bin:${PATH}"
CLAUDE_TOOLS="Read,Edit,Write,Glob,Grep,WebFetch,Bash(${SELF} build:*),Bash(${SELF} deps:*),Bash(.github/autobump/gentoo.sh build:*),Bash(.github/autobump/gentoo.sh deps:*),Bash(ebuild:*),Bash(emerge:*),Bash(pkgdev:*),Bash(pkgcheck:*),Bash(pycargoebuild:*),Bash(python3:*),Bash(git diff:*),Bash(git status:*),Bash(git log:*),Bash(diff:*),Bash(tar:*),Bash(ls:*),Bash(find:*),Bash(grep:*),Bash(cat:*),Bash(head:*),Bash(tail:*)"

setup() {
	# A restored actions/cache belongs to the runner user, but portage and
	# pkgdev fetch as the portage user
	chown -R portage:portage /var/cache/distfiles
	chmod 2775 /var/cache/distfiles
	# The workflows mount ::gentoo from the gentoo/portage image, which avoids
	# emerge-webrsync's dependency on a reachable OpenPGP keyserver
	[[ -d /var/db/repos/gentoo/metadata ]] || emerge-webrsync --quiet
	# Some ebuilds may need ~amd64 deps from ::gentoo
	cat >> /etc/portage/make.conf <<-EOF
		FEATURES="\${FEATURES} getbinpkg buildpkg -ipc-sandbox -network-sandbox -pid-sandbox"
		ACCEPT_LICENSE="*"
		MAKEOPTS="-j$(nproc)"
		CONFIG_PROTECT_MASK="/etc/portage"
		EMERGE_DEFAULT_OPTS="--quiet-build=y --autounmask-continue=y --autounmask-keep-keywords=n"
	EOF
	mkdir -p /etc/portage/repos.conf /etc/portage/package.accept_keywords /etc/portage/package.use
	# pkgcore ignores portage's built-in default once /etc/portage/repos.conf exists
	printf '[DEFAULT]\nmain-repo = gentoo\n\n[gentoo]\nlocation = /var/db/repos/gentoo\n' \
		> /etc/portage/repos.conf/gentoo.conf
	printf '[cy1der]\nlocation = %s\n' "${OVERLAY}" > /etc/portage/repos.conf/cy1der.conf
	echo "*/*::cy1der ~amd64" > /etc/portage/package.accept_keywords/cy1der
	getuto
	emerge --oneshot --noreplace dev-vcs/git dev-util/pkgdev dev-util/pkgcheck app-portage/pycargoebuild \
		app-portage/gentoolkit
	git config --global --add safe.directory "${OVERLAY}"
}

# Keeps only the distfiles and binpkgs of what is installed: stage3, the
# package's build dependencies and the package. Otherwise the cache saved
# after a job holds everything every job before it restored and added to, and
# outgrows the repository's 10 GB. The distfiles of the packages given are
# kept even when they aren't installed, so a retry after a failed build
# doesn't download them again.
prune() {
	command -v eclean-dist > /dev/null || return 0
	local keep
	keep=$(mktemp)
	printf '%s\n' "$@" > "${keep}"
	echo ">>> cache before (distfiles, binpkgs): $(du -sh /var/cache/distfiles /var/cache/binpkgs | cut -f1 | xargs)"
	eclean-dist --deep --quiet --exclude-file="${keep}" || true
	eclean-pkg --deep --quiet || true
	echo ">>> cache after: $(du -sh /var/cache/distfiles /var/cache/binpkgs | cut -f1 | xargs)"
	rm -f "${keep}"
}

# Sets the caller's opts to the emerge options for the =atom $1: never reuse a
# binpkg of the package under test, always build it. Also turns on verify-sig
# for it (off by default), so a bump proves upstream's signatures. Not for
# everything: binpkgs built without the flag would no longer match, and their
# packages would be compiled instead.
# Every command needs "|| return 1": set -e is off when called from an if.
pkg_opts() {
	local cp
	cp=$(python3 -c 'import sys; from portage.versions import cpv_getkey; print(cpv_getkey(sys.argv[1].lstrip("=")))' "$1") \
		|| return 1
	opts=(--oneshot --usepkg-exclude "${cp}" --buildpkg-exclude "${cp}")
	echo "${cp} verify-sig" > /etc/portage/package.use/zz-under-test || return 1
}

# Installs only what building and installing one version needs (DEPEND,
# BDEPEND, IDEPEND), not the package itself. Its runtime-only dependencies are
# left out: they're not needed to build it, and a GUI toolkit that is only used
# at run time can take hours to compile.
deps() {
	local opts
	pkg_opts "$1" || return 1
	emerge "${opts[@]}" --onlydeps --onlydeps-with-rdeps=n --onlydeps-with-ideps=y "$1" || return 1
}

# Builds one version with its default USE, after installing its build-time
# dependencies (see deps).
build() {
	local opts
	pkg_opts "$1" || return 1
	deps "$1" || return 1
	emerge "${opts[@]}" --nodeps "$1" || return 1
}

# Runs a command for at most $1 seconds (0: no limit of its own) and never past
# DEADLINE, if job() set one. Returns 124 when it ran out of time.
limited() {
	local limit=$1 rc=0
	shift
	if [[ -n ${DEADLINE:-} ]]; then
		local left=$((DEADLINE - SECONDS))
		((left > 0)) || return 124
		if ((limit == 0 || left < limit)); then
			limit=${left}
		fi
	fi
	if ((limit == 0)); then
		"$@" || rc=$?
	else
		timeout --kill-after=1m "${limit}" "$@" || rc=$?
		# Killed when it ignored the TERM
		((rc != 137)) || rc=124
	fi
	return "${rc}"
}

# Field $2 of /proc/$1/stat, counting from the one after "(comm)": 1 is the
# state, 2 the parent PID. Nothing when the process is gone.
proc_stat() {
	local stat fields
	read -r stat 2> /dev/null < "/proc/$1/stat" || return 0
	# comm may contain spaces and parens
	read -r -a fields <<< "${stat##*) }"
	echo "${fields[$2 - 1]}"
}

# Stops every process in the container except PID 1 (`sleep infinity`), this
# script's own chain of parents and the PIDs given. Only call it while nothing
# else of ours runs. Builds that Claude started in the background, or one that
# timed out and is still winding down, would otherwise compete with what comes
# next for the CPU and portage's locks. Killing emerge alone isn't enough: the
# build processes it started can outlive it.
stop_strays() {
	local -A keep=([1]=1)
	local pid=${BASHPID} p i state strays=() alive
	for p in "$@"; do
		[[ -z ${p} ]] || keep[${p}]=1
	done
	while ((pid > 1)); do
		keep[${pid}]=1
		pid=$(proc_stat "${pid}" 2)
		pid=${pid:-0}
	done
	for p in /proc/[0-9]*; do
		p=${p#/proc/}
		[[ -z ${keep[${p}]:-} ]] || continue
		# Zombies are done, nobody reaps them under `sleep infinity`
		state=$(proc_stat "${p}" 1)
		[[ -z ${state} || ${state} == Z ]] || strays+=("${p}")
	done
	((${#strays[@]})) || return 0
	echo ">>> stopping ${#strays[@]} leftover processes"
	kill -TERM "${strays[@]}" 2> /dev/null || true
	for ((i = 0; i < 60; i++)); do
		alive=()
		for p in "${strays[@]}"; do
			state=$(proc_stat "${p}" 1)
			[[ -z ${state} || ${state} == Z ]] || alive+=("${p}")
		done
		((${#alive[@]})) || return 0
		strays=("${alive[@]}")
		sleep 1
	done
	kill -KILL "${strays[@]}" 2> /dev/null || true
}

# Runs gentoo.sh <step> <atom> ($1, $2) within the time left, and stops what it
# left behind when it ran out of time.
limited_step() {
	local rc=0
	limited 0 "${SELF}" "$@" || rc=$?
	if ((rc == 124)); then
		echo ">>> stopped: out of time"
		stop_strays "${follow_pid:-}"
	fi
	return "${rc}"
}

check_and_build() {
	local cp=$1 ver=$2
	# Only the new version: the previous one may be dropped by this bump, and
	# CI checks the whole package as it ends up
	echo ">>> pkgcheck scan =${cp}-${ver}"
	(cd "${OVERLAY}" && pkgcheck scan --exit error,warning,style -- "=${cp}-${ver}") > "${OUT}/pkgcheck.txt" 2>&1 \
		|| { cat "${OUT}/pkgcheck.txt"; return 1; }
	cat "${OUT}/pkgcheck.txt"
	echo ">>> build =${cp}-${ver}"
	limited_step build "=${cp}-${ver}"
}

# Runs a command with its output in $1, which is also followed in the step log.
# Not with a pipe to tee: processes left over from a timed-out build would keep
# that pipe, and with it this function, open. follow_pid is the tail, which
# stop_strays must leave alone.
follow() {
	local log=$1 rc=0
	shift
	: > "${log}"
	tail -f -n +1 "${log}" &
	follow_pid=$!
	"$@" >> "${log}" 2>&1 || rc=$?
	# Let tail catch up before stopping it
	sleep 1
	kill "${follow_pid}" 2> /dev/null || true
	wait "${follow_pid}" 2> /dev/null || true
	follow_pid=
	return "${rc}"
}

# pkgcheck and build one version into $log
verify() {
	follow "$3" check_and_build "$1" "$2"
}

# verify, setting the caller's timed_out when it ran out of time. Past the
# deadline it doesn't start, so build.log keeps the last attempt.
try_verify() {
	if [[ -n ${DEADLINE:-} ]] && ((SECONDS >= DEADLINE)); then
		timed_out=true
		return 124
	fi
	local rc=0
	verify "$@" || rc=$?
	((rc != 124)) || timed_out=true
	return "${rc}"
}

install_claude() {
	command -v claude > /dev/null || curl -fsSL https://claude.ai/install.sh | bash > /dev/null
}

claude_round() {
	local round=$1
	# Claude only sees its working directories: add the unpacked sources and
	# the distfiles, which the prompt points it to
	local args=(-p --max-turns "${CLAUDE_MAX_TURNS}" --permission-mode acceptEdits --allowedTools "${CLAUDE_TOOLS}"
		--add-dir /var/tmp/portage --add-dir /var/cache/distfiles)
	((round > 1)) && args+=(--continue)
	# The whole transcript, with every command Claude ran and what it got back
	args+=(--output-format stream-json --verbose)
	local rc=0 out=${OUT}/claude-round-${round}
	# A Bash command may take the whole round, so Claude can wait for a build
	# in the foreground. By default it gets 10 minutes, after which the command
	# moves to the background, where -p runs stop it 10 minutes later, and
	# Claude ends up restarting builds that are still running.
	local bash_ms=$((CLAUDE_ROUND_MINUTES * 60 * 1000))
	(cd "${OVERLAY}" && CLAUDE_CODE_OAUTH_TOKEN=${claude_token} BASH_DEFAULT_TIMEOUT_MS=${bash_ms} \
		BASH_MAX_TIMEOUT_MS=${bash_ms} limited "$((CLAUDE_ROUND_MINUTES * 60))" claude "${args[@]}") \
		> "${out}.jsonl" 2>&1 || rc=$?
	stop_strays
	# Claude's final message to claude-round-N.txt, the commands it wasn't
	# allowed to run to denied.txt (publish lists them). The token is taken out
	# of the transcript, which is uploaded: GitHub only masks it in logs.
	echo ">>> Claude round ${round}: $(REDACT=${claude_token} "${AUTOBUMP[@]}" transcript "${out}.jsonl" "${out}.txt" \
		"${OUT}/denied.txt" || echo "?")"
	return "${rc}"
}

# Fingerprint of the package directory, to tell whether Claude changed anything
pkg_state() {
	git add -A -- "$1" && git diff --cached -- "$1" | sha1sum
}

job() {
	local cp=$1 old=$2 new=$3 mode=$4 drop_old=$5 url=$6
	local status=failed bumped=false round reason="" timed_out=false
	# Only the claude process gets the token, our own builds don't see it
	local claude_token=${CLAUDE_CODE_OAUTH_TOKEN:-}
	unset CLAUDE_CODE_OAUTH_TOKEN
	# Stop with time left to save the cache and upload the results
	if [[ -n ${BUDGET_MINUTES:-} ]]; then
		DEADLINE=$((SECONDS + BUDGET_MINUTES * 60))
		echo ">>> time budget: ${BUDGET_MINUTES} minutes, until $(date -u -d "+${BUDGET_MINUTES} minutes" +%H:%M) UTC"
	fi

	rm -rf "${OUT}"
	mkdir -p "${OUT}"
	cd "${OVERLAY}"
	git config user.name autobump
	git config user.email autobump@localhost

	echo ">>> ${cp}: ${old} -> ${new} (${mode})"
	if "${AUTOBUMP[@]}" bump "${cp}" "${new}" > "${OUT}/build.log" 2>&1; then
		bumped=true
		# ai-mode packages go straight to Claude, unless there is no token
		if [[ ${mode} == pr || -z ${claude_token} ]] && try_verify "${cp}" "${new}" "${OUT}/build.log"; then
			status="pr"
		fi
	fi
	echo ">>> mechanical bump: $([[ ${status} == pr ]] && echo built || echo "not built")"

	if [[ ${status} == failed && -n ${claude_token} && ${timed_out} == false ]]; then
		install_claude
		local prompt_args=(--url "${url}") before rc=0 rounds=${CLAUDE_ROUNDS}
		# Hand over the log only when something actually failed
		if [[ ${mode} == pr || ${bumped} == false ]]; then
			prompt_args+=(--log "${OUT}/build.log")
		fi
		# Claude needs the package's toolchain (Rust, Go, .NET, ...) to unpack and
		# inspect it. The mechanical build only installs it when it gets that far:
		# not in ai mode, or when pkgcheck fails first. Otherwise this is quick.
		echo ">>> build dependencies of =${cp}-${new}"
		follow "${OUT}/deps.log" limited_step deps "=${cp}-${new}" || rc=$?
		case ${rc} in
			0) ;;
			124) timed_out=true rounds=0 ;;
			*) prompt_args+=(--deps-log "${OUT}/deps.log") ;;
		esac
		before=$(pkg_state "${cp}")
		for ((round = 1; round <= rounds; round++)); do
			local stop=$((CLAUDE_ROUND_MINUTES * 60))
			if [[ -n ${DEADLINE:-} ]] && ((DEADLINE - SECONDS < stop)); then
				stop=$((DEADLINE - SECONDS))
			fi
			echo ">>> Claude round ${round}, stops by $(date -u -d "+${stop} seconds" +%H:%M) UTC"
			rc=0
			if ((round == 1)); then
				"${AUTOBUMP[@]}" prompt "${cp}" "${old}" "${new}" --round-minutes "${CLAUDE_ROUND_MINUTES}" \
					--tools "${CLAUDE_TOOLS}" "${prompt_args[@]}" | claude_round 1 || rc=$?
			else
				{
					echo "Verification failed again. Fix it and update .autobump-out/ai-summary.md."
					echo "Tail of the verification log:"
					echo '```'
					tail -n 150 "${OUT}/build.log"
					echo '```'
				} | claude_round "${round}" || rc=$?
			fi
			case ${rc} in
				0) ;;
				124) echo ">>> Claude round ${round} ran out of time" ;;
				*) echo ">>> Claude exited with an error, see claude-round-${round}.txt" ;;
			esac
			if try_verify "${cp}" "${new}" "${OUT}/build.log"; then
				# Unchanged by Claude means it was a mechanical bump after all
				if [[ $(pkg_state "${cp}") == "${before}" ]]; then
					status="pr"
				else
					status="ai"
				fi
				break
			fi
			# Another round won't do better after an error or a time limit
			if ((rc != 0)) || [[ ${timed_out} == true ]]; then
				break
			fi
		done
	fi
	if [[ ${timed_out} == true ]]; then
		reason=timeout
		echo ">>> out of time after ${BUDGET_MINUTES} minutes"
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

	python3 -c 'import json, sys; json.dump(dict(zip(("atom", "old", "new", "mode", "status", "url", "reason", "budget"), sys.argv[2:])), open(sys.argv[1], "w"))' \
		"${OUT}/result.json" "${cp}" "${old}" "${new}" "${mode}" "${status}" "${url}" "${reason}" "${BUDGET_MINUTES:-}"
}

"$@"
