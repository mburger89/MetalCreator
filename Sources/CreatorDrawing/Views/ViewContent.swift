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

    public init(
        projection: Projection2D? = nil, topology: Topology? = nil, isPending: Bool = false, problem: String? = nil,
        warnings: [String] = [], lastSize: Vector2? = nil
    ) {
        self.projection = projection
        self.topology = topology
        self.isPending = isPending
        self.problem = problem
        self.warnings = warnings
        self.lastSize = lastSize
    }
}
