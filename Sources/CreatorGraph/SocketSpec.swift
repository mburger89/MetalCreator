/// Declares one input or output socket of a node type.
public struct SocketSpec: Sendable, Equatable {
    /// `.item` sockets broadcast over lists. `.list` sockets receive the whole list at once.
    public enum Access: Sendable, Equatable { case item, list }

    public var name: SocketName
    public var type: SocketType
    public var access: Access
    public var defaultValue: ConstantValue?
    public var unit: ValueUnit
    /// A UI hint for sliders. Values outside it are allowed.
    public var range: ClosedRange<Double>?
    public var isOptional: Bool

    public init(_ name: SocketName, _ type: SocketType, access: Access = .item, defaultValue: ConstantValue? = nil,
                unit: ValueUnit = .none, range: ClosedRange<Double>? = nil, optional: Bool = false) {
        self.name = name
        self.type = type
        self.access = access
        self.defaultValue = defaultValue
        self.unit = unit
        self.range = range
        self.isOptional = optional
    }
}
