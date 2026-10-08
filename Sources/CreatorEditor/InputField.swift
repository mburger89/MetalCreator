import CreatorGraph
import CreatorKernel

/// An unwired input (or a node setting) the inspector edits: which node and socket, how to label
/// and show it, and its current constant (the stored value, else the socket's default). A setting
/// is a name that isn't an input socket (M3's `NodeSetting`); its `type` is `nil`, or `.bool` for
/// a toggle.
public struct InputField: Equatable, Sendable {
    public var node: NodeID
    public var socket: SocketName
    public var label: String
    public var type: SocketType?
    public var unit: ValueUnit
    public var value: ConstantValue?
    /// An optional input socket (`SocketSpec.isOptional`, such as M3's Grid Points `total`). With no
    /// default it starts unset (`value == nil`), and the inspector can clear it again.
    public var isOptional: Bool

    public init(node: NodeID, socket: SocketName, label: String, type: SocketType?, unit: ValueUnit,
                value: ConstantValue?, isOptional: Bool = false) {
        self.node = node
        self.socket = socket
        self.label = label
        self.type = type
        self.unit = unit
        self.value = value
        self.isOptional = isOptional
    }

    /// The value as a number, for sliders and number fields.
    public var number: Double? {
        switch value {
        case .number(let number)?: number
        case .integer(let integer)?: Double(integer)
        default: nil
        }
    }

    /// The value's x, y and z, for the three fields of a vector row; zeros when it isn't a vector.
    public var vectorComponents: [Double] {
        if case .vector(let vector)? = value { [vector.x, vector.y, vector.z] } else { [0, 0, 0] }
    }
}
