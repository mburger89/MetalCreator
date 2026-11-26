import CreatorGeometry

public enum SurfaceProcess: String, Hashable, Codable, Sendable {
    case any, removalRequired, removalProhibited
}

public enum RoughnessParameter: String, Hashable, Codable, Sendable {
    case ra, rz

    public var title: String { self == .ra ? "Ra" : "Rz" }
}

public enum SurfaceLay: String, Hashable, Codable, Sendable, CaseIterable {
    case parallel, perpendicular, crossed, multidirectional, circular, radial, particulate
}

/// What a surface asks for; `value` is in micrometres.
public struct SurfaceRequirement: Hashable, Codable, Sendable {
    public var process: SurfaceProcess
    public var parameter: RoughnessParameter?
    public var value: Double?

    public init(process: SurfaceProcess = .any, parameter: RoughnessParameter? = nil, value: Double? = nil) {
        self.process = process
        self.parameter = parameter
        self.value = value
    }

    private enum CodingKeys: String, CodingKey { case process, parameter, value }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        process = try c.decodeIfPresent(SurfaceProcess.self, forKey: .process) ?? .any
        parameter = try c.decodeIfPresent(RoughnessParameter.self, forKey: .parameter)
        value = try c.decodeIfPresent(Double.self, forKey: .value)
    }
}

/// A surface texture symbol (plan R1, R6). `offset` nil: it stands on its line.
public struct SurfaceTexture: Hashable, Codable, Sendable {
    public var requirement: SurfaceRequirement
    public var lay: SurfaceLay?
    public var feature: LeaderEnd
    public var offset: Vector2?

    public init(requirement: SurfaceRequirement, lay: SurfaceLay? = nil, feature: LeaderEnd, offset: Vector2? = nil) {
        self.requirement = requirement
        self.lay = lay
        self.feature = feature
        self.offset = offset
    }

    private enum CodingKeys: String, CodingKey { case requirement, lay, feature, offset }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requirement = try c.decode(SurfaceRequirement.self, forKey: .requirement)
        lay = try c.decodeIfPresent(SurfaceLay.self, forKey: .lay)
        feature = try c.decode(LeaderEnd.self, forKey: .feature)
        offset = try c.decodeIfPresent(Vector2.self, forKey: .offset)
    }
}
