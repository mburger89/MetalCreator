/// A test gate: `hold()` suspends (never blocks a thread) until `open()`; `waitForEntries(_:)` waits until that many holds began.
actor SuspendingGate {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var watchers: [(Int, CheckedContinuation<Void, Never>)] = []
    private var entries = 0
    private var isOpen = false

    func hold() async {
        entries += 1
        let ready = watchers.filter { entries >= $0.0 }
        watchers.removeAll { entries >= $0.0 }
        for watcher in ready { watcher.1.resume() }
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func waitForEntries(_ count: Int) async {
        if entries >= count { return }
        await withCheckedContinuation { watchers.append((count, $0)) }
    }

    func open() {
        isOpen = true
        let all = waiting
        waiting.removeAll()
        for continuation in all { continuation.resume() }
    }
}
