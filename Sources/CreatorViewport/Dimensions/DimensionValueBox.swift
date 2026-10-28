import MetalUI

/// The value box of a dimension being edited (spec §7): a draft that changes nothing until Return.
public struct DimensionValueBox: Hashable, Sendable {
    public var id: OverlayDimensionID
    /// What the field holds now.
    public var draft: String
    /// What it opened with: Return on an untouched draft commits nothing.
    public var opening: String
    public var selection: TextSelection?
    /// Shown under the box (the editor's note).
    public var note: String?
    /// The reason the last commit was refused, shown in red.
    public var message: String?
    /// True while the host checks a commit: the box takes no input.
    public var isChecking: Bool

    public init(id: OverlayDimensionID, draft: String, opening: String, selection: TextSelection? = nil, note: String? = nil,
                message: String? = nil, isChecking: Bool = false) {
        self.id = id
        self.draft = draft
        self.opening = opening
        self.selection = selection
        self.note = note
        self.message = message
        self.isChecking = isChecking
    }
}
