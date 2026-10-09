/// What the sketch editor tells its host. Every callback runs on the main actor, from input.
public struct SketchEditorEvents {
    /// An edit: the host stores `commit.sketch` in the Sketch node's `sketch` setting as one undo step.
    public var committed: @MainActor (SketchCommit) -> Void = { _ in }
    /// Finish (⏎, Esc with nothing in progress, or the Finish button): the host leaves sketch mode.
    public var finished: @MainActor () -> Void = {}
    /// Asked first by Esc and Finish: the host closes a popup of its own that is open over the sketch (the add-node
    /// palette) and returns true, and the key does nothing else. The sketch's keys are button shortcuts, which run
    /// before the host's own keys, so without this Esc would end sketch mode under an open palette.
    public var dismissHostPopup: @MainActor () -> Bool = { false }

    public init() {}
}
