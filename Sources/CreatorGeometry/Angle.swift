/// An angle stored in radians.
public struct Angle: Hashable, Sendable, Codable, Comparable {
    public var radians: Double

    public init(radians: Double) {
        self.radians = radians
    }

    public static func degrees(_ degrees: Double) -> Angle { Angle(radians: degrees * .pi / 180) }

    public var degrees: Double { radians * 180 / .pi }

    public static func < (lhs: Angle, rhs: Angle) -> Bool { lhs.radians < rhs.radians }
}
