/// One piece of sketch geometry plus its construction flag. Construction geometry is solved
/// like any other geometry but never becomes part of a region.
public struct SketchEntity: Hashable, Sendable, Codable {
    public var kind: SketchEntityKind
    public var isConstruction: Bool

    public init(_ kind: SketchEntityKind, isConstruction: Bool = false) {
        self.kind = kind
        self.isConstruction = isConstruction
    }
}
