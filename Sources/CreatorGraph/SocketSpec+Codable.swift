/// A group definition saves its sockets (groups spec §4). Every key but `name` and `type` is optional on decode, with
/// the same defaults as `SocketSpec.init`.
extension SocketSpec: Codable {
    private enum CodingKeys: String, CodingKey { case name, type, access, defaultValue, unit, range, optional }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try container.decode(SocketName.self, forKey: .name), try container.decode(SocketType.self, forKey: .type),
                  access: try container.decodeIfPresent(Access.self, forKey: .access) ?? .item,
                  defaultValue: try container.decodeIfPresent(ConstantValue.self, forKey: .defaultValue),
                  unit: try container.decodeIfPresent(ValueUnit.self, forKey: .unit) ?? .none,
                  range: try container.decodeIfPresent(ClosedRange<Double>.self, forKey: .range),
                  optional: try container.decodeIfPresent(Bool.self, forKey: .optional) ?? false)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(access, forKey: .access)
        try container.encodeIfPresent(defaultValue, forKey: .defaultValue)
        try container.encode(unit, forKey: .unit)
        try container.encodeIfPresent(range, forKey: .range)
        try container.encode(isOptional, forKey: .optional)
    }
}
