import CreatorGeometry
import CreatorGraph
import Foundation

/// Slack wires (cable ties spec 2026-10-26 §5.2). A move kicks the springs of the wires whose pinned points it moved
/// (`withWireSlack`); a move is a drag of the selection or an arrow key. While some wire is slack the canvas draws the wires
/// inside `TimelineView(.animation)` (`WireLayer`). Each frame reads the slack at its date (`drawnMotion(at:)`) and writes
/// nothing back. A settle task ends the motion once every wire is taut again (`settleWireMotion()`). With Reduce Motion on,
/// nothing is ever kicked. Hit testing, culling, boxes and the file only ever see the taut routes.
extension EditorModel {
    /// How often the settle task checks whether the wires are taut again.
    static let motionSettleInterval = Duration.milliseconds(100)

    /// Every wire's pinned points now (its ends and its lanes, display canvas points).
    func pinnedPoints() -> [Endpoint: [Vector2]] { wireRouting.routes.mapValues(\.pinned) }

    /// Runs `move`, then makes the wires whose pinned points it moved go slack, and starts the timeline if it isn't running.
    /// Just `move` while Reduce Motion is on.
    func withWireSlack(_ move: () -> Void) {
        guard !reducesMotion else {
            move()
            return
        }
        let before = pinnedPoints()
        move()
        wireMotion.excite(from: before, to: pinnedPoints(), at: motionClock())
        guard !wireMotion.isAtRest else { return }
        if !isWireMotionActive { isWireMotionActive = true }
        scheduleMotionSettle()
    }

    /// The slack at `date`, a timeline frame's: what the canvas draws. Pure: nothing is written.
    public func drawnMotion(at date: Date) -> WireMotion {
        wireMotion.advanced(to: date.timeIntervalSinceReferenceDate)
    }

    /// Advances the slack to the clock's time and, once every wire is taut, ends the motion (the timeline goes).
    public func settleWireMotion() {
        wireMotion = wireMotion.advanced(to: motionClock())
        if wireMotion.isAtRest { stopWireMotion() }
    }

    /// Every wire taut at once: Reduce Motion turned on, or the slack settled.
    func stopWireMotion() {
        wireMotion = WireMotion()
        motionSettleTask?.cancel()
        motionSettleTask = nil
        if isWireMotionActive { isWireMotionActive = false }
    }

    private func scheduleMotionSettle() {
        guard motionSettleTask == nil else { return }
        motionSettleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.motionSettleInterval)
                guard let self, !Task.isCancelled else { return }
                self.settleWireMotion()
                if !self.isWireMotionActive { return }
            }
        }
    }
}
