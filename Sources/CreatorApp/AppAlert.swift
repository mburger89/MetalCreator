/// The alert the window shows, if any.
public enum AppAlert {
    /// Something failed; the alert has one OK button.
    case problem(AppProblem)
    /// New or Open with unsaved changes: Discard Changes or Cancel.
    case discardChanges

    public var title: String {
        switch self {
        case .problem(let problem): problem.title
        case .discardChanges: "Discard unsaved changes?"
        }
    }

    public var message: String {
        switch self {
        case .problem(let problem): problem.message
        case .discardChanges: "This document has changes that haven't been saved."
        }
    }
}
