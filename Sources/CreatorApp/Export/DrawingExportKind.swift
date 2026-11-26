/// The files a drawing exports to (drawings plan R25, DR-5 R15): beside `ExportKind`, not inside it, so STEP, STL and 3MF's switches stay as they are.
public enum DrawingExportKind: String, CaseIterable, Sendable {
    /// Every sheet, one page each, in tab order.
    case pdf
    /// The open sheet, one page.
    case pdfSheet
    /// The open sheet, in sheet millimetres.
    case dxfSheet
    /// The one selected view at 1:1, in model millimetres.
    case dxfView
    /// The one selected view at 1:1 with its dimensions, callouts, notes, balloons and centre marks, in model millimetres (plan R22).
    case dxfViewWithAnnotations
    /// The open sheet as an SVG, in sheet millimetres (DR-5 R14).
    case svgSheet

    /// The file extension.
    var fileExtension: String {
        switch self {
        case .pdf, .pdfSheet: "pdf"
        case .svgSheet: "svg"
        case .dxfSheet, .dxfView, .dxfViewWithAnnotations: "dxf"
        }
    }

    /// The name of the format in a message.
    var title: String {
        switch self {
        case .pdf, .pdfSheet: "PDF"
        case .svgSheet: "SVG"
        case .dxfSheet, .dxfView, .dxfViewWithAnnotations: "DXF"
        }
    }
}
