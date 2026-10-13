/// What `Kernel.distances(from:to:signed:)` measures to (fields spec §3.1): a whole solid (its surface), some of a solid's
/// faces, or some of its edges.
public enum DistanceTarget: Sendable {
    case solid(Solid)
    case faces(FaceSet)
    case edges(EdgeSet)

    /// The solid the target belongs to.
    public var solid: Solid {
        switch self {
        case .solid(let solid): solid
        case .faces(let set): set.solid
        case .edges(let set): set.solid
        }
    }

    /// Refuses a target with nothing to measure to: an empty selection, or an ID the solid doesn't have. Every kernel
    /// calls it first, so the messages are the same everywhere.
    public func validate() throws {
        switch self {
        case .solid:
            return
        case .faces(let set):
            guard !set.faces.isEmpty else { throw KernelError.invalidInput("No faces are selected to measure to.") }
            let count = set.solid.topology.faces.count
            guard set.faces.allSatisfy({ (0..<count).contains($0.rawValue) }) else {
                throw KernelError.invalidInput("A selected face doesn't exist on the solid.")
            }
        case .edges(let set):
            guard !set.edges.isEmpty else { throw KernelError.invalidInput("No edges are selected to measure to.") }
            let count = set.solid.topology.edges.count
            guard set.edges.allSatisfy({ (0..<count).contains($0.rawValue) }) else {
                throw KernelError.invalidInput("A selected edge doesn't exist on the solid.")
            }
        }
    }

    /// Which target this is, for caches: the solid object (by identity), the kind, and the selected IDs as a sorted set. A
    /// cache that keys on it must keep the target itself alive, so the solid's identity can't be reused by another object.
    public struct Identity: Hashable, Sendable {
        let solid: ObjectIdentifier
        let kind: Int
        let ids: [Int]
    }

    public var identity: Identity {
        switch self {
        case .solid(let solid): Identity(solid: ObjectIdentifier(solid), kind: 0, ids: [])
        case .faces(let set): Identity(solid: ObjectIdentifier(set.solid), kind: 1, ids: Set(set.faces.map(\.rawValue)).sorted())
        case .edges(let set): Identity(solid: ObjectIdentifier(set.solid), kind: 2, ids: Set(set.edges.map(\.rawValue)).sorted())
        }
    }
}
