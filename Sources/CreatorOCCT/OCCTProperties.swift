import CreatorGeometry

/// Mass properties and tight bounds read from an OCCT shape.
struct OCCTProperties: Sendable {
    var volume: Double
    var surfaceArea: Double
    var centroid: Vector3
    var bounds: BoundingBox
}
