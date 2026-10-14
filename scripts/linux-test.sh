#!/bin/bash
# Builds and tests MetalCreator on Linux in Docker (OrbStack on this Mac runs aarch64 containers; CI runs the same script
# on x86_64 and aarch64 runners). Cross-platform spec 2.5, 2.6.
#
#   scripts/linux-test.sh [build|test|smoke|all]    default: all
#     build   swift build
#     test    swift test, judged by the pass rule below
#     smoke   the app's --self-test, then --smoke-test 20 (the real window over SDL's offscreen renderers: a first frame within 20 s)
#     all     the three, in that order
#   scripts/linux-test.sh clean                     removes this track's build volume
#
# Needs MetalUI checked out beside this repository (../MetalUI), which Package.swift's path dependency expects. The repository
# is mounted read-write and MetalUI read-only; build products live in a named volume, so macOS's .build is untouched and a
# rerun is incremental.
#
# Pass rule for `test` (spec 2.5): exit 0, no "recorded an issue" or "failed after" line, and EXPECTED_TEST_RUNS lines
# "Test run with" (one per test target that has tests on Linux; macOS has one more, CreatorOCCTTests).
#
# Environment: XP_TRACK names the track (default xp-1), which names the container and the volume, so a script run kills only
# its own container. EXPECTED_TEST_RUNS overrides the count (10 today).
set -euo pipefail

cd "$(dirname "$0")/.."
REPO=$PWD
if [ ! -d ../MetalUI ]; then
    echo "scripts/linux-test.sh: MetalUI must be checked out beside this repository (../MetalUI)." >&2
    exit 2
fi
METALUI=$(cd ../MetalUI && pwd -P)

TRACK=${XP_TRACK:-xp-1}
EXPECTED_TEST_RUNS=${EXPECTED_TEST_RUNS:-10}
BASE_IMAGE=metalui-portable:latest
IMAGE=metalcreator-linux:latest
NAME=$TRACK-linux
VOLUME=$TRACK-linux-build
LOG=${TMPDIR:-/tmp}/$TRACK-linux-test.log

step=${1:-all}
if [ "$step" = clean ]; then
    docker volume rm "$VOLUME" >/dev/null 2>&1 || true
    exit 0
fi

if ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
    echo "Building $BASE_IMAGE from MetalUI's recipe (once; it builds SDL3 from source)..."
    docker build -t "$BASE_IMAGE" -f "$METALUI/Backends/SDL/linux/Dockerfile" "$METALUI/Backends/SDL"
fi
docker build -q -t "$IMAGE" --build-arg "BASE=$BASE_IMAGE" - < scripts/linux/Dockerfile >/dev/null

# Runs `$1` in the image, from the repository, with the build volume; stops only this track's own container.
in_container() {
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run --rm --name "$NAME" \
        -v "$REPO":/work/MetalCreator -v "$METALUI":/work/MetalUI:ro -v "$VOLUME":/build \
        "$IMAGE" bash -ec "$1"
}

do_build() {
    in_container 'swift build --scratch-path /build'
}

do_smoke() {
    in_container 'bin=$(swift build --scratch-path /build --show-bin-path)/MetalCreatorApp
        "$bin" --self-test
        "$bin" --smoke-test 20'
}

do_test() {
    local status=0
    in_container 'swift test --scratch-path /build' 2>&1 | tee "$LOG" || status=$?
    local clean runs tests
    clean=$(sed $'s/\x1b\\[[0-9;]*m//g' "$LOG")
    runs=$(grep -c "Test run with" <<<"$clean" || true)
    tests=$({ grep "Test run with" <<<"$clean" || true; } | sed -E 's/.*Test run with ([0-9]+) tests.*/\1/' | awk '{ total += $1 } END { print total + 0 }')
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
    all) do_build && do_test && do_smoke ;;
    *) echo "usage: scripts/linux-test.sh [build|test|smoke|all|clean]" >&2; exit 64 ;;
esac
