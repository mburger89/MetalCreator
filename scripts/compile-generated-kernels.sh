#!/bin/bash
# Compiles the implicit engine's generated HLSL kernels offline (plan xp-c, task 3), until MetalUI's run-time compiler (gap XP-G25) compiles them
# while the app runs: the sources GeneratedKernelExport wrote to .build/generated-kernels/source become SPIR-V, DXIL, MSL and reflection JSON in
# .build/generated-kernels/compiled, through MetalUI's MetalUICompileShaders and the pinned SDL_shadercross (scripts/shadercross.env), as
# MetalUI's CompileShadersOnBuild plugin compiles the viewport's. Only the sources not compiled yet are compiled (a name is its text's digest). Run in the Linux image
# by scripts/linux-test.sh kernels. A source DXC refuses stops the script naming it: that is a generator bug, never a test to skip.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
. scripts/shadercross.env
SHADERCROSS=${SHADERCROSS:-/opt/shadercross/bin/shadercross}
[ -x "$SHADERCROSS" ] || { echo "scripts/compile-generated-kernels.sh: SDL_shadercross ($SHADERCROSS_COMMIT) was not found at $SHADERCROSS" >&2; exit 69; }
METALUI=$(cd "$ROOT/../MetalUI" && pwd -P)
SCRATCH=${METALUI_TOOLS_SCRATCH:-$ROOT/.build/metalui-tools}
KERNELS=$ROOT/.build/generated-kernels
STAGE=$KERNELS/stage
mkdir -p "$KERNELS/compiled"
rm -rf "$STAGE" && mkdir -p "$STAGE"
shopt -s nullglob
for source in "$KERNELS"/source/*.comp.hlsl; do
    stem=$(basename "$source" .hlsl)
    [ -s "$KERNELS/compiled/$stem.json" ] || cp "$source" "$STAGE/"
done
count=$(find "$STAGE" -name '*.comp.hlsl' | wc -l | tr -d ' ')
if [ "$count" = 0 ]; then echo "The generated kernels are compiled."; exit 0; fi
echo "Compiling $count generated kernels..."
start=$(date +%s.%N)
swift run --package-path "$METALUI" --scratch-path "$SCRATCH" MetalUICompileShaders --no-marker \
    --shadercross "$SHADERCROSS" --source "$STAGE" --out "$STAGE/out"
end=$(date +%s.%N)
cp "$STAGE"/out/* "$KERNELS/compiled/"
echo "COMPILE-TIME $count kernels in $(awk -v s="$start" -v e="$end" 'BEGIN { printf "%.1f", e - s }') s"
