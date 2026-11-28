# The jar's directory isn't writable, keep data in the XDG location rather
# than ~/morphe (still used if it already exists).
if [[ -z ${MORPHE_DATA_DIR} && ! -d ${HOME}/morphe ]]; then
	export MORPHE_DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/morphe"
fi

# Java doesn't know XWayland WMs such as niri's xwayland-satellite, sway or
# Hyprland, and wouldn't follow their resizes. GNOME's and KDE's reparent.
if [[ -z ${_JAVA_AWT_WM_NONREPARENTING} && -n ${WAYLAND_DISPLAY} &&
	${XDG_CURRENT_DESKTOP} != *GNOME* && ${XDG_CURRENT_DESKTOP} != *KDE* ]]; then
	export _JAVA_AWT_WM_NONREPARENTING=1
fi

# Without arguments upstream downloads the GUI's runtime jars and restarts
# itself with this flag. They are installed already, so start the GUI directly.
if [[ $# -eq 0 && -n ${DISPLAY} ]]; then
	set -- --internal-gui-subprocess
fi

