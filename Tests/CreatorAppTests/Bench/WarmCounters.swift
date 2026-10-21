#if canImport(Metal)
import MetalUITesting

/// Per-frame MetalUI work counters collected over the timed warm frames of a bench row, printed as one `BENCH counters`
/// line (median / max per frame) plus the summed `retainedTranslationRefusedReasons` and `retainedIneligibleReasons`. The warm rows print these next to
/// their element requests so a change of retained work shows up in docs/verification/performance.md.
struct WarmCounters {
    private static var keys: [(String, KeyPath<FrameWork, Int>)] { [
        ("elementRequests", \.elementRequests), ("elementPrepaints", \.elementPrepaints), ("elementPaints", \.elementPaints),
        ("rasterizedPixels", \.rasterizedPixels), ("retainedHits", \.retainedHits), ("retainedMisses", \.retainedMisses),
        ("retainedGrafts", \.retainedGrafts), ("retainedTranslated", \.retainedTranslated),
        ("retainedTranslationRefused", \.retainedTranslationRefused), ("contentEvaluations", \.contentEvaluations),
        ("contentSkips", \.contentSkips), ("retainedIneligible", \.retainedIneligible),
        ("retainedGraftIneligible", \.retainedGraftIneligible), ("retainedPrepaintIneligible", \.retainedPrepaintIneligible),
        ("retainedRedos", \.retainedRedos), ("retainedBackoffFrames", \.retainedBackoffFrames),
        ("atlasUploadPixels", \.atlasUploadPixels),
    ] }
    private var samples: [[Int]] = Array(repeating: [], count: keys.count)
    private var refused: [[String: Int]] = []
    private var ineligible: [[String: Int]] = []
    private var frames = 0

    /// Adds one warm frame's work (the presented frames `TestWindow.frameWork` holds since the last reset).
    mutating func add(_ work: [FrameWork]) {
        for (index, key) in Self.keys.enumerated() { samples[index].append(work.reduce(0) { $0 + $1[keyPath: key.1] }) }
        refused.append(work.reduce(into: [:]) { $0.merge($1.retainedTranslationRefusedReasons, uniquingKeysWith: +) })
        ineligible.append(work.reduce(into: [:]) { $0.merge($1.retainedIneligibleReasons, uniquingKeysWith: +) })
        frames += 1
    }

    /// The largest value one warm frame reached for `keyPath` (the worst frame), for a bound that pins a spike.
    func worst(_ keyPath: KeyPath<FrameWork, Int>) -> Int {
        guard let index = Self.keys.firstIndex(where: { $0.1 == keyPath }) else { return 0 }
        return samples[index].max() ?? 0
    }

    /// Prints `BENCH counters <name> (median/max per frame): …` and `BENCH refused <name> (summed over N frames): …`.
    func report(_ name: String) {
        let parts = Self.keys.enumerated().map { index, key -> String in
            let sorted = samples[index].sorted()
            return "\(key.0) \(sorted.isEmpty ? 0 : sorted[sorted.count / 2])/\(sorted.last ?? 0)"
        }
        print("BENCH counters \(name) (median/max per frame): " + parts.joined(separator: ", "))
        print("BENCH refused \(name) (median/max per frame over \(frames) frames): \(Self.reasons(refused))")
        print("BENCH ineligible \(name) (median/max per frame over \(frames) frames): \(Self.reasons(ineligible))")
    }

    /// `reason median/max, …` over the frames' per-reason counts (a frame without the reason counts 0), or `none`.
    private static func reasons(_ perFrame: [[String: Int]]) -> String {
        let names = Set(perFrame.flatMap(\.keys)).sorted()
        let parts = names.map { name -> String in
            let counts = perFrame.map { $0[name] ?? 0 }.sorted()
            return "\(name) \(counts[counts.count / 2])/\(counts.last ?? 0)"
        }
        return parts.isEmpty ? "none" : parts.joined(separator: ", ")
    }
}
#endif
