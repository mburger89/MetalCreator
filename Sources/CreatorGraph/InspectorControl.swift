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
    case button(title: String, action: InspectorAction)
}
