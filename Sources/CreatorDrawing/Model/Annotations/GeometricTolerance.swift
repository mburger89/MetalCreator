import CreatorGeometry

/// The family a characteristic belongs to (ISO 1101's grouping; plan R7).
public enum ToleranceFamily: String, Hashable, Codable, Sendable {
    case form, profile, orientation, location, runout
}

/// The fourteen characteristics of ISO 1101, in the order the editor lists them (plan R7).
public enum GeometricCharacteristic: String, Hashable, Codable, Sendable, CaseIterable {
    case straightness, flatness, circularity, cylindricity, lineProfile, surfaceProfile
    case parallelism, perpendicularity, angularity
    case position, concentricity, symmetry
    case circularRunout, totalRunout

    public var title: String {
        switch self {
        case .straightness: "Straightness"
        case .flatness: "Flatness"
        case .circularity: "Circularity"
        case .cylindricity: "Cylindricity"
        case .lineProfile: "Profile of a line"
        case .surfaceProfile: "Profile of a surface"
        case .parallelism: "Parallelism"
        case .perpendicularity: "Perpendicularity"
        case .angularity: "Angularity"
        case .position: "Position"
        case .concentricity: "Concentricity"
        case .symmetry: "Symmetry"
        case .circularRunout: "Circular run-out"
        case .totalRunout: "Total run-out"
        }
    }

    public var family: ToleranceFamily {
        switch self {
        case .straightness, .flatness, .circularity, .cylindricity: .form
        case .lineProfile, .surfaceProfile: .profile
        case .parallelism, .perpendicularity, .angularity: .orientation
        case .position, .concentricity, .symmetry: .location
        case .circularRunout, .totalRunout: .runout
        }
    }

    /// Whether the zone may be a diameter (Ø).
    public var takesDiameterZone: Bool {
        switch self {
        case .straightness, .parallelism, .perpendicularity, .angularity, .position, .concentricity: true
        default: false
        }
    }

    /// Whether Ⓜ and Ⓛ apply.
    public var takesMaterialCondition: Bool {
        switch self {
        case .straightness, .parallelism, .perpendicularity, .angularity, .position: true
        default: false
        }
    }

    /// Whether Ⓣ (tangent plane) applies.
    public var takesTangentPlane: Bool {
        switch self {
        case .flatness, .lineProfile, .surfaceProfile, .parallelism, .perpendicularity, .angularity: true
        default: false
        }
    }

    /// Whether Ⓟ (projected tolerance zone) applies.
    public var takesProjectedZone: Bool {
        switch self {
        case .parallelism, .perpendicularity, .angularity, .position: true
        default: false
        }
    }

    /// Whether a composite (two row) frame is allowed.
    public var allowsComposite: Bool {
        switch self {
        case .lineProfile, .surfaceProfile, .position: true
        default: false
        }
    }

    /// False for concentricity and symmetry, which ASME Y14.5-2018 dropped.
    public var isInASME: Bool {
        switch self {
        case .concentricity, .symmetry: false
        default: true
        }
    }
}

public enum ToleranceZone: String, Hashable, Codable, Sendable {
    case width, diameter
}

/// Ⓜ (maximum) or Ⓛ (least material condition).
public enum MaterialCondition: String, Hashable, Codable, Sendable {
    case maximum, least
}

/// Ⓟ: a projected tolerance zone, with its length when stated (mm).
public struct ProjectedZone: Hashable, Codable, Sendable {
    public var length: Double?

    public init(length: Double? = nil) {
        self.length = length
    }
}

public struct DatumReference: Hashable, Codable, Sendable {
    public var letter: String
    public var material: MaterialCondition?

    public init(letter: String, material: MaterialCondition? = nil) {
        self.letter = letter
        self.material = material
    }
}

/// One row of a feature control frame; `value` is in millimetres.
public struct ToleranceRow: Hashable, Codable, Sendable {
    public var zone: ToleranceZone
    public var value: Double
    public var material: MaterialCondition?
    public var freeState: Bool
    public var tangentPlane: Bool
    public var projected: ProjectedZone?
    public var datums: [DatumReference]

    public init(
        zone: ToleranceZone = .width, value: Double, material: MaterialCondition? = nil, freeState: Bool = false,
        tangentPlane: Bool = false, projected: ProjectedZone? = nil, datums: [DatumReference] = []
    ) {
        self.zone = zone
        self.value = value
        self.material = material
        self.freeState = freeState
        self.tangentPlane = tangentPlane
        self.projected = projected
        self.datums = datums
    }

    private enum CodingKeys: String, CodingKey {
        case zone, value, material, freeState, tangentPlane, projected, datums
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        zone = try c.decodeIfPresent(ToleranceZone.self, forKey: .zone) ?? .width
        value = try c.decode(Double.self, forKey: .value)
        material = try c.decodeIfPresent(MaterialCondition.self, forKey: .material)
        freeState = try c.decodeIfPresent(Bool.self, forKey: .freeState) ?? false
        tangentPlane = try c.decodeIfPresent(Bool.self, forKey: .tangentPlane) ?? false
        projected = try c.decodeIfPresent(ProjectedZone.self, forKey: .projected)
        datums = try c.decodeIfPresent([DatumReference].self, forKey: .datums) ?? []
    }
}

public struct FeatureControlFrame: Hashable, Codable, Sendable {
    public var characteristic: GeometricCharacteristic
    public var rows: [ToleranceRow]
    public var attachment: SymbolAttachment
    /// Sheet millimetres (plan R4).
    public var offset: Vector2

    public init(
        characteristic: GeometricCharacteristic, rows: [ToleranceRow], attachment: SymbolAttachment,
        offset: Vector2 = Vector2(0, 0)
    ) {
        self.characteristic = characteristic
        self.rows = rows
        self.attachment = attachment
        self.offset = offset
    }

    public var isComposite: Bool { rows.count == 2 }
}
