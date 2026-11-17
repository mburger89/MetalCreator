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

    public var estimatedBytes: Int {
        storage.estimatedBytes + (topology.faces.count + topology.edges.count) * 128
    }
}
