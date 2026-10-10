import MetalUI

/// The three buttons of the unsaved-changes alert that closing the window or quitting shows (spec §6.1), in the order
/// the alert lists them.
public enum SaveChangesAnswer: Sendable, Equatable, CaseIterable {
    /// Save (the document's file, or Save As… for an untitled one), then close.
    case save
    /// Close and lose the changes.
    case dontSave
    /// Keep the window open.
    case cancel

    /// The button's label.
    public var title: String {
        switch self {
        case .save: "Save"
        case .dontSave: "Don't Save"
        case .cancel: "Cancel"
        }
    }

    /// The button's role. Escape presses the cancel button. Don't Save is deliberately not destructive: MetalUI gives
    /// Return to the first plain button only when no button is destructive (SV-X), and Return must mean Save.
    public var role: ButtonRole? {
        self == .cancel ? .cancel : nil
    }
}
