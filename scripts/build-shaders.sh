#!/bin/bash
# Compiles the viewport's SDL_GPU shaders (cross-platform spec section 4, plan xp-3, user decision U1(b)): the HLSL in Shaders/viewport
# becomes SPIR-V (Vulkan), DXIL (Direct3D 12) and MSL, a reflection JSON each, and SOURCE.sha256, in Shaders/viewport/compiled, through
# MetalUI's MetalUICompileShaders (MetalUI S12, docs/packaging.md section 4a), built from the ../MetalUI checkout; this script adds
# INCLUDES.sha256 for the shared header, which MetalUI's marker does not list. Nothing compiled is checked in (the directory is
# git-ignored): every Linux and Windows build makes it. The one tool outside Swift is SDL_shadercross, pinned in scripts/shadercross.env.
#
#   scripts/build-shaders.sh                  uses $SHADERCROSS, else /opt/shadercross/bin/shadercross (the Linux test image), else PATH
#   SHADERCROSS=/path/to/shadercross scripts/build-shaders.sh
#   METALUI_TOOLS_SCRATCH=DIR                 where MetalUI's tool is built (default .build/metalui-tools here; never inside ../MetalUI)
#
# On Linux scripts/linux-test.sh runs this in the test image before swift build, swift test, the smoke step and packaging; CI does the
# same through it. Windows has scripts/build-shaders.ps1. macOS builds Metal only (MSL strings) and never runs this.
#
# Exit codes: 0 the directory is built (or was already current); 69 shadercross is missing or is not the pinned commit; 1 a shader
# failed to compile (the directory is removed, so the tests and --self-test fail loudly rather than run on a half-built one);
# 2 MetalUI is not beside this repository. A rerun with unchanged sources compiles nothing.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
# shellcheck source=scripts/shadercross.env
. scripts/shadercross.env
TOOL="SDL_shadercross ($SHADERCROSS_REPOSITORY, commit $SHADERCROSS_COMMIT, pinned in scripts/shadercross.env)"
fail() { echo "scripts/build-shaders.sh: $2" >&2; exit "$1"; }

SHADERCROSS=${SHADERCROSS:-}
if [ -z "$SHADERCROSS" ]; then
    for candidate in /opt/shadercross/bin/shadercross "$(command -v shadercross || true)"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then SHADERCROSS=$candidate; break; fi
    done
fi
if [ -z "$SHADERCROSS" ] || [ ! -x "$SHADERCROSS" ]; then
    fail 69 "$TOOL was not found. Set SHADERCROSS=/path/to/shadercross, or on Linux run this through scripts/linux-test.sh, whose Docker image builds it (scripts/linux/Dockerfile, stage shadercross). The viewport's shaders are compiled at build time and cannot be built without it."
fi
# The image records the commit it built beside bin/; any other build is refused, so a stale image cannot pass for the pin.
BUILT=$(cat "$(dirname "$SHADERCROSS")/../COMMIT" 2>/dev/null || true)
if [ -n "$BUILT" ] && [ "$BUILT" != "$SHADERCROSS_COMMIT" ]; then
    fail 69 "$SHADERCROSS was built from commit $BUILT, but $TOOL is required. Rebuild it (scripts/linux-test.sh rebuilds the image when the Dockerfile's ARG changes)."
fi
[ -f "$ROOT/../MetalUI/Package.swift" ] || fail 2 "MetalUI must be checked out beside this repository (../MetalUI), as Package.swift expects."
METALUI=$(cd "$ROOT/../MetalUI" && pwd -P)
SCRATCH=${METALUI_TOOLS_SCRATCH:-$ROOT/.build/metalui-tools}

cd Shaders/viewport
shopt -s nullglob
# sha256sum's "<sha256>  <name>" lines for the named files, sorted bytewise by name: the format of MetalUI's SOURCE.sha256
# (SourceMarker.swift), so the same function says whether the directory is current and writes INCLUDES.sha256.
digests() {
    [ "$#" -gt 0 ] || return 0
    local name
    while read -r name; do sha256sum "$name"; done < <(printf '%s\n' "$@" | LC_ALL=C sort)
}
stages=(*.vert.hlsl *.frag.hlsl *.comp.hlsl)
headers=(*.hlsli)
current() {
    [ -f compiled/SOURCE.sha256 ] && [ -f compiled/INCLUDES.sha256 ] || return 1
    [ "$(digests "${stages[@]}")" = "$(cat compiled/SOURCE.sha256)" ] || return 1
    [ "$(digests "${headers[@]}")" = "$(cat compiled/INCLUDES.sha256)" ] || return 1
    local stage kind
    for stage in "${stages[@]}"; do
        for kind in spv msl dxil json; do [ -s "compiled/${stage%.hlsl}.$kind" ] || return 1; done
    done
}
[ "${#stages[@]}" -gt 0 ] || fail 1 "no NAME.vert.hlsl or NAME.frag.hlsl in Shaders/viewport."
if current; then
    echo "Shaders/viewport/compiled is current."
    exit 0
fi

rm -rf compiled
echo "Compiling Shaders/viewport with MetalUI's MetalUICompileShaders and $TOOL..."
if ! swift run --package-path "$METALUI" --scratch-path "$SCRATCH" MetalUICompileShaders \
        --shadercross "$SHADERCROSS" --source "$ROOT/Shaders/viewport" --out "$ROOT/Shaders/viewport/compiled"; then
    rm -rf compiled
    fail 1 "$TOOL failed to compile a shader of Shaders/viewport, or MetalUICompileShaders did not build (the lines above name the file and the complaint). Shaders/viewport/compiled was removed."
fi
digests "${headers[@]}" > compiled/INCLUDES.sha256
echo "Built Shaders/viewport/compiled ($(find compiled -type f | wc -l | tr -d ' ') files)."
