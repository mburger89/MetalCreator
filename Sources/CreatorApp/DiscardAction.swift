/// What the app does once the person agrees to discard unsaved changes.
public enum DiscardAction {
    case newDocument
    case openDocument(any FilePicker)
}
