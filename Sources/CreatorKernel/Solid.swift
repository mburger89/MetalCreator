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

    public var estimatedBytes: Int {
        storage.estimatedBytes + (topology.faces.count + topology.edges.count) * 128
    }
}
