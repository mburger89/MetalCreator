import CreatorDrawing
import MetalUI

/// A sheet's name being typed into its tab: what the field holds and selects. View state: never undone, never saved.
public struct SheetRename: Equatable {
    public var sheet: SheetID
    public var draft: String
    public var selection: TextSelection?

    public init(sheet: SheetID, draft: String, selection: TextSelection?) {
        self.sheet = sheet
        self.draft = draft
        self.selection = selection
    }
}
