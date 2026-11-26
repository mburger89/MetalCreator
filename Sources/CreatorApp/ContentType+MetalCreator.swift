import CreatorKernel
import MetalUI

extension ContentType {
    /// A MetalCreator document (spec §4.5): JSON, saved as `.mcgraph`. Not registered with the system until the
    /// app is packaged, so the file panels match it by extension.
    public static let mcgraph = ContentType("com.metalcreator.mcgraph", conformingTo: [.json], filenameExtensions: ["mcgraph"],
                                           localizedDescription: "MetalCreator graph")
    /// ISO 10303 STEP, for CNC and machinists (spec §1).
    public static let step = ContentType("public.step", conformingTo: [.data], filenameExtensions: ["step", "stp"],
                                          localizedDescription: "STEP model")
    /// IGES, read by the Import Model node.
    public static let iges = ContentType("public.iges", conformingTo: [.data], filenameExtensions: ["igs", "iges"],
                                         localizedDescription: "IGES model")
    /// Stereolithography mesh, for 3D printing (spec §1).
    public static let stl = ContentType("public.standard-tesselated-geometry-format", conformingTo: [.data],
                                        filenameExtensions: ["stl"], localizedDescription: "STL mesh")

    /// 3D Manufacturing Format, for 3D printing (implicit spec §5.3).
    public static let threeMF = ContentType("org.3mf.3mf", conformingTo: [.data], filenameExtensions: ["3mf"],
                                               localizedDescription: "3MF model")

    /// A KiCad board, read by the Import KiCad Board node.
    public static let kicadPCB = ContentType("org.kicad.pcb", conformingTo: [.data], filenameExtensions: ["kicad_pcb"],
                                             localizedDescription: "KiCad board")

    /// A drawing as a PDF, one page per sheet.
    public static let pdf = ContentType("com.adobe.pdf", conformingTo: [.data], filenameExtensions: ["pdf"],
                                        localizedDescription: "PDF document")

    /// A drawing as a DXF, for CAD and CAM programs.
    public static let dxf = ContentType("com.autodesk.dxf", conformingTo: [.data], filenameExtensions: ["dxf"],
                                        localizedDescription: "DXF drawing")

    /// A drawing sheet as an SVG picture.
    public static let svg = ContentType("public.svg-image", conformingTo: [.data], filenameExtensions: ["svg"],
                                        localizedDescription: "SVG image")

    /// The file type a drawing export writes.
    public static func exported(_ kind: DrawingExportKind) -> ContentType {
        switch kind {
        case .pdf, .pdfSheet: .pdf
        case .svgSheet: .svg
        case .dxfSheet, .dxfView, .dxfViewWithAnnotations: .dxf
        }
    }

    /// The file type an export format writes.
    public static func exported(_ kind: ExportKind) -> ContentType {
        switch kind {
        case .step: .step
        case .stl: .stl
        case .threeMF: .threeMF
        }
    }
}
