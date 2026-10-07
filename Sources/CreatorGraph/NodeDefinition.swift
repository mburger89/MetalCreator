import CreatorKernel

/// A node type. Definitions are stateless and UI-free: the inspector and handles are data
/// (spec §4.3).
public protocol NodeDefinition: Sendable {
    static var typeID: String { get }
    static var typeVersion: Int { get }
    static var displayName: String { get }
    static var category: NodeCategory { get }
    static var inputs: [SocketSpec] { get }
    static var outputs: [SocketSpec] { get }
    static var inspector: [InspectorSection] { get }
    static var handles: [HandleSpec] { get }
    /// True if `evaluate` reads `context.parameters`, so parameter edits invalidate its cache.
    static var readsParameters: Bool { get }

    /// Upgrades a node saved under an older `typeVersion`.
    static func migrate(_ node: Node, from version: Int) -> Node

    static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs
}

extension NodeDefinition {
    public static var typeVersion: Int { 1 }
    public static var inspector: [InspectorSection] { [] }
    public static var handles: [HandleSpec] { [] }
    public static var readsParameters: Bool { false }
    public static func migrate(_ node: Node, from version: Int) -> Node { node }
}
