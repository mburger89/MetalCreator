import CreatorGeometry
import CreatorKernel

/// One node instance in a graph: pure data, saved in the file.
public struct Node: Sendable, Codable, Equatable, Identifiable {
    public var id: NodeID
    public var typeID: String
    public var typeVersion: Int
    public var name: String
    /// Constants for unwired inputs, plus non-socket settings (`text`).
    public var inputValues: [SocketName: ConstantValue]
    /// Canonical left-to-right canvas position. The vertical dock uses its transpose (spec §6.2).
    public var position: Vector2
    public var isOutput: Bool

    public init(id: NodeID = NodeID(), typeID: String, typeVersion: Int = 1, name: String,
                inputValues: [SocketName: ConstantValue] = [:], position: Vector2 = .zero, isOutput: Bool = false) {
        self.id = id
        self.typeID = typeID
        self.typeVersion = typeVersion
        self.name = name
        self.inputValues = inputValues
        self.position = position
        self.isOutput = isOutput
    }
}
