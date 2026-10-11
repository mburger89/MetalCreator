import CreatorGeometry
import CreatorKernel

/// The inputs for one broadcast iteration of a node.
public struct NodeInputs: Sendable {
    public enum Slot: Sendable {
        case item(Scalar)
        case list([Scalar])
        /// The whole value of a `.tree`-access socket.
        case tree(DataTree)
    }

    /// Which broadcast iteration this is (0-based).
    public let item: Int
    private let slots: [SocketName: Slot]

    public init(item: Int, slots: [SocketName: Slot]) {
        self.item = item
        self.slots = slots
    }

    public func has(_ name: SocketName) -> Bool { slots[name] != nil }

    public func scalar(_ name: SocketName) throws -> Scalar {
        switch slots[name] {
        case .item(let scalar)?: return scalar
        case .list(let scalars)?:
            guard let first = scalars.first else { throw NodeError.missingInput(name) }
            return first
        case .tree(let tree)?:
            guard let first = tree.items.first else { throw NodeError.missingInput(name) }
            return first
        case nil: throw NodeError.missingInput(name)
        }
    }

    public func list(_ name: SocketName) throws -> [Scalar] {
        switch slots[name] {
        case .list(let scalars)?: return scalars
        case .item(let scalar)?: return [scalar]
        case .tree(let tree)?: return tree.items
        case nil: throw NodeError.missingInput(name)
        }
    }

    /// The whole value on a `.tree`-access socket. A flat list is a tree of depth 1, and one item a list of one.
    public func tree(_ name: SocketName) throws -> DataTree {
        switch slots[name] {
        case .tree(let tree)?: return tree
        case .list(let scalars)?: return .list(scalars)
        case .item(let scalar)?: return .list([scalar])
        case nil: throw NodeError.missingInput(name)
        }
    }

    public func number(_ name: SocketName) throws -> Double {
        guard case .number(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .number) }
        return value
    }

    public func integer(_ name: SocketName) throws -> Int {
        guard case .integer(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .integer) }
        return value
    }

    public func bool(_ name: SocketName) throws -> Bool {
        guard case .bool(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .bool) }
        return value
    }

    public func vector(_ name: SocketName) throws -> Vector3 {
        guard case .vector(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .vector) }
        return value
    }

    public func plane(_ name: SocketName) throws -> Plane {
        guard case .plane(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .plane) }
        return value
    }

    public func profile(_ name: SocketName) throws -> Profile2D {
        guard case .profile(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .profile) }
        return value
    }

    public func solid(_ name: SocketName) throws -> Solid {
        guard case .solid(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .solid) }
        return value
    }

    public func edgeSet(_ name: SocketName) throws -> EdgeSet {
        guard case .edgeSet(let value) = try scalar(name) else { throw NodeError.typeMismatch(name, expected: .edgeSet) }
        return value
    }
}
