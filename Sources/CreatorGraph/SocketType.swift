/// The closed set of socket types (spec §4.2). `mesh` is reserved for sub-project 7.
public enum SocketType: String, Sendable, Codable, CaseIterable {
    case number, integer, bool, vector, plane, profile, solid, edgeSet, faceSet
    /// Any item type. Only the list and tree nodes use it (Flatten, Graft, Partition, …), which move items without
    /// reading them; it is no type a value has, only one a socket may declare.
    case any

    /// Whether a wire carrying `source` may connect to a socket of this type.
    /// Only two implicit conversions exist: integer → number and vector → plane. An `any` socket accepts every type,
    /// and an `any` output may be wired to every type (the wire's items are checked when the node runs).
    public func accepts(_ source: SocketType) -> Bool {
        self == source || self == .any || source == .any
            || (self == .number && source == .integer) || (self == .plane && source == .vector)
    }
}
