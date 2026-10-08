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

    public static let all: Set<SocketName> = [parameter, picks, showHandle]
}
