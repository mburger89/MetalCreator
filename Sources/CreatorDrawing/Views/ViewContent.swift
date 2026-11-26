import CreatorGeometry
import CreatorKernel

/// What a view shows now: its projection, or why it has none (the editor's cache fills it).
public struct ViewContent: Hashable, Sendable {
    public var projection: Projection2D?
    /// The topology of the solid the projection shows, carried with it (plan R25): what annotations resolve against.
    public var topology: Topology?
    public var isPending: Bool
    public var problem: String?
    public var warnings: [String]
    /// The size of the last projection's frame on the sheet, kept for a view that has none now.
    public var lastSize: Vector2?
    /// A section's cut faces, in its model plane (DR-3 R5); drawing only, empty for every other view.
    public var hatch: [HatchRegion]
    /// The circles hatch is cut to: a detail's own and its ancestors' (R8).
    public var hatchClips: [HatchClip]
    /// The model-plane box the view centres on (a detail's circle, R10); `nil` centres on the projection's bounds.
    public var framing: Rect2D?

    public init(
        projection: Projection2D? = nil, topology: Topology? = nil, isPending: Bool = false, problem: String? = nil,
        warnings: [String] = [], lastSize: Vector2? = nil, hatch: [HatchRegion] = [], hatchClips: [HatchClip] = [],
        framing: Rect2D? = nil
    ) {
        self.hatch = hatch
        self.hatchClips = hatchClips
        self.framing = framing
        self.projection = projection
        self.topology = topology
        self.isPending = isPending
        self.problem = problem
        self.warnings = warnings
        self.lastSize = lastSize
    }
}
