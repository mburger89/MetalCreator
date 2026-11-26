import CreatorDrawing
import Foundation

/// How a client names a sheet and a view of a drawing (DR-5 R19).
public enum DrawingAddressing {
    /// The sheet `ref` names: a full UUID, else a name that exactly one sheet has.
    public static func sheet(_ ref: JSONValue?, in document: DrawingDocument) -> Result<SheetID, Refusal> {
        guard let text = ref?.string, !text.isEmpty else { return .failure(Refusal("Say which sheet, by its ID or name.")) }
        if let uuid = UUID(uuidString: text) {
            let id = SheetID(rawValue: uuid)
            return document.sheet(id) != nil ? .success(id) : .failure(Refusal("There's no sheet with ID \(text)."))
        }
        let matches = document.sheets.filter { $0.name == text }
        switch matches.count {
        case 0: return .failure(Refusal("There's no sheet called “\(text)”."))
        case 1: return .success(matches[0].id)
        default: return .failure(Refusal("Two sheets are called “\(text)”; use the sheet's ID."))
        }
    }

    /// The view `ref` names on `sheet`, by its full ID.
    public static func view(_ ref: JSONValue?, on sheet: DrawingSheet) -> Result<ViewID, Refusal> {
        guard let text = ref?.string, !text.isEmpty else { return .failure(Refusal("Say which view, by its ID.")) }
        if let uuid = UUID(uuidString: text) {
            let id = ViewID(rawValue: uuid)
            if sheet.view(id) != nil { return .success(id) }
        }
        return .failure(Refusal("There's no view with ID \(text) on “\(sheet.name)”."))
    }
}
