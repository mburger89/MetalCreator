import Foundation

/// A number typed into an inspector field and not yet committed with Return (M6). It carries the field's own
/// commit and clear actions, captured as it was typed, so committing it later always writes the field it was
/// typed into, even after the inspector has moved on to another node.
public struct PendingEntry {
    /// Identifies the field that recorded it, so that field can drop its own entry when its value changes
    /// underneath it (`EditorModel.discardPendingEntry(ownedBy:)`).
    public var owner: UUID?
    public var text: String
    public var commit: @MainActor (Double) -> Void
    /// Set for an optional input: emptying the field clears it.
    public var clear: (@MainActor () -> Void)?
    /// Set for a text field (a group's or a socket's name): it takes the text as it is, and `commit` is unused.
    public var commitText: (@MainActor (String) -> Void)?

    public init(owner: UUID? = nil, text: String, commit: @escaping @MainActor (Double) -> Void, clear: (@MainActor () -> Void)? = nil) {
        self.owner = owner
        self.text = text
        self.commit = commit
        self.clear = clear
    }

    /// A text field's entry: `commitText` gets the text, however it reads.
    public init(owner: UUID? = nil, text: String, commitText: @escaping @MainActor (String) -> Void) {
        self.owner = owner
        self.text = text
        self.commit = { _ in }
        self.commitText = commitText
    }

    /// Commits a readable number, or clears an emptied optional field. An unreadable entry is discarded. A text
    /// field's entry is committed as typed.
    @MainActor
    func apply() {
        if let commitText {
            commitText(text)
        } else if let clear, text.trimmingCharacters(in: .whitespaces).isEmpty {
            clear()
        } else if let value = ValueText.parse(text) {
            commit(value)
        }
    }
}
