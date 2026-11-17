import Foundation

/// A 3D model file's format, from its name, checked against its bytes.
public enum ModelFormat: Sendable, Hashable {
    case step, stepGzip, iges, vrml, vrmlGzip, x3d, idf, unknown

    public init(fileName: String) {
        let name = fileName.lowercased()
        if name.hasSuffix(".stp.gz") || name.hasSuffix(".step.gz") {
            self = .stepGzip
            return
        }
        let ext = name.split(separator: ".", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        guard name.contains(".") else { self = .unknown; return }
        switch ext {
        case "stp", "step": self = .step
        case "stpz", "stepz": self = .stepGzip
        case "igs", "iges": self = .iges
        case "wrl": self = .vrml
        case "wrz": self = .vrmlGzip
        case "x3d": self = .x3d
        case "idf": self = .idf
        default: self = .unknown
        }
    }

    /// Whether the bytes agree with the format.
    public func matches(_ bytes: Data) -> Bool {
        let data = Data(bytes.prefix(4096))
        switch self {
        case .stepGzip, .vrmlGzip:
            return data.count >= 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
        case .step:
            return Self.trimmed(data).starts(with: Array("ISO-10303-21".utf8))
        case .idf:
            return Self.trimmed(data).starts(with: Array(".HEADER".utf8))
        case .vrml:
            return data.starts(with: Array("#VRML V1.0".utf8)) || data.starts(with: Array("#VRML V2.0".utf8))
        case .x3d:
            return data.range(of: Data("<X3D".utf8)) != nil
        case .iges:
            let line = data.prefix { $0 != 0x0A && $0 != 0x0D }
            guard line.count >= 73 else { return false }
            return line[line.startIndex + 72] == UInt8(ascii: "S")
        case .unknown:
            return false
        }
    }

    private static func trimmed(_ data: Data) -> Data {
        Data(data.drop { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D })
    }
}
