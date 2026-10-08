import CreatorKernel

/// What the viewport tells its host. Every callback runs on the main actor, from input.
public struct ViewportEvents {
    /// A click (a press that didn't drag) on the model: the face or edge under it, or `nil` for empty space.
    /// In pick mode the host collects `.edge` targets and turns them into `items[solid].solid.topology.picks(for:)`.
    public var clicked: @MainActor (PickTarget?) -> Void = { _ in }
    /// "Select Edges of Face" (spec §6.3): the face, its boundary edges as remembered picks
    /// (`topology.picks(for:)`, the encoding an Edges by Tag rule stores, spec §5.3) and their IDs, seams excluded.
    /// The host wraps the picks as `.edgePicks(…)`; the viewport never builds a graph value.
    public var selectEdgesOfFace: @MainActor (ViewportFaceRef, [EdgePick], [EdgeID]) -> Void = { _, _, _ in }
    /// "Show Producing Node": the node that made the face, from its tags.
    public var showProducingNode: @MainActor (NodeID) -> Void = { _ in }
    /// A handle drag: the handle's id and its new value.
    public var handleChanged: @MainActor (String, Double, HandleDragPhase) -> Void = { _, _, _ in }
    /// A node's display name for menu titles, or `nil` to show its short ID.
    public var nodeName: @MainActor (NodeID) -> String? = { _ in nil }

    public init() {}
}
