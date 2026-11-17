import CreatorGeometry

/// An immutable solid produced by a kernel. Cheap to share: cached node outputs hold
/// references, never copies.
public final class Solid: Sendable {
    public let topology: Topology
    public let bounds: BoundingBox
    public let storage: any SolidStorage

    public init(topology: Topology, bounds: BoundingBox, storage: any SolidStorage) {
        self.topology = topology
        self.bounds = bounds
        self.storage = storage
    }

    /// Whether no edge has exactly one face: a solid, never a sheet.
    public var isClosed: Bool { !topology.edges.contains(where: \.isBoundary) }

    /// Whether any face belongs to a shell that isn't closed: a sheet, or a body with one. Unlike `isClosed` this
    /// ignores an edge a valid solid may list with one face (a face that borders itself), so closed-solid refusals use it.
    public var hasOpenShell: Bool { topology.faces.contains(where: \.isOnOpenShell) }

    public var estimatedBytes: Int {
        storage.estimatedBytes + (topology.faces.count + topology.edges.count) * 128
    }
}
