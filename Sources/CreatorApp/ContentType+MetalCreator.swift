import CreatorKernel
import MetalUI

extension ContentType {
    /// A MetalCreator document (spec §4.5): JSON, saved as `.mcgraph`. Not registered with the system until the
    /// app is packaged, so the file panels match it by extension.
    public static let mcgraph = ContentType("com.metalcreator.mcgraph", conformingTo: [.json], filenameExtensions: ["mcgraph"])
    /// ISO 10303 STEP, for CNC and machinists (spec §1).
    public static let step = ContentType("public.step", conformingTo: [.data], filenameExtensions: ["step", "stp"])
    /// Stereolithography mesh, for 3D printing (spec §1).
    public static let stl = ContentType("public.standard-tesselated-geometry-format", conformingTo: [.data],
                                        filenameExtensions: ["stl"])

    /// 3D Manufacturing Format, for 3D printing (implicit spec §5.3).
    public static let threeMF = ContentType("org.3mf.3mf", conformingTo: [.data], filenameExtensions: ["3mf"])

    /// The file type an export format writes.
    public static func exported(_ kind: ExportKind) -> ContentType {
        switch kind {
        case .step: .step
        case .stl: .stl
        case .threeMF: .threeMF
        }
    }
}
