/// The alert the window shows, if any.
public enum AppAlert: Equatable {
    /// Something failed; the alert has one OK button.
    case problem(AppProblem)
    /// New or Open with unsaved changes: Discard Changes or Cancel.
    case discardChanges
    /// Closing the window or quitting with unsaved changes to the document called `name`: Save, Don't Save or Cancel.
    case saveChanges(name: String)

    public var title: String {
        switch self {
        case .problem(let problem): problem.title
        case .discardChanges: "Discard unsaved changes?"
        case .saveChanges(let name): "Do you want to save the changes to “\(name)”?"
        }
    }

    public var message: String {
        switch self {
        case .problem(let problem): problem.message
        case .discardChanges: "This document has changes that haven't been saved."
        case .saveChanges: "Your changes will be lost if you don't save them."
        }
    }
}
