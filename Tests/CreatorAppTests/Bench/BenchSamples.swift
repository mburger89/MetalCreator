// Test fixture file: timings collected by a benchmark and the line it prints for them.

/// Durations of one measured step, in milliseconds, and their summary (docs/verification/performance.md).
struct BenchSamples {
    /// What was measured, e.g. "pan-50 window-cpu".
    let name: String
    private(set) var values: [Double] = []

    init(_ name: String) {
        self.name = name
    }

    mutating func append(_ milliseconds: Double) {
        values.append(milliseconds)
    }

    /// Adds the time from `start` to `end`.
    mutating func append(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) {
        values.append((end - start) / .milliseconds(1))
    }

    /// The middle value (the mean of the two middle values for an even count); 0 when empty.
    var median: Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// The nearest-rank 95th percentile: the smallest value at least 95% of the values are at or below; 0 when empty.
    var percentile95: Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let rank = Int((0.95 * Double(sorted.count)).rounded(.up))
        return sorted[max(rank, 1) - 1]
    }

    var maximum: Double { values.max() ?? 0 }

    /// "BENCH <name>: median 1.23 ms, p95 2.34 ms, max 3.45 ms (n 90)", then "; budget 16.67 ms: met" (or "missed")
    /// when the median is judged against `budget`.
    func line(budget: Double? = nil) -> String {
        func ms(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2)).grouping(.never)) + " ms" }
        var text = "BENCH \(name): median \(ms(median)), p95 \(ms(percentile95)), max \(ms(maximum)) (n \(values.count))"
        if let budget {
            text += "; budget \(ms(budget)): \(median <= budget ? "met" : "missed")"
        }
        return text
    }
}
