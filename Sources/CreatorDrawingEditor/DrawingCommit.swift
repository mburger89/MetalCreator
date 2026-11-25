import CreatorDrawing

/// One change to the drawings: the whole document after it, the undo step's name and the key that merges a run of them.
public struct DrawingCommit: Hashable, Sendable {
    public var document: DrawingDocument
    /// A `DrawingStepName`; never contains typed text or a number.
    public var name: String
    public var coalescingKey: String?

    public init(document: DrawingDocument, name: String, coalescingKey: String? = nil) {
        self.document = document
        self.name = name
        self.coalescingKey = coalescingKey
    }
}
