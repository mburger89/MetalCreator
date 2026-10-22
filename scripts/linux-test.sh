#!/bin/bash
# Builds and tests MetalCreator on Linux in Docker (OrbStack on this Mac runs aarch64 containers; CI runs the same script
# on x86_64 and aarch64 runners). Cross-platform spec 2.5, 2.6.
#
#   scripts/linux-test.sh [build|test|smoke|package|all] [swift test arguments]    default: all
#     build   swift build
#     test    swift test, judged by the pass rule below. Arguments after `test` (for example `--filter CreatorOCCTTests`) go to
#             swift test and switch the count rule off: only the exit code and the issue lines are judged.
#     smoke   the app's --self-test, then --smoke-test 20 (the real window over SDL's offscreen renderers: a first frame within 20 s,
#             and the 3D viewport drew in it)
#     package scripts/package-linux.sh and scripts/package-appimage.sh in the image (the second downloads appimagetool and the
#             AppImage runtime, pinned by version and sha256: it needs the network), then the tarball and the AppImage in dist/ are
#             each run in a clean ubuntu:24.04 (no Swift, no /opt/occt, no MetalUI checkout, no FUSE) and must pass --version and
#             --self-test there (the AppImage with --appimage-extract-and-run); the desktop entry is validated
#     all     build, test and smoke, in that order (not package: a release build is slow)
#   scripts/linux-test.sh clean                     removes this track's build volume
#
# Needs MetalUI checked out beside this repository (../MetalUI), which Package.swift's path dependency expects. The repository
# is mounted read-write and MetalUI read-only; build products live in a named volume, so macOS's .build is untouched and a
# rerun is incremental.
#
# Pass rule for `test` (spec 2.5): exit 0, no "recorded an issue" or "failed after" line, and EXPECTED_TEST_RUNS lines
# "Test run with" (one per test target that has tests: twelve on Linux, Windows and macOS since xp-2 put CreatorOCCTTests on
# every platform).
#
# The image draws on Mesa's lavapipe, a CPU Vulkan driver, so the SDL_GPU viewport renders here with no GPU in the machine. Every
# container sets XP_REQUIRE_GPU=1: the viewport's renderer suites skip when no SDL_GPU device answers, and with this set a missing
# device fails SDLGPUAvailabilityTests instead, so a runner that lost its driver cannot pass by running none of them (MetalUI's
# METALUI_REQUIRE_GPU).
#
# The viewport's HLSL shaders are compiled at build time (plan xp-3, user decision U1(b)): before build, test, smoke and package this
# script runs scripts/build-shaders.sh in the image, which holds the pinned SDL_shadercross (scripts/shadercross.env; the Dockerfile's
# `shadercross` stage, built once and cached like OpenCascade's) and builds MetalUI's MetalUICompileShaders into the track's volume. The
# output, Shaders/viewport/compiled in the worktree, is git-ignored; a run with nothing to recompile takes a second. If shadercross is
# missing or a shader fails, the step stops with a message that names the tool and its pinned commit.
#
# Environment: XP_TRACK names the track (default xp-1), which names the container and the volume, so a script run kills only
# its own container. EXPECTED_TEST_RUNS overrides the count (12 today). IMAGE names the image this script builds and runs
# (default metalcreator-linux:latest; a track that must not replace another's image sets its own). OpenCascade is built from
# source in an image stage, which is the slow part: OCCT_IMAGE names an image that already holds /opt/occt (CI builds the
# stage alone with buildx and its layer cache and passes the result), else the stage is built here and Docker's layer cache
# keeps it. OCCT_JOBS sets the parallelism of
# that OpenCascade build (default 6; a different value is a different Docker cache key and rebuilds OpenCascade). SHADERCROSS_IMAGE
# and SHADERCROSS_JOBS do the same for the `shadercross` stage (CI passes the image it built with buildx).
set -euo pipefail

cd "$(dirname "$0")/.."
REPO=$PWD
if [ ! -d ../MetalUI ]; then
    echo "scripts/linux-test.sh: MetalUI must be checked out beside this repository (../MetalUI)." >&2
    exit 2
fi
METALUI=$(cd ../MetalUI && pwd -P)

TRACK=${XP_TRACK:-xp-1}
EXPECTED_TEST_RUNS=${EXPECTED_TEST_RUNS:-12}
BASE_IMAGE=metalui-portable:latest
IMAGE=${IMAGE:-metalcreator-linux:latest}
NAME=$TRACK-linux
VOLUME=$TRACK-linux-build
LOG=${TMPDIR:-/tmp}/$TRACK-linux-test.log

