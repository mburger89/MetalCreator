import Foundation
import Observation

/// The "Building Fillet…" chip over the viewport: it shows once an evaluation has been running for `delay` (0.5 s) and goes as
/// soon as none is. Whether one is running is `DocumentModel.isEvaluating` (true from `scheduleEvaluation`, across a replacing
/// evaluation, until `apply`, which a held result set also reaches), fed in by `AppModel.followEvaluation()`; so a run is a run
/// whether or not any node is named, and the wait starts when the flag goes true and is never restarted while it stays true.
///
/// The names only decide the wording, and they are approximate: they are the nodes whose `NodeState` is `.evaluating`, which an
/// edit sets on every stale downstream node at once, so a name may be a node that is already done (the evaluator reports no
/// per-node progress). A node new to the graph, or any node while a file opens, has no result yet and is not named: the chip then
/// reads "Building…". Nothing is polled and no progress is claimed.
@MainActor
@Observable
final class SlowEvaluationModel {
    static let defaultDelay = Duration.milliseconds(500)

    /// The nodes running now, in the stable order the app gave them; empty when nothing runs.
    private(set) var running: [String] = []
    /// True while an evaluation is running (`DocumentModel.isEvaluating`).
    private(set) var isRunning = false
    /// True once the current run has lasted `delay`.
    private(set) var isDue = false

    /// How long a run waits before the chip shows. Tests replace `wait` instead of sleeping.
    @ObservationIgnored var delay = SlowEvaluationModel.defaultDelay
    @ObservationIgnored var wait: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    @ObservationIgnored private(set) var timer: Task<Void, Never>?

    /// What the chip says, or `nil` while it is hidden: "Building Fillet…", or "Building Fillet and 2 more…".
    var text: String? {
        guard isDue, isRunning else { return nil }
        guard let first = running.first else { return "Building…" }
        let others = running.count - 1
        return others == 0 ? "Building \(first)…" : "Building \(first) and \(others) more…"
    }

    /// Whether an evaluation is running, and the nodes marked evaluating (in a stable order; they only word the chip). A run that
    /// ends clears the chip; one that starts waits `delay`, once.
    func follow(running isRunning: Bool, names: [String]) {
        let names = isRunning ? names : []
        if names != running { running = names }
        if self.isRunning != isRunning { self.isRunning = isRunning }
        guard isRunning else {
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
    func reset() { follow(running: false, names: []) }

    /// Returns once the current wait has ended (it has, or the run did).
    func waitForTimer() async {
        await timer?.value
    }

    private func becameDue() {
        guard isRunning else { return }
        isDue = true
    }
}
