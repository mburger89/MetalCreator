import Foundation

/// What the app does once the person agrees to discard unsaved changes.
public enum DiscardAction {
    case newDocument
    case openDocument(any FilePicker)
    /// A file the system asked the app to open (Finder, the Dock, `open`).
    case openURL(URL)
}
