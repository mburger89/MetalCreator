import CreatorKernel

/// What the person typed about one part of the drawing's items (DR-5 R5); the array's order is their item order.
public struct PartItem: Hashable, Codable, Sendable {
    public var part: NodeID
    public var material: String
    public var partNumber: String

    public init(part: NodeID, material: String = "", partNumber: String = "") {
        self.part = part
        self.material = material
        self.partNumber = partNumber
    }
}

/// A part's remembered name, so a part whose Output was deleted keeps its place and its name (DR-5 R5).
public struct PartName: Hashable, Codable, Sendable {
    public var part: NodeID
    public var name: String

    public init(part: NodeID, name: String) {
        self.part = part
        self.name = name
    }
}
