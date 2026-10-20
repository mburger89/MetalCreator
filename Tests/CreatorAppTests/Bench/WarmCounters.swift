#if canImport(Metal)
import MetalUITesting

/// Per-frame MetalUI work counters collected over the timed warm frames of a bench row, printed as one `BENCH counters`
/// line (median / max per frame) plus the summed `retainedTranslationRefusedReasons`. The warm rows print these next to
/// their element requests so a change of retained work shows up in docs/verification/performance.md.
struct WarmCounters {
    private static var keys: [(String, KeyPath<FrameWork, Int>)] { [
        ("elementRequests", \.elementRequests), ("elementPrepaints", \.elementPrepaints), ("elementPaints", \.elementPaints),
        ("rasterizedPixels", \.rasterizedPixels), ("retainedHits", \.retainedHits), ("retainedMisses", \.retainedMisses),
        ("retainedGrafts", \.retainedGrafts), ("retainedTranslated", \.retainedTranslated),
        ("retainedTranslationRefused", \.retainedTranslationRefused), ("contentEvaluations", \.contentEvaluations),
        ("contentSkips", \.contentSkips),
    ] }
    private var samples: [[Int]] = Array(repeating: [], count: keys.count)
    private var refused: [String: Int] = [:]
    private var frames = 0

    /// Adds one warm frame's work (the presented frames `TestWindow.frameWork` holds since the last reset).
    mutating func add(_ work: [FrameWork]) {
        for (index, key) in Self.keys.enumerated() { samples[index].append(work.reduce(0) { $0 + $1[keyPath: key.1] }) }
        for item in work { refused.merge(item.retainedTranslationRefusedReasons, uniquingKeysWith: +) }
        frames += 1
    }

    /// Prints `BENCH counters <name> (median/max per frame): …` and `BENCH refused <name> (summed over N frames): …`.
    func report(_ name: String) {
        let parts = Self.keys.enumerated().map { index, key -> String in
            let sorted = samples[index].sorted()
            return "\(key.0) \(sorted.isEmpty ? 0 : sorted[sorted.count / 2])/\(sorted.last ?? 0)"
        }
        print("BENCH counters \(name) (median/max per frame): " + parts.joined(separator: ", "))
        let reasons = refused.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        print("BENCH refused \(name) (summed over \(frames) frames): \(reasons.isEmpty ? "none" : reasons)")
    }
}
#endif
