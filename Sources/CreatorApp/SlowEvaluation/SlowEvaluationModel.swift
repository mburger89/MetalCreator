import Foundation
import Observation

/// The "Building Fillet…" chip over the viewport: it shows once evaluation has been running for `delay` (0.5 s) and goes as soon
/// as nothing is evaluating. The running nodes' names come from the app (`AppModel.followEvaluation()`, which reads the nodes whose
/// `NodeState` is `.evaluating`, the same state the graph panel's badge spinner draws); this only keeps the wait.
///
/// The wait starts when the first node starts running and is kept while some node is running: a newer evaluation that replaces a
/// cancelled one leaves the nodes marked, so the chip neither flickers nor starts its wait again. It is empty again the moment the
/// list is empty (finished, failed, cancelled), and the next run waits afresh. Nothing is polled and no progress is claimed.
@MainActor
@Observable
final class SlowEvaluationModel {
    static let defaultDelay = Duration.milliseconds(500)

    /// The nodes running now, in the stable order the app gave them; empty when nothing runs.
    private(set) var running: [String] = []
    /// True once the current run has lasted `delay`.
    private(set) var isDue = false

    /// How long a run waits before the chip shows. Tests replace `wait` instead of sleeping.
    @ObservationIgnored var delay = SlowEvaluationModel.defaultDelay
    @ObservationIgnored var wait: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    @ObservationIgnored private(set) var timer: Task<Void, Never>?

    /// What the chip says, or `nil` while it is hidden: "Building Fillet…", or "Building Fillet and 2 more…".
    var text: String? {
        guard isDue, let first = running.first else { return nil }
        let others = running.count - 1
        return others == 0 ? "Building \(first)…" : "Building \(first) and \(others) more…"
    }

    /// The nodes that are running now, in a stable order. An empty list ends the run; a non-empty one starts it if none was running.
    func follow(_ names: [String]) {
        if names != running { running = names }
        guard !names.isEmpty else {
            timer?.cancel()
            timer = nil
            if isDue { isDue = false }
            return
        }
        guard timer == nil else { return }
        let wait = wait
        let delay = delay
        timer = Task { [weak self] in
            do { try await wait(delay) } catch { return }
            self?.becameDue()
        }
    }

    /// Stops and forgets everything (a new document).
    func reset() { follow([]) }

    /// Returns once the current wait has ended (it has, or the run did).
    func waitForTimer() async {
        await timer?.value
    }

    private func becameDue() {
        guard !running.isEmpty else { return }
        isDue = true
    }
}
