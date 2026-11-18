import CreatorGeometry
import CreatorKernel
import CreatorSketch

/// A value typed into an unwired input or stored as a node setting, saved in the file.
public enum ConstantValue: Hashable, Sendable {
    case number(Double)
    case integer(Int)
    case bool(Bool)
    case vector(Vector3)
    case plane(Plane)
    /// A non-socket setting, such as the parameter a Graph Parameter node reads.
    case text(String)
    /// The picked edges an Edges by Tag rule remembers (spec §5.3, rule 5). A setting, never a socket value.
    case edgePicks([EdgePick])
    /// A Sketch node's sketch (sketcher spec §3, §7). A setting, never a socket value.
    case sketch(Sketch)
    /// The face a Plane from Face node is on (sketcher spec §7). A setting, never a socket value.
    case facePick(FacePick)
    /// An Image Field's picture, embedded or linked (fields spec §5). A setting, never a socket value.
    case image(ImageReference)
    /// An Import Mesh node's file, embedded or linked (mesh import spec, File setting): the same reference as an image, its
    /// embedded bytes in the document's `images` table. A setting, never a socket value.
    case meshFile(ImageReference)
    /// An Import KiCad Board node's file, linked only (KiCad import spec): the same reference as an image. A setting,
    /// never a socket value.
    case pcbFile(ImageReference)
    /// An Import Model node's file (NURBS spec, Import Model): the same reference as an image, embedded or linked, its embedded
    /// bytes in the document's `images` table. A setting, never a socket value.
    case modelFile(ImageReference)

    /// The reference of an `image`, `meshFile` or `pcbFile` setting: what paths, stamps, hashes and the clipboard read, because both
    /// kinds are held, resolved and embedded the same way.
    public var fileReference: ImageReference? {
        switch self {
        case .image(let reference), .meshFile(let reference), .pcbFile(let reference), .modelFile(let reference): reference
        default: nil
        }
    }

    private var fileKind: Kind {
        switch self {
        case .meshFile: .meshFile
        case .pcbFile: .pcbFile
        case .modelFile: .modelFile
        default: .image
        }
    }

    /// False for NaN or ±∞ anywhere. JSON can't store those, so commands reject them.
    public var isFinite: Bool {
        switch self {
        case .number(let value): value.isFinite
        case .vector(let vector): vector.isFinite
        case .plane(let plane): plane.origin.isFinite && plane.normal.isFinite && plane.xAxis.isFinite
        case .sketch(let sketch): sketch.isFinite
        case .integer, .bool, .text, .edgePicks, .facePick, .image, .meshFile, .pcbFile, .modelFile: true
        }
    }
}

extension ConstantValue: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable {
        case number, integer, bool, vector, plane, text, edgePicks, sketch, facePick, image, meshFile, pcbFile, modelFile
    }

    private static func fileSetting(of kind: Kind, _ reference: ImageReference) -> ConstantValue {
        switch kind {
        case .meshFile: .meshFile(reference)
        case .pcbFile: .pcbFile(reference)
        case .modelFile: .modelFile(reference)
        default: .image(reference)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .number: self = .number(try container.decode(Double.self, forKey: .value))
        case .integer: self = .integer(try container.decode(Int.self, forKey: .value))
        case .bool: self = .bool(try container.decode(Bool.self, forKey: .value))
        case .vector: self = .vector(try container.decode(Vector3.self, forKey: .value))
        case .plane: self = .plane(try container.decode(Plane.self, forKey: .value))
        case .text: self = .text(try container.decode(String.self, forKey: .value))
        case .edgePicks: self = .edgePicks(try container.decode([EdgePick].self, forKey: .value))
        case .sketch: self = .sketch(try container.decode(Sketch.self, forKey: .value))
        case .facePick: self = .facePick(try container.decode(FacePick.self, forKey: .value))
        case .image, .meshFile, .pcbFile, .modelFile:
            self = Self.fileSetting(of: kind, try container.decode(ImageReference.self, forKey: .value))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .number(let value): try container.encode(Kind.number, forKey: .type); try container.encode(value, forKey: .value)
        case .integer(let value): try container.encode(Kind.integer, forKey: .type); try container.encode(value, forKey: .value)
        case .bool(let value): try container.encode(Kind.bool, forKey: .type); try container.encode(value, forKey: .value)
        case .vector(let value): try container.encode(Kind.vector, forKey: .type); try container.encode(value, forKey: .value)
        case .plane(let value): try container.encode(Kind.plane, forKey: .type); try container.encode(value, forKey: .value)
        case .text(let value): try container.encode(Kind.text, forKey: .type); try container.encode(value, forKey: .value)
        case .edgePicks(let value): try container.encode(Kind.edgePicks, forKey: .type); try container.encode(value, forKey: .value)
        case .sketch(let value): try container.encode(Kind.sketch, forKey: .type); try container.encode(value, forKey: .value)
        case .facePick(let value): try container.encode(Kind.facePick, forKey: .type); try container.encode(value, forKey: .value)
        case .image(let value), .meshFile(let value), .pcbFile(let value), .modelFile(let value):
            try container.encode(fileKind, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}
