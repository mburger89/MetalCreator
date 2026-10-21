import Foundation

/// An order-preserving `map` over many independent items on every core. The checks (`ThinWallCheck`, `TrappedVolumeCheck`) ask a pure
/// question of each vertex or cell centre, so running the questions side by side gives the very values a loop gives, in the same order.
///
/// This is a plain synchronous function on purpose: its loop is not an `async` function's, and it needs no actor. It does not look at
/// `Task.isCancelled` (its workers are not the caller's task); callers hand it bounded batches and check for cancellation between them.
enum ParallelMap {
    /// The fewest items a worker is given: below this, the hand-off costs more than the work.
    static let minimumChunk = 256

    /// `transform` applied to each element of `items`, in order.
    static func map<Element: Sendable, Result: Sendable>(_ items: [Element], _ transform: @Sendable (Element) -> Result) -> [Result] {
        let count = items.count
        let workers = max(1, ProcessInfo.processInfo.activeProcessorCount)
        guard count > Self.minimumChunk, workers > 1 else { return items.map(transform) }
        let chunk = max(Self.minimumChunk, (count + 4 * workers - 1) / (4 * workers))
        let chunks = (count + chunk - 1) / chunk
        // Each chunk's results are its own array, so the workers share nothing; they are joined in order afterwards.
        let box = ResultSlots<Result>(count: chunks)
        withoutActuallyEscaping(transform) { transform in
            DispatchQueue.concurrentPerform(iterations: chunks) { index in
                let range = (index * chunk)..<min(count, (index + 1) * chunk)
                box.store(items[range].map(transform), at: index)
            }
        }
        return box.joined()
    }
}

/// Where the chunks of a `ParallelMap` leave their results: one slot each, written once by one worker.
private final class ResultSlots<Result: Sendable>: @unchecked Sendable {
    private var slots: [[Result]]
    private let lock = NSLock()

    init(count: Int) {
        slots = Array(repeating: [], count: count)
    }

    func store(_ values: [Result], at index: Int) {
        lock.lock()
        slots[index] = values
        lock.unlock()
    }

    func joined() -> [Result] {
        lock.lock()
        defer { lock.unlock() }
        return slots.flatMap { $0 }
    }
}
