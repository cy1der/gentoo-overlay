#!/usr/bin/env bash
# Lantern Engine expects one writable folder: bb-start writes its generated files into engine/out
# beside the programs, and settings, saves, mods and logs go in the folder itself. That folder is
# made in the user's data directory from symlinks into the installed copy, refreshed on every
# start so it always matches the installed version.
#
#   lantern-engine [game folder] [bb-probe options...]   (upstream's lantern.sh)
#   lantern-engine-launcher                              (the launcher)
set -euo pipefail

dist=@DIST@
home=${LANTERN_ENGINE_HOME:-${XDG_DATA_HOME:-${HOME}/.local/share}/lantern-engine}

# Replaces what upstream's self-update may have unpacked in place of a link.
relink() {
	if [[ -e $2 && ! -L $2 ]]; then
		rm -rf -- "$2"
	fi
	ln -sfn -- "$1" "$2"
}

mkdir -p -- "${home}/engine/out"
# Links left from an earlier version (or a disabled USE flag) to files no longer installed.
find "${home}" "${home}/engine" "${home}/engine/out" -maxdepth 1 -xtype l -lname "${dist}/*" -delete
for entry in "${dist}"/engine/*; do
	[[ ${entry##*/} == out ]] || relink "${entry}" "${home}/engine/${entry##*/}"
done
for entry in "${dist}"/engine/out/*; do
	relink "${entry}" "${home}/engine/out/${entry##*/}"
done
for name in lantern.sh package.json LICENSE NOTICE; do
	relink "${dist}/${name}" "${home}/${name}"
done

export PYTHON=${PYTHON:-@PYTHON@}

case ${0##*/} in
	*-launcher)
		# The launcher finds the engine from its working directory, and points "Add to Steam"
		# at this script.
		cd -- "${home}"
		export LANTERN_ENGINE_LAUNCHER=@LAUNCHER_SCRIPT@
		for DOTNET_ROOT in @DOTNET_ROOTS@; do
			[[ -d ${DOTNET_ROOT} ]] && break
		done
		export DOTNET_ROOT
		exec "@LAUNCHER@" "$@"
		;;
	*)
		exec "${home}/lantern.sh" "$@"
		;;
esac
