#!/bin/bash
# Runs the preview triangle cap sweep (Tests/CreatorAppTests/Bench/PreviewSweepBench.swift, Errata D15) in a release build and
# prints its BENCH lines, ending with `BENCH preview-sweep cap-candidate N`: the last rung of the ladder (about 0.25M to 8M
# triangles) before the first rung that misses the rule in docs/verification/performance.md, "Preview triangle cap (D15): measured".
#
# usage: scripts/preview-sweep.sh        (no arguments; it is scripts/bench.sh PreviewSweepBench)
# Run it on an otherwise idle Mac, with nothing else building or testing: a busy GPU or CPU inflates every frame time and the cap
# it picks. The machine and its load average come first in the output; keep them beside the numbers. The full output is in
# .build/bench.log.
set -euo pipefail

exec "$(cd "$(dirname "$0")" && pwd)/bench.sh" PreviewSweepBench