step=${1:-all}
shift || true
TEST_ARGS=("$@")
if [ "$step" = clean ]; then
    docker volume rm "$VOLUME" >/dev/null 2>&1 || true
    exit 0
fi

if ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
    echo "Building $BASE_IMAGE from MetalUI's recipe (once; it builds SDL3 from source)..."
    docker build -t "$BASE_IMAGE" -f "$METALUI/Backends/SDL/linux/Dockerfile" "$METALUI/Backends/SDL"
fi
if [ "${METALCREATOR_IMAGE_PREBUILT:-}" != 1 ]; then
    docker build -q -t "$IMAGE" --build-arg "BASE=$BASE_IMAGE" ${OCCT_IMAGE:+--build-arg "OCCT_IMAGE=$OCCT_IMAGE"} \
        ${OCCT_JOBS:+--build-arg "OCCT_JOBS=$OCCT_JOBS"} ${SHADERCROSS_IMAGE:+--build-arg "SHADERCROSS_IMAGE=$SHADERCROSS_IMAGE"} \
        ${SHADERCROSS_JOBS:+--build-arg "SHADERCROSS_JOBS=$SHADERCROSS_JOBS"} - < scripts/linux/Dockerfile >/dev/null
fi

# Runs `$1` in the image, from the repository, with the build volume (and `$DOCKER_EXTRA`, if set); stops only this track's own
# container.
in_container() {
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    docker run --rm --name "$NAME" \
        -e XP_REQUIRE_GPU=1 -v "$REPO":/work/MetalCreator -v "$METALUI":/work/MetalUI:ro -v "$VOLUME":/build ${DOCKER_EXTRA:-} \
        "$IMAGE" bash -ec "$1"
}

# Compiles Shaders/viewport into Shaders/viewport/compiled in the worktree (git-ignored), MetalUI's tool built in the track's volume;
# a second when nothing changed. Every step that builds the app runs it first (`|| return 1`: `set -e` is off inside a function
# called from `&&`, as `all` calls them).
compile_shaders() {
    in_container 'METALUI_TOOLS_SCRATCH=/build/metalui-tools scripts/build-shaders.sh'
}

do_build() {
    compile_shaders || return 1
    in_container 'swift build --scratch-path /build'
}

do_smoke() {
    compile_shaders || return 1
    in_container 'bin=$(swift build --scratch-path /build --show-bin-path)/MetalCreatorApp
        "$bin" --self-test
        "$bin" --smoke-test 20'
}

