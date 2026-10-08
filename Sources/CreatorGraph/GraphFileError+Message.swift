extension GraphFileError {
    /// A sentence for the person opening the file (the app shell shows it, M6).
    public var message: String {
        switch self {
        case .newerFormat(let version):
            "This file was saved by a newer version of MetalCreator (file format \(version)). "
                + "Update MetalCreator to open it."
        }
    }
}
