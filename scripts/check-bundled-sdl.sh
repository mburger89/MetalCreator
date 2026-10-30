#!/bin/bash
# Fails unless the libSDL3.so.0 given is a desktop SDL (XP-G33; the 2026-10-30 Linux VM check found packages whose bundled SDL had only the
# dummy, evdev and offscreen drivers, so no window opened on a desktop): it must contain the x11, wayland, offscreen and dummy video drivers
# (SDL registers each by name; MetalUI's check-video-drivers.c asks SDL_GetVideoDriver for the same four), and its DT_NEEDED must name no
# X11, xcb, Wayland or libdecor library: SDL dlopens those at run time (-DSDL_X11_SHARED, -DSDL_WAYLAND_SHARED), so the package still starts
# on a headless or minimal machine with none of them installed.
#
# usage: scripts/check-bundled-sdl.sh path/to/libSDL3.so.0     (scripts/package-linux.sh runs it on the lib/ it is about to ship)
set -euo pipefail

lib="${1:?usage: check-bundled-sdl.sh path/to/libSDL3.so.0}"
[ -s "$lib" ] || { echo "check-bundled-sdl: $lib is missing or empty" >&2; exit 1; }
status=0
# `-n 3`: strings drops anything under four characters by default, which includes "x11". Captured first: `strings | grep -q` under pipefail fails when grep exits early and strings dies of SIGPIPE.
names=$(strings -a -n 3 "$lib")
for driver in x11 wayland offscreen dummy; do
    if ! grep -qx "$driver" <<<"$names"; then
        echo "check-bundled-sdl: $lib has no '$driver' video driver" >&2
        status=1
    fi
done
needed=$(readelf -d "$lib" | sed -nE 's/.*\(NEEDED\).*\[(.*)\]/\1/p')
if linked=$(grep -E '^lib(X11|Xext|Xcursor|Xi|Xfixes|Xrandr|Xss|xcb|wayland|decor)' <<<"$needed"); then
    echo "check-bundled-sdl: $lib links $(tr '\n' ' ' <<<"$linked")at load time; they must be dlopen'd" >&2
    status=1
fi
[ "$status" -eq 0 ] && echo "check-bundled-sdl: $lib has the x11, wayland, offscreen and dummy video drivers and links no X11/Wayland library"
exit "$status"
