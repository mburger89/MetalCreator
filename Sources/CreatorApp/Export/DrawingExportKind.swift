/// The files a drawing exports to (drawings plan R25): beside `ExportKind`, not inside it, so STEP, STL and 3MF's switches stay as they are.
public enum DrawingExportKind: String, CaseIterable, Sendable {
    /// Every sheet, one page each.
    case pdf
    /// The open sheet, in sheet millimetres.
    case dxfSheet
    /// The one selected view at 1:1, in model millimetres.
    case dxfView
    /// The one selected view at 1:1 with its dimensions, callouts, notes and centre marks, in model millimetres (plan R22).
    case dxfViewWithAnnotations

    /// The file extension.
    var fileExtension: String { self == .pdf ? "pdf" : "dxf" }

    /// The name of the format in a message.
    var title: String { self == .pdf ? "PDF" : "DXF" }
}
