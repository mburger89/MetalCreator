/// What a hole callout says about a hole (plan R12), in millimetres and radians.
public struct HoleShape: Hashable, Sendable {
    public struct Counterbore: Hashable, Sendable {
        public var diameter: Double
        public var depth: Double

        public init(diameter: Double, depth: Double) {
            self.diameter = diameter
            self.depth = depth
        }
    }

    public struct Countersink: Hashable, Sendable {
        public var diameter: Double
        public var angle: Double

        public init(diameter: Double, angle: Double) {
            self.diameter = diameter
            self.angle = angle
        }
    }

    public var diameter: Double
    /// The drilled depth, or nil for a hole through the part.
    public var depth: Double?
    public var counterbore: Counterbore?
    public var countersink: Countersink?

    public init(diameter: Double, depth: Double? = nil, counterbore: Counterbore? = nil, countersink: Countersink? = nil) {
        self.diameter = diameter
        self.depth = depth
        self.counterbore = counterbore
        self.countersink = countersink
    }

    /// Whether every size the shape holds is a finite number.
    var isFinite: Bool {
        diameter.isFinite && (depth?.isFinite ?? true) && (counterbore.map { $0.diameter.isFinite && $0.depth.isFinite } ?? true)
            && (countersink.map { $0.diameter.isFinite && $0.angle.isFinite } ?? true)
    }
}
