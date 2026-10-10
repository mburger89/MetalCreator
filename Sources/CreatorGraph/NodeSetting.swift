/// Names of stored node settings that are not sockets. They live in `Node.inputValues` beside the
/// socket constants, are saved with the file and are part of the node's cache key. They are in
/// `CreatorGraph` so the editor (M5) and the app shell (M6) can write them without importing
/// `CreatorNodes`. `Graph.apply(.setInput)` must keep accepting these non-socket names.
public enum NodeSetting {
    /// Graph Parameter: the `ParameterID` it reads, as `ConstantValue.parameter(_:)`.
    public static let parameter: SocketName = "parameter"
    /// Edges by Tag: the remembered picks, as `.edgePicks(topology.picks(for:))`.
    public static let picks: SocketName = "picks"
    /// Fillet and Chamfer: whether the viewport shows the size handle, as `.bool`. New nodes are
    /// seeded with `.bool(true)` through `NodeDefinition.defaultSettings`.
    public static let showHandle: SocketName = "showHandle"

    /// Sketch: the sketch, as `.sketch(_:)`. New nodes are seeded with an empty sketch on XY.
    public static let sketch: SocketName = "sketch"
    /// Plane from Face: the picked face, as `.facePick(topology.facePick(for:))`.
    public static let face: SocketName = "face"
    /// Group, Group Input and Group Output: the definition they belong to, as `ConstantValue.group(_:)`
    /// (groups spec §4). `NodeRegistry.makeGroupNode` sets it.
    public static let group: SocketName = "groupID"

    public static let all: Set<SocketName> = [parameter, picks, showHandle, sketch, face, group]

    /// The start of every projection setting's name, which no exposed dimension may use.
    public static let projectionPrefix = "projection."

    /// Sketch: the edge pick of one projected edge, as `.edgePicks([pick])`, stored under the
    /// projection's `ProjectionSource.reference` (sketcher spec §7, S1–S2 handoff).
    public static func projection(_ reference: String) -> SocketName {
        SocketName(projectionPrefix + reference)
    }
}
