import CreatorGeometry

/// A ray from `origin` along the unit `direction`.
struct Ray: Sendable {
    var origin: Vector3
    var direction: Vector3
    /// The smallest ray parameter that counts as a hit. It's 0 in perspective. Orthographic views also show what
    /// lies behind the nominal eye, so there it is −∞.
    var minimumT: Double

    func point(at t: Double) -> Vector3 { origin + direction * t }
}
