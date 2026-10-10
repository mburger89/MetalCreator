/// How a click or a box combines what it hits with the selection (spec 2026-10-09 §3): no modifier replaces the
/// selection, ⇧ adds to it, and ⌘ toggles each item in or out. ⌘ wins when both are held.
public enum SelectionMode: Equatable, Sendable {
    case replace
    case add
    case toggle

    /// The mode `modifiers` ask for: a click's are those held at its press, a box's those held as its drag starts.
    /// ⌥ isn't a mode (it duplicates).
    public init(_ modifiers: CanvasModifiers) {
        if modifiers.contains(.command) {
            self = .toggle
        } else if modifiers.contains(.shift) {
            self = .add
        } else {
            self = .replace
        }
    }
}
