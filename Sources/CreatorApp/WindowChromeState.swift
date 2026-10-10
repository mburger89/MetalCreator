import Foundation

/// What the window's title bar says about the open document (gap M6-a).
public struct WindowChromeState: Equatable, Sendable {
    /// The file's name, or "Untitled".
    public var title: String
    /// Unsaved changes: the dot in the close button.
    public var isEdited: Bool
    /// The document's file, or `nil` for an untitled one: the proxy icon.
    public var fileURL: URL?
}
