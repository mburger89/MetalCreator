import CreatorDrawing

/// What the editor asks of its host, which owns the panels, the template folder and the image pool (DR-5 R10, R16).
public enum DrawingEditorRequest: Hashable, Sendable {
    case newSheetFromTemplate(String)
    case saveSheetAsTemplate(SheetID)
    case chooseLogo(SheetID)
    case renameTemplate(String, to: String)
    case deleteTemplate(String)
}

/// A template the sheet inspector offers: its id and name; set by the host.
public struct DrawingTemplateChoice: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