# The release tarball and AppImage, built in the image and then run where nothing of the build machine exists (no Swift, no
# /opt/occt, no FUSE).
do_package() {
    local arch
    arch=$(uname -m | sed 's/arm64/aarch64/')
    rm -f dist/MetalCreator-*-linux-"$arch".tar.gz dist/MetalCreator-*-linux-"$arch".AppImage
    compile_shaders || return 1
    DOCKER_EXTRA="-v $VOLUME-package:/build-package" in_container '
        desktop-file-validate packaging/linux/com.metalcreator.MetalCreator.desktop
        METALCREATOR_SCRATCH=/build-package scripts/package-linux.sh
        scripts/package-appimage.sh'
    local tarball appimage
    tarball=$(ls dist/MetalCreator-*-linux-*.tar.gz | head -n 1)
    echo "Checking $tarball in a clean ubuntu:24.04..."
    docker rm -f "$NAME-clean" >/dev/null 2>&1 || true
    docker run --rm --name "$NAME-clean" -v "$REPO/dist":/dist:ro ubuntu:24.04 bash -ec '
        test ! -e /opt/occt && test ! -e /work
        mkdir /tmp/unpacked && tar -xzf /dist/'"$(basename "$tarball")"' -C /tmp/unpacked
        cd /tmp/unpacked/MetalCreator-*
        ./MetalCreator --version
        ./MetalCreator --self-test
        LD_DEBUG=libs ./MetalCreator --version >/dev/null 2>/tmp/ld.txt
        grep -q "RUNPATH from file ./MetalCreator" /tmp/ld.txt
        if grep -q /opt/occt /tmp/ld.txt; then echo "the loader searched /opt/occt" >&2; exit 1; fi
        test -f MetalUISDLShaders/SOURCE.sha256 && ls lib | grep -q "^libTKernel.so.7.9$"
        cd share/doc/metalcreator
        for f in NOTICE.txt LICENSE_LGPL_21.txt OCCT_LGPL_EXCEPTION.txt SDL3-LICENSE.txt Swift-LICENSE.txt; do test -s "$f"; done
        grep -q "V7_9_3" NOTICE.txt && grep -q "LGPL" NOTICE.txt'
    echo "Linux tarball: PASS ($tarball)"
    appimage=$(ls dist/MetalCreator-*-linux-*.AppImage | head -n 1)
    echo "Checking $appimage in a clean ubuntu:24.04 (no FUSE: --appimage-extract-and-run)..."
    docker rm -f "$NAME-clean" >/dev/null 2>&1 || true
    docker run --rm --name "$NAME-clean" -v "$REPO/dist":/dist:ro ubuntu:24.04 bash -ec '
        test ! -e /opt/occt && test ! -e /work && test ! -e /dev/fuse
        cp /dist/'"$(basename "$appimage")"' /tmp/MetalCreator.AppImage && chmod +x /tmp/MetalCreator.AppImage
        cd /tmp
        ./MetalCreator.AppImage --appimage-extract-and-run --version
        ./MetalCreator.AppImage --appimage-extract-and-run --self-test
        LD_DEBUG=libs ./MetalCreator.AppImage --appimage-extract-and-run --version >/dev/null 2>/tmp/ld.txt
        grep -q "RUNPATH from file .*/usr/metalcreator/MetalCreator" /tmp/ld.txt
        if grep -q /opt/occt /tmp/ld.txt; then echo "the loader searched /opt/occt" >&2; exit 1; fi
        ./MetalCreator.AppImage --appimage-extract "usr/metalcreator/share/mime/packages/*.xml" >/dev/null
        test -f squashfs-root/usr/metalcreator/share/mime/packages/com.metalcreator.MetalCreator.xml
        ./MetalCreator.AppImage --appimage-extract "usr/metalcreator/share/doc/metalcreator/*" >/dev/null
        cd squashfs-root/usr/metalcreator/share/doc/metalcreator
        for f in NOTICE.txt LICENSE_LGPL_21.txt OCCT_LGPL_EXCEPTION.txt SDL3-LICENSE.txt Swift-LICENSE.txt \
                 AppImage-runtime/type2-runtime-LICENSE.txt AppImage-runtime/libfuse-LGPL2.txt AppImage-runtime/squashfuse-LICENSE.txt \
                 AppImage-runtime/zstd-LICENSE.txt; do test -s "$f"; done
        grep -q "type2-runtime" NOTICE.txt'
    echo "Linux AppImage: PASS ($appimage)"
}

do_test() {
    local status=0 quoted=""
    # printf %q keeps a filter like 'A|B' one word through the container's shell.
    if [ "${#TEST_ARGS[@]}" -gt 0 ]; then printf -v quoted ' %q' "${TEST_ARGS[@]}"; fi
    compile_shaders || { echo "Linux: FAIL (the viewport's shaders did not compile; see above)" >&2; return 1; }
    in_container "swift test --scratch-path /build$quoted" 2>&1 | tee "$LOG" || status=$?
    local clean runs tests
    clean=$(sed $'s/\x1b\\[[0-9;]*m//g' "$LOG")
    runs=$(grep -c "Test run with" <<<"$clean" || true)
    tests=$({ grep "Test run with" <<<"$clean" || true; } | sed -E 's/.*Test run with ([0-9]+) tests.*/\1/' | awk '{ total += $1 } END { print total + 0 }')
    # A filtered run has no fixed number of "Test run with" lines,
    # but it must have run something: a filter that matches nothing, or a crash before any run line, is a failure.
    if [ "${#TEST_ARGS[@]}" -gt 0 ]; then
        EXPECTED_TEST_RUNS=$runs
        [ "$runs" -ge 1 ] || status=1
    fi
    if [ "$status" -ne 0 ] || grep -qE "recorded an issue|failed after" <<<"$clean" || [ "$runs" -ne "$EXPECTED_TEST_RUNS" ]; then
        echo "Linux: FAIL (exit $status, $runs of $EXPECTED_TEST_RUNS 'Test run with' lines; log: $LOG)" >&2
        return 1
    fi
    echo "Linux: PASS ($runs 'Test run with' lines, ${tests:-0} tests; log: $LOG)"
}

case $step in
    build) do_build ;;
    test) do_test ;;
    smoke) do_smoke ;;
    package) do_package ;;
    all) do_build && do_test && do_smoke ;;
    *) echo "usage: scripts/linux-test.sh [build|test|smoke|package|all|clean]" >&2; exit 64 ;;
esac
