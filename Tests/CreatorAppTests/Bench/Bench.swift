// Test fixture file: the switch and the shared numbers of the §7.3 benchmarks (docs/verification/performance.md).
import Foundation
import Testing

/// The §7.3 benchmarks run only when asked (`METALCREATOR_BENCH=1`, which `scripts/bench.sh` sets) and only in a
/// release build: a debug build of MetalUI draws about 45× slower (docs/metalui-gaps.md PERF-a), so its numbers say
/// nothing about the app. They print `BENCH …` lines and never assert a time, so the default test run skips them and
/// can't flake on a busy machine.
enum Bench {
    /// True when the environment asks for the benchmarks.
    static let isRequested = ProcessInfo.processInfo.environment["METALCREATOR_BENCH"] == "1"

    /// True in a release (optimized) build of the tests.
    static var isRelease: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    /// One frame at 60 fps, in milliseconds (spec §7.3).
    static let frameBudget = 1000.0 / 60

    /// The fillet drag's budget, command to frame, in milliseconds (spec §7.3).
    static let dragBudget = 100.0

    /// The window the benchmarks draw: 1440 × 900 points at scale 2, a 15-inch MacBook's default.
    static let windowWidth = 1440.0
    static let windowHeight = 900.0
    static let scale = 2.0

    /// Records an issue and returns false in a debug build, so a benchmark never prints debug numbers.
    static func requireRelease(sourceLocation: SourceLocation = #_sourceLocation) -> Bool {
        if !isRelease {
            Issue.record("Benchmarks run in a release build: scripts/bench.sh (swift test -c release).",
                         sourceLocation: sourceLocation)
        }
        return isRelease
    }
}
