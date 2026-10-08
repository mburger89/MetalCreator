import CreatorGeometry
import CreatorGraph
import CreatorKernel

extension NodeInputs {
    /// The whole list on a `.list`-access socket (or a single item as a one-item list), typed.
    func numbers(_ name: SocketName) throws -> [Double] {
        try typedList(name, .number) { if case .number(let value) = $0 { value } else { nil } }
    }

    func vectors(_ name: SocketName) throws -> [Vector3] {
        try typedList(name, .vector) { if case .vector(let value) = $0 { value } else { nil } }
    }

    func profiles(_ name: SocketName) throws -> [Profile2D] {
        try typedList(name, .profile) { if case .profile(let value) = $0 { value } else { nil } }
    }

    func solids(_ name: SocketName) throws -> [Solid] {
        try typedList(name, .solid) { if case .solid(let value) = $0 { value } else { nil } }
    }

    private func typedList<T>(_ name: SocketName, _ type: SocketType, _ extract: (Scalar) -> T?) throws -> [T] {
        try list(name).map { scalar in
            guard let value = extract(scalar) else { throw NodeError.typeMismatch(name, expected: type) }
            return value
        }
    }
}
