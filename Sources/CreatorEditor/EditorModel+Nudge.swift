import CreatorGeometry
import CreatorGraph
import Foundation

extension EditorModel {
    /// An arrow key (spec 2026-10-09 §3): moves every selected item, and the nodes a selected frame holds, by `delta` display canvas points, the way the
    /// arrow points on screen (the left dock's transpose is undone). One undo step per key-down run: a press that
    /// isn't an auto-repeat starts a new step, and its repeats join it. A repeat after something ended coalescing
    /// (a press, a selection change, Undo) starts a new step too. Returns false when nothing selected is on the
    /// canvas, so the key goes on.
    @discardableResult
    public func nudgeSelection(by delta: Vector2, isRepeat: Bool) -> Bool {
        let start = positions(of: carried(by: canvasSelection))
        guard !start.isEmpty else { return false }
        if !isRepeat || nudgeKey == nil {
            document.endCoalescing()
            nudgeKey = "nudge-\(UUID().uuidString)"
        }
        try? document.perform(.batch(moveCommands(from: start, by: flow.stored(delta))), coalescingKey: nudgeKey)
        return true
    }
}
