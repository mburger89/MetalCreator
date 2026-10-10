#!/bin/bash
# Runs the spec §7.3 benchmarks (Tests/CreatorAppTests/Bench) in a release build and prints their BENCH lines.
# They are skipped by a plain `swift test`; this sets METALCREATOR_BENCH=1 and builds with -c release, because a debug
# build of MetalUI draws about 45× slower (docs/metalui-gaps.md PERF-a). Record the numbers in
# docs/verification/performance.md.
#
# usage: scripts/bench.sh [filter]      filter defaults to "Bench" (every benchmark suite)
# The suites run one at a time (--no-parallel), so they don't time each other. Run on an otherwise idle machine: the
# first lines printed are the machine and its load average, which belong next to the numbers. The full output is kept
# in .build/bench.log.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILTER="${1:-Bench}"
LOG="$ROOT/.build/bench.log"
mkdir -p "$ROOT/.build"

cd "$ROOT"
printf 'BENCH machine: %s, %s cores, macOS %s\n' "$(sysctl -n hw.model)" "$(sysctl -n hw.ncpu)" "$(sw_vers -productVersion)"
printf 'BENCH load before: %s\n' "$(uptime | sed 's/.*load averages*: //')"
if ! METALCREATOR_BENCH=1 swift test -c release --no-parallel --filter "$FILTER" >"$LOG" 2>&1; then
    grep -E "BENCH|recorded an issue|error:" "$LOG" || true
    printf 'bench: the run failed; see %s\n' "$LOG" >&2
    exit 1
fi
grep "BENCH" "$LOG" || { printf 'bench: no BENCH lines; see %s\n' "$LOG" >&2; exit 1; }
printf 'BENCH load after: %s\n' "$(uptime | sed 's/.*load averages*: //')"
