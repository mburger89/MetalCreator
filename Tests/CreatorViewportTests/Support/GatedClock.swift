// Test fixture file: a clock whose sleeps last until the test moves time past their deadline.
import Synchronization
@testable import CreatorViewport

/// Starts at 100 s. `sleep(until:)` suspends until `time` reaches its deadline, or the task is cancelled, so a test
/// can pin a debounce: advance short of the delay and nothing fires; advance past it and it does. (`ManualClock`'s
/// sleeps return at once, so a debounce can't be told from none.)
///
/// Nothing here depends on yield counts or real time:
/// - The model reads `deadline(after:)` synchronously when it schedules a wait, so the deadline is right even if the
///   task that sleeps starts late; the clock counts each such request (`unregistered`) until that task's
///   `sleep(until:)` has registered, and `advance` waits for the count to reach 0 before moving time.
/// - After moving time, `advance` resumes every expired sleeper and counts it in `pendingWakes`. A sleeper decrements
///   the count as its `sleep` returns; everything runs on the main actor, so the rest of that task then runs
///   synchronously up to its next suspension before any other main-actor job (including `advance`) continues. When
///   `pendingWakes` is 0, every woken task has therefore run as far as it can.
@MainActor
final class GatedClock: ViewportClock {
    var time = 100.0
    private var unregistered = 0
    private var pendingWakes = 0
    private var nextID = 0
    private let state = Mutex(State())

    /// `true` resumes a sleeper woken by `advance`; `false` one woken by cancellation.
    private struct State {
        var waiters: [Int: (deadline: Double, continuation: CheckedContinuation<Bool, Never>)] = [:]
        var cancelled: Set<Int> = []
    }

    func now() -> Double { time }

    func deadline(after seconds: Double) -> Double {
        unregistered += 1
        return time + seconds
    }

    func sleep(until deadline: Double) async {
        unregistered -= 1
        guard time < deadline, !Task.isCancelled else { return }
        nextID += 1
        let id = nextID
        let advanced = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let resumeNow = state.withLock { state -> Bool in
                    if state.cancelled.remove(id) != nil { return true }
                    state.waiters[id] = (deadline, continuation)
                    return false
                }
                if resumeNow { continuation.resume(returning: false) }
            }
        } onCancel: {
            // May run on any thread. Resuming under the lock's result keeps it to exactly once.
            let continuation = state.withLock { state -> CheckedContinuation<Bool, Never>? in
                if let waiter = state.waiters.removeValue(forKey: id) { return waiter.continuation }
                state.cancelled.insert(id)
                return nil
            }
            continuation?.resume(returning: false)
        }
        if advanced { pendingWakes -= 1 }
    }

    /// Waits for every wait the model has scheduled to register, moves time on, wakes the sleepers it expired and
    /// waits until each has run to its next suspension.
    func advance(by seconds: Double) async {
        while unregistered > 0 { await Task.yield() }
        time += seconds
        let now = time
        let due = state.withLock { state -> [CheckedContinuation<Bool, Never>] in
            let ids = state.waiters.filter { $0.value.deadline <= now }.keys.sorted()
            return ids.compactMap { state.waiters.removeValue(forKey: $0)?.continuation }
        }
        pendingWakes += due.count
        for continuation in due { continuation.resume(returning: true) }
        while pendingWakes > 0 { await Task.yield() }
    }
}
