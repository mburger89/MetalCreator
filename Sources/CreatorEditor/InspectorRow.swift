import CreatorGraph

/// One rendered inspector row, built from a node's `InspectorControl` data (spec §6.4).
public enum InspectorRow: Equatable, Sendable {
    case slider(InputField, range: ClosedRange<Double>)
    case number(InputField)
    case integer(InputField)
    case toggle(InputField, label: String)
    /// `selected` is the index of the current option, if it matches one.
    case segmented(InputField, options: [String], selected: Int?)
    case planePicker(InputField, selected: PlaneChoice?)
    /// Three number fields (x, y, z) for a vector socket.
    case vector(InputField)
    /// A 3×3 anchor grid; `selected` is 0…8, row-major from the top-left (4 is the centre).
    case anchorGrid(InputField, selected: Int?)
    case ruleSummary(label: String, summary: String)
    /// A menu of the document's parameters for a setting (M3's Graph Parameter). `selected` is
    /// the parameter the setting names, if it still exists.
    case parameterPicker(InputField, options: [GraphParameter], selected: ParameterID?)
    /// A line of text for a `.text` setting; `field.value` is the stored `.text`, or `nil` when none is stored.
    case text(InputField)
    case button(title: String, action: InspectorAction)
    /// A wired input: read-only text such as "wired from Edges ∥ Z".
    case wired(label: String, source: String)
    /// A data tree on one of the node's sockets: its shape and, opened, its branches (the Data section).
    case treeShape(TreeShapeRow)
    /// A value shown without an editor, such as a missing node's type.
    case readOnly(label: String, text: String)
}
