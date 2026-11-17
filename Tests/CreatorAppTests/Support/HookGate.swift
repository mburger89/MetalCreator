import Synchronization

/// Holds a `FakeKernel` hook until the test releases it, by suspending the call, never by blocking a thread.
///
/// A hook that blocked (a `DispatchSemaphore.wait()`) held a thread of Swift's shared pool, which has one thread per core. On CI's
/// four-core Linux runner four gated tests running at once used the pool up, and the work that would let a test release its gate
/// (its `waitUntilEntered()`, the model's own tasks) then had no thread left to run on: `CreatorAppTests` hung until the job's
/// timeout. A suspended hook holds no thread. `release()` lets one held or future call through (a counting gate, as the
/// semaphore was); `open()` lets every one through, and each test calls it on every way out (`defer { gate.open() }`).
final class HookGate: Sendable {
    private struct State {
        var permits = 0
        var isOpen = false
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())
    private let entered: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation

    init() { (entered, signal) = AsyncStream<Void>.makeStream() }

    /// Called from the hook: says it was entered, then waits for a `release()` (or `open()`).
    func hold() async {
        signal.yield()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let passes = state.withLock { state -> Bool in
                if state.isOpen { return true }
                if state.permits > 0 {
                    state.permits -= 1
                    return true
                }
                state.waiting.append(continuation)
                return false
            }
            if passes { continuation.resume() }
        }
    }

    /// Lets the longest-held call through, or the next one if none is held.
    func release() {
        let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard !state.waiting.isEmpty else {
                state.permits += 1
                return nil
            }
            return state.waiting.removeFirst()
        }
        next?.resume()
    }

    /// Lets every held and future call through.
    func open() {
        let held = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isOpen = true
            let held = state.waiting
            state.waiting = []
            return held
        }
        for continuation in held { continuation.resume() }
    }

    /// Waits until one more call has entered the hook; false if none does within 900 s (a test that really stalls fails, naming
    /// what it waited for, instead of hanging).
    func waitUntilEntered() async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in self.entered { return true }; return false }
            group.addTask { try? await Task.sleep(for: .seconds(900)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
}
