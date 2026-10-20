import CreatorKernel

/// The file formats the File menu exports (implicit spec §5.3). STEP and STL are the kernel's `ExportFormat`; 3MF is ours, so it is not
/// one of the kernel's.
public enum ExportKind: String, CaseIterable, Sendable {
    case step
    case stl
    case threeMF = "3mf"

    /// What the kernel writes itself, `nil` for 3MF.
    var kernelFormat: ExportFormat? {
        switch self {
        case .step: .step
        case .stl: .stl
        case .threeMF: nil
        }
    }

    /// The name of the format in a message: "STEP", "STL", "3MF".
    var title: String { rawValue.uppercased() }
}
