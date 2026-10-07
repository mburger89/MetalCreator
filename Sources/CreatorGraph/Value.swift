/// What a socket carries: a single item, or a list that broadcasts (spec §4.2).
/// Nested data trees will be added in sub-project 7, so don't assume exactly two cases.
public enum Value: Sendable {
    case one(Scalar)
    case list([Scalar])

    public var items: [Scalar] {
        switch self {
        case .one(let scalar): [scalar]
        case .list(let scalars): scalars
        }
    }

    public func converted(to target: SocketType) -> Value? {
        switch self {
        case .one(let scalar):
            return scalar.converted(to: target).map(Value.one)
        case .list(let scalars):
            let converted = scalars.compactMap { $0.converted(to: target) }
            return converted.count == scalars.count ? .list(converted) : nil
        }
    }

    public var estimatedBytes: Int { items.reduce(16) { $0 + $1.estimatedBytes } }
}
