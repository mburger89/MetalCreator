/// What the sketch editor tells its host. Every callback runs on the main actor, from input.
public struct SketchEditorEvents {
    /// An edit: the host stores `commit.sketch` in the Sketch node's `sketch` setting as one undo step.
    public var committed: @MainActor (SketchCommit) -> Void = { _ in }
    /// Finish (⏎, Esc with nothing in progress, or the Finish button): the host leaves sketch mode.
    public var finished: @MainActor () -> Void = {}

    public init() {}
}
