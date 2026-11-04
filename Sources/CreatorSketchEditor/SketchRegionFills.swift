import CreatorGeometry
import CreatorSketch
import CreatorViewport

/// The overlay's region fills: one `OverlayFill` per closed region of the sketch (`SketchRegions.find`, so construction
/// geometry and suspended projections are left out and holes stay empty), in the plane's world space.
enum SketchRegionFills {
    static func fills(of sketch: Sketch, on plane: Plane) -> [OverlayFill] {
        found(in: sketch, on: plane).fills
    }

    /// The fills and the region finder's warnings (a spline that crosses itself), from one `SketchRegions.find`.
    static func found(in sketch: Sketch, on plane: Plane) -> (fills: [OverlayFill], warnings: [String]) {
        let result = SketchRegions.find(in: sketch)
        let fills = result.regions.compactMap { region -> OverlayFill? in
            let triangles = RegionTriangulator.triangles(of: region)
            return triangles.isEmpty ? nil : OverlayFill(vertices: triangles.map(plane.point), tint: .region)
        }
        return (fills, result.selfCrossingWarnings)
    }
}
