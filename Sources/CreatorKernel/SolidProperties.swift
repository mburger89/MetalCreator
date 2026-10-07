import CreatorGeometry

/// Mass properties of a solid, in millimetres (volume mm³, area mm²).
public struct SolidProperties: Hashable, Sendable {
    public var volume: Double
    public var surfaceArea: Double
    public var centroid: Vector3

    public init(volume: Double, surfaceArea: Double, centroid: Vector3) {
        self.volume = volume
        self.surfaceArea = surfaceArea
        self.centroid = centroid
    }
}
