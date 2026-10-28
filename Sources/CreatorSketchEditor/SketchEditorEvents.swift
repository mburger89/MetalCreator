import CreatorGeometry
import CreatorViewport

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
    /// The Project tool's pick (an edge, or a face for all its edges) and the sketch plane: the host resolves it into the
    /// edges that can be projected onto that plane, with the picks the Sketch node stores.
    public var projection: @MainActor (PickTarget, Plane) -> ProjectionResolution = { _, _ in
        ProjectionResolution(candidates: [], skipped: ["Projecting isn't available here."])
    }
    /// Asked after a dimension's typed value is committed (the value box): the host checks what the change did downstream and
    /// returns a message when it must be refused (a feature the new value breaks), or `nil`.
    public var checkValueCommit: @MainActor () async -> String? = { nil }

    /// Asked after the Dimension tool's completing pick: the host opens the value box for this dimension (`"sketch/new"`) over
    /// the viewport.
    public var openValueBox: @MainActor (OverlayDimensionID) -> Void = { _ in }

    public init() {}
}
