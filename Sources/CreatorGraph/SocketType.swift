/// The closed set of socket types (spec §4.2).
public enum SocketType: String, Sendable, Codable, CaseIterable {
    case number, integer, bool, vector, plane, profile, solid, edgeSet, faceSet
    /// A value that varies over space (fields spec §2.1). A number or integer converts to one; nothing converts back.
    case field
    /// A signed distance function (implicit spec §2.1). An implicit converts to a field; nothing converts to one but
    /// To Implicit and Isosurface.
    case implicit
    /// A watertight triangle mesh (implicit spec §2.2). An implicit wired into a mesh socket is meshed at the Mesh node's
    /// default settings by the node that takes it.
    case mesh
    /// Any item type. Only the list and tree nodes use it (Flatten, Graft, Partition, …), which move items without
    /// reading them; it is no type a value has, only one a socket may declare.
    case any

    /// Whether a wire carrying `source` may connect to a socket of this type.
    /// Only these implicit conversions exist: integer → number, vector → plane, number, integer or implicit → field, and
    /// implicit → mesh. An `any` socket accepts every type,
    /// and an `any` output may be wired to every type (the wire's items are checked when the node runs).
    public func accepts(_ source: SocketType) -> Bool {
        self == source || self == .any || source == .any
            || (self == .number && source == .integer) || (self == .plane && source == .vector)
            || (self == .field && (source == .number || source == .integer || source == .implicit))
            || (self == .mesh && source == .implicit)
    }
}
