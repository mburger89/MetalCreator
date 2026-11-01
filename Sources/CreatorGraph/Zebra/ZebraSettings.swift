import CreatorGeometry

/// Which way the zebra's stripes run on the part.
public enum ZebraDirection: String, Codable, Sendable { case horizontal, vertical }

/// A camera's frame, kept so the stripes stay put while the camera moves (Lock).
public struct ZebraFrame: Equatable, Sendable, Codable {
    public var right: Vector3
    public var up: Vector3
    public var toEye: Vector3

    public init(right: Vector3, up: Vector3, toEye: Vector3) {
        self.right = right
        self.up = up
        self.toEye = toEye
    }

    public var isFinite: Bool { right.isFinite && up.isFinite && toEye.isFinite }
}

/// The zebra stripes view's settings, saved with the document's view state (never in its content: changing them is no
/// edit and has no undo step, like the camera and the section).
public struct ZebraSettings: Equatable, Sendable, Codable {
    public static let stripeRange = 4...40
    public static let blackShareRange = 0.2...0.8

    public var isOn: Bool
    public var direction: ZebraDirection
    public var stripes: Int { didSet { stripes = Self.clamped(stripes) } }
    public var blackShare: Double { didSet { blackShare = Self.clamped(blackShare) } }
    /// The camera frame the stripes are fixed to; `nil` means Lock is off and they follow the camera.
    public var lock: ZebraFrame?

    public init(isOn: Bool = false, direction: ZebraDirection = .horizontal, stripes: Int = 12,
                blackShare: Double = 0.5, lock: ZebraFrame? = nil) {
        self.isOn = isOn
        self.direction = direction
        self.stripes = Self.clamped(stripes)
        self.blackShare = Self.clamped(blackShare)
        self.lock = lock
    }

    private enum CodingKeys: String, CodingKey { case isOn, direction, stripes, blackShare, lock }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(isOn: try container.decodeIfPresent(Bool.self, forKey: .isOn) ?? false,
                  direction: try container.decodeIfPresent(ZebraDirection.self, forKey: .direction) ?? .horizontal,
                  stripes: try container.decodeIfPresent(Int.self, forKey: .stripes) ?? 12,
                  blackShare: try container.decodeIfPresent(Double.self, forKey: .blackShare) ?? 0.5,
                  lock: try container.decodeIfPresent(ZebraFrame.self, forKey: .lock))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isOn, forKey: .isOn)
        try container.encode(direction, forKey: .direction)
        try container.encode(stripes, forKey: .stripes)
        try container.encode(blackShare, forKey: .blackShare)
        try container.encodeIfPresent(lock, forKey: .lock)
    }

    private static func clamped(_ count: Int) -> Int { min(max(count, stripeRange.lowerBound), stripeRange.upperBound) }

    private static func clamped(_ share: Double) -> Double {
        guard share.isFinite else { return 0.5 }
        return min(max(share, blackShareRange.lowerBound), blackShareRange.upperBound)
    }
}
