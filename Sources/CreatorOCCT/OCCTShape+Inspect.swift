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

/// Prepares process-wide OCCT state (idempotent). Called by `OCCTKernel.init`.
func occtInitialize() {
    occt_initialize()
}
