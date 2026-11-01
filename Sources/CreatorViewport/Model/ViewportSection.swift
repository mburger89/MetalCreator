import CreatorGeometry

/// The section's cut face (section spec part B): for each capped part a triangulated cap lying on the section plane and the
/// outlines of its boundary. The host makes one and the viewport draws it right after the opaque solids, hatched, and the outlines
/// after the edges. It is no part of the scene: it never picks (a click on it picks nothing), frames or widens `sceneBounds`.
///
/// A section is equal to another, and hashes the same, when their `generation`s are: the host bumps `generation` each time it
/// changes the caps, so neither `ViewportModel` nor the render key ever compares or hashes the geometry.
public struct ViewportSection: Sendable, Equatable, Hashable {
    /// One part's cut face.
    public struct Cap: Sendable {
        /// The cap's vertices, on the section plane.
        public var positions: [Vector3]
        /// Three indices into `positions` per triangle.
        public var triangles: [UInt32]
        /// Polylines drawn in the section edge colour; a closed loop repeats its first point at the end.
        public var outlines: [[Vector3]]
        /// The hatch direction in the plane (radians from `ViewportSection.plane`'s x axis).
        public var hatchAngle: Double

        public init(positions: [Vector3], triangles: [UInt32], outlines: [[Vector3]], hatchAngle: Double) {
            self.positions = positions
            self.triangles = triangles
            self.outlines = outlines
            self.hatchAngle = hatchAngle
        }
    }

    public var caps: [Cap]
    /// The plane the caps lie on; its `xAxis` and `yAxis` are the hatch's axes.
    public var plane: Plane
    public var generation: Int

    /// The distance between hatch lines, in points.
    public static let hatchSpacingPoints = 8.0
    /// A hatch line's width, in points.
    public static let hatchLinePoints = 1.25

    public init(caps: [Cap], plane: Plane, generation: Int) {
        self.caps = caps
        self.plane = plane
        self.generation = generation
    }

    /// The hatch angle of the cap that is `index`-th among the capped items: 45°, 135°, 15°, 105°, 75°, 165°, then repeating.
    public static func hatchAngle(forCap index: Int) -> Double {
        let degrees = [45.0, 135, 15, 105, 75, 165]
        return degrees[((index % degrees.count) + degrees.count) % degrees.count] * .pi / 180
    }

    public static func == (lhs: ViewportSection, rhs: ViewportSection) -> Bool { lhs.generation == rhs.generation }

    public func hash(into hasher: inout Hasher) { hasher.combine(generation) }
}
