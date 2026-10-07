import COCCT
import CreatorGeometry

extension OCCTShape {
    func properties() throws(OCCTError) -> OCCTProperties {
        var raw = occt_properties()
        try Self.check { status in occt_read_properties(self.raw, &raw, status) }
        return OCCTProperties(
            volume: raw.volume,
            surfaceArea: raw.area,
            centroid: OCCTRawTopology.vector(raw.centroid),
            bounds: BoundingBox(min: OCCTRawTopology.vector(raw.min), max: OCCTRawTopology.vector(raw.max))
        )
    }
}

extension OCCTShape {
    /// Tight axis-aligned bounds. Cheaper than `properties()`: no volume or area integration.
    func bounds() throws(OCCTError) -> BoundingBox {
        var min = [0.0, 0.0, 0.0]
        var max = [0.0, 0.0, 0.0]
        try Self.check { status in occt_read_bounds(self.raw, &min, &max, status) }
        return BoundingBox(min: Vector3(min[0], min[1], min[2]), max: Vector3(max[0], max[1], max[2]))
    }
}

/// Prepares process-wide OCCT state (idempotent). Called by `OCCTKernel.init`.
func occtInitialize() {
    occt_initialize()
}
