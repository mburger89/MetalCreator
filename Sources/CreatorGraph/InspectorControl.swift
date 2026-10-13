/// One control in a node's context inspector, bound to an input socket (spec §6.4).
public enum InspectorControl: Sendable, Equatable {
    case slider(SocketName)
    case number(SocketName)
    case integer(SocketName)
    case toggle(SocketName, label: String)
    case segmented(SocketName, options: [String])
    case planePicker(SocketName)
    /// Three number fields (x, y, z) for a vector socket.
    case vector(SocketName)
    case anchorGrid(SocketName)
    case ruleSummary(SocketName)
    /// A menu of the document's graph parameters, stored as `.text(uuidString)` in a setting.
    case parameterPicker(SocketName)
    /// A line of text for a `.text` setting (the Path Mapper's rule, Branch by Path's path), committed on Return or when
    /// the field loses focus.
    case text(SocketName)
    /// An image setting's picture (the Image Field's `NodeSetting.image`): what it is (embedded or linked) and the buttons that
    /// choose, link, relink and embed it, which depend on that (fields spec §5).
    case image(SocketName)
    case button(title: String, action: InspectorAction)
}
