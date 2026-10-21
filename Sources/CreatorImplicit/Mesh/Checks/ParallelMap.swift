import Foundation

/// An order-preserving `map` over many independent items on every core. The checks (`ThinWallCheck`, `TrappedVolumeCheck`) ask a pure
/// question of each vertex or cell centre, so running the questions side by side gives the very values a loop gives, in the same order.
///
/// The heavy loop is never in an `async` function: each child task calls `transform`, a plain synchronous function that maps one chunk
/// (the pattern of `DistanceBaker`), and the chunks are put back in order by their first index.
enum ParallelMap {
    /// The fewest items a task is given: below this, the hand-off costs more than the work.
    static let minimumChunk = 256

    /// `transform` applied to consecutive chunks of `items` side by side, the results joined in order.
    /// - Throws: `CancellationError`, checked before the chunks go out and as they come back.
    static func map<Element: Sendable, Result: Sendable>(
        _ items: [Element], _ transform: @escaping @Sendable ([Element]) -> [Result]
    ) async throws -> [Result] {
        try Task.checkCancellation()
        let count = items.count
        let workers = max(1, ProcessInfo.processInfo.activeProcessorCount)
        guard count > Self.minimumChunk, workers > 1 else { return transform(items) }
        let chunk = max(Self.minimumChunk, (count + 4 * workers - 1) / (4 * workers))
        return try await withThrowingTaskGroup(of: (Int, [Result]).self) { group in
            for start in stride(from: 0, to: count, by: chunk) {
                let slice = Array(items[start..<min(start + chunk, count)])
                group.addTask { (start, transform(slice)) }
            }
            var runs: [(Int, [Result])] = []
            for try await run in group {
                try Task.checkCancellation()
                runs.append(run)
            }
            return runs.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }
}
