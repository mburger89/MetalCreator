/// What the window shows in its model area (drawings plan R21): the 3D viewport, or the drawing's sheets. Saved as
/// `ViewState.drawing`; switching is view state, never an edit and never an undo step.
public enum WorkspaceMode: String, CaseIterable, Sendable {
    case model
    case drawing

    /// The segmented control's and the View menu's word.
    public var title: String {
        switch self {
        case .model: "Model"
        case .drawing: "Drawing"
        }
    }
}
