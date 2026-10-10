/// An entry of the canvas's context menu (canvas comments spec 2026-10-09 §7). `GraphCanvas` lists `allCases` as
/// buttons, disabled by `EditorModel.isEnabled(_:)`, and runs `EditorModel.choose(_:at:)` with the point the menu
/// opened at.
public enum CanvasMenuItem: CaseIterable, Equatable, Sendable {
    case addNote
    case frameSelection

    public var title: String {
        switch self {
        case .addNote: "Add Note"
        case .frameSelection: "Frame Selection"
        }
    }
}
