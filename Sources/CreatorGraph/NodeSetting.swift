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

    /// Path Mapper: its rule, as `.text("{A;B} → {B;A}")`. New nodes are seeded with a rule that changes nothing.
    public static let pathRule: SocketName = "pathRule"
    /// Branch by Path: the branch to take, as `.text("{0}")`.
    public static let branchPath: SocketName = "branchPath"
    /// List Item: the one item to take by its full path, as `.text("{0;3}")`; empty means "use the index".
    public static let itemPath: SocketName = "itemPath"

    /// Cull Pattern: its mask, as `.text("1 0 1")` (1 keeps an item, 0 culls it, repeated along each branch).
    public static let cullPattern: SocketName = "cullPattern"

    /// Cull Index: the indices and paths to take out, as `.text("1, 4, {0;3}")`; empty takes nothing out.
    public static let cullIndices: SocketName = "cullIndices"

    /// Image Field: its picture, as `.image(ImageReference)` (fields spec §5). Absent until one is chosen.
    public static let image: SocketName = "image"

    public static let all: Set<SocketName> = [
        parameter, picks, showHandle, sketch, face, group, pathRule, branchPath, itemPath, cullPattern, cullIndices, image
    ]

    /// The setting names no group socket and no exposed Sketch dimension may use, because those nodes keep their settings beside
    /// their inputs' values. `image` is left out on purpose: only Image Field has it, and a Sketch node or a group whose socket
    /// is called "image" (a file made before 7b-2 may have one) keeps working exactly as it did.
    public static let reservedForSockets: Set<SocketName> = all.subtracting([image])

    /// The start of every projection setting's name, which no exposed dimension may use.
    public static let projectionPrefix = "projection."

    /// Sketch: the edge pick of one projected edge, as `.edgePicks([pick])`, stored under the
    /// projection's `ProjectionSource.reference` (sketcher spec §7, S1–S2 handoff).
    public static func projection(_ reference: String) -> SocketName {
        SocketName(projectionPrefix + reference)
    }
}
