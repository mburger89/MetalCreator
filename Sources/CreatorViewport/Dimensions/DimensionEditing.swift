/// An entry the host adds to a context menu (a dimension's Pin, a tool's own). `key` names it for the host.
public struct HostMenuAction: Hashable, Sendable {
    public var title: String
    public var key: String

    public init(title: String, key: String) {
        self.title = title
        self.key = key
    }
}

/// What a dimension's value box opens with: the text to edit and an optional note shown under the box.
public struct DimensionValueBoxContent: Hashable, Sendable {
    public var text: String
    public var note: String?

    public init(text: String, note: String? = nil) {
        self.text = text
        self.note = note
    }
}

/// The host's answer to a typed value.
public enum DimensionCommitOutcome: Hashable, Sendable {
    case accepted
    /// Not taken, with the plain-language reason the box shows in red.
    case refused(String)
}

/// Whoever owns the dimensions the viewport draws (the sketch editor, the app shell) answers its edits and menus through this.
@MainActor
public protocol DimensionEditing: AnyObject {
    /// What the box for `id` opens with, or `nil` when the dimension cannot be edited (no box opens).
    func valueBoxContent(for id: OverlayDimensionID) -> DimensionValueBoxContent?
    /// Takes the text typed for `id`. The viewport shows the box as checking until this answers.
    func commitValue(_ text: String, to id: OverlayDimensionID) async -> DimensionCommitOutcome
    /// The entries for a right-click on `id`'s text (default: none).
    func menuActions(for id: OverlayDimensionID) -> [HostMenuAction]
    /// Runs a chosen entry (default: nothing).
    func performMenuAction(_ action: HostMenuAction, for id: OverlayDimensionID)
    /// What to say under `id`'s text while the pointer is on it, e.g. a reference's source (default: nothing).
    func hoverNote(for id: OverlayDimensionID) -> String?
}

extension DimensionEditing {
    public func menuActions(for id: OverlayDimensionID) -> [HostMenuAction] { [] }
    public func performMenuAction(_ action: HostMenuAction, for id: OverlayDimensionID) {}
    public func hoverNote(for id: OverlayDimensionID) -> String? { nil }
}
