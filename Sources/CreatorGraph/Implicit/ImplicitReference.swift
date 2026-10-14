/// An implicit solid as a value on a wire (`Scalar.implicit`) and as a field leaf (`Field.implicit`): an `ImplicitPayload`
/// with value equality, so `Field` stays `Hashable`.
public struct ImplicitReference: Hashable, Sendable {
    public let payload: any ImplicitPayload

    public init(_ payload: any ImplicitPayload) {
        self.payload = payload
    }

    public static func == (lhs: ImplicitReference, rhs: ImplicitReference) -> Bool { lhs.payload.isEqual(to: rhs.payload) }

    public func hash(into hasher: inout Hasher) { payload.hashPayload(into: &hasher) }
}
