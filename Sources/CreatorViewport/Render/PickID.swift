import CreatorKernel

/// The ID-buffer encoding (spec §6.3: "solid index, face or edge, id") in one `r32Uint` texel:
/// - the top 2 bits are the kind (0 nothing, 1 face, 2 edge)
/// - the next 8 bits are the solid index
/// - the low 22 bits are the face or edge ID
enum PickID {
    static let faceKind: UInt32 = 1
    static let edgeKind: UInt32 = 2
    static let maxSolids = 256
    static let maxElements = 1 << 22

    /// The kind and solid bits, ready to OR with a face or edge ID, or `nil` if the solid index doesn't fit.
    static func base(kind: UInt32, solid: Int) -> UInt32? {
        guard (0..<maxSolids).contains(solid) else { return nil }
        return (kind << 30) | (UInt32(solid) << 22)
    }

    static func encode(_ target: PickTarget) -> UInt32? {
        let (kind, solid, element) = switch target {
        case .face(let solid, let face): (faceKind, solid, face.rawValue)
        case .edge(let solid, let edge): (edgeKind, solid, edge.rawValue)
        }
        guard (0..<maxElements).contains(element), let base = base(kind: kind, solid: solid) else { return nil }
        return base | UInt32(element)
    }

    static func decode(_ raw: UInt32) -> PickTarget? {
        let solid = Int((raw >> 22) & 0xFF)
        let element = Int(raw & 0x3F_FFFF)
        switch raw >> 30 {
        case faceKind: return .face(solid: solid, FaceID(element))
        case edgeKind: return .edge(solid: solid, EdgeID(element))
        default: return nil
        }
    }
}
