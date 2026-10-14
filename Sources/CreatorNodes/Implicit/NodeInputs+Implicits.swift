import CreatorGraph
import CreatorImplicit

extension NodeInputs {
    /// The implicit solid on `name` (an item socket).
    func implicitSolid(_ name: SocketName) throws -> ImplicitSolid {
        try solid(of: try implicit(name), name)
    }

    /// Every implicit solid on the list socket `name`, in order.
    func implicitSolids(_ name: SocketName) throws -> [ImplicitSolid] {
        try list(name).map { scalar in
            guard case .implicit(let reference) = scalar else { throw NodeError.typeMismatch(name, expected: .implicit) }
            return try solid(of: reference, name)
        }
    }

    private func solid(of reference: ImplicitReference, _ name: SocketName) throws -> ImplicitSolid {
        guard let solid = reference.solid else { throw NodeError.typeMismatch(name, expected: .implicit) }
        return solid
    }
}
