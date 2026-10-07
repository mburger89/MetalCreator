/// The closed set of socket types (spec §4.2). `mesh` is reserved for sub-project 7.
public enum SocketType: String, Sendable, Codable, CaseIterable {
    case number, integer, bool, vector, plane, profile, solid, edgeSet, faceSet

    /// Whether a wire carrying `source` may connect to a socket of this type.
    /// Only two implicit conversions exist: integer → number and vector → plane.
    public func accepts(_ source: SocketType) -> Bool {
        self == source || (self == .number && source == .integer) || (self == .plane && source == .vector)
    }
}
