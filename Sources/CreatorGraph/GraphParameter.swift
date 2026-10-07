/// A named document input (for example Width or Wall), shown in the inspector. A variant
/// is a saved set of these values (spec §4.1).
public struct GraphParameter: Sendable, Codable, Equatable, Identifiable {
    public var id: ParameterID
    public var name: String
    public var type: SocketType
    public var value: ConstantValue
    public var min: Double?
    public var max: Double?
    public var step: Double?

    public init(id: ParameterID = ParameterID(), name: String, type: SocketType, value: ConstantValue,
                min: Double? = nil, max: Double? = nil, step: Double? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.value = value
        self.min = min
        self.max = max
        self.step = step
    }
}
