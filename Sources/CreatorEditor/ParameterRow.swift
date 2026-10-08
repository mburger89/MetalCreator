import CreatorGraph

/// One document parameter in the inspector, with its slider range.
public struct ParameterRow: Equatable, Sendable, Identifiable {
    public var parameter: GraphParameter
    public var range: ClosedRange<Double>

    public var id: ParameterID { parameter.id }
}
