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

    public init(owner: UUID? = nil, text: String, commit: @escaping @MainActor (Double) -> Void, clear: (@MainActor () -> Void)? = nil) {
        self.owner = owner
        self.text = text
        self.commit = commit
        self.clear = clear
    }

    /// Commits a readable number, or clears an emptied optional field. An unreadable entry is discarded.
    @MainActor
    func apply() {
        if let clear, text.trimmingCharacters(in: .whitespaces).isEmpty {
            clear()
        } else if let value = ValueText.parse(text) {
            commit(value)
        }
    }
}
