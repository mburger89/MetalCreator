import Foundation

extension ConstantValue {
    /// The `NodeSetting.parameter` value that makes a Graph Parameter node read `id`.
    public static func parameter(_ id: ParameterID) -> ConstantValue {
        .text(id.rawValue.uuidString)
    }

    /// The parameter a `NodeSetting.parameter` value names, or `nil` if it isn't one.
    public var parameterID: ParameterID? {
        guard case .text(let raw) = self, let uuid = UUID(uuidString: raw) else { return nil }
        return ParameterID(rawValue: uuid)
    }

    /// The `NodeSetting.group` value that ties a group node (or a Group Input or Output) to definition `id`.
    public static func group(_ id: GroupID) -> ConstantValue {
        .text(id.rawValue.uuidString)
    }

    /// The definition a `NodeSetting.group` value names, or `nil` if it isn't one.
    public var groupID: GroupID? {
        guard case .text(let raw) = self, let uuid = UUID(uuidString: raw) else { return nil }
        return GroupID(rawValue: uuid)
    }
}
