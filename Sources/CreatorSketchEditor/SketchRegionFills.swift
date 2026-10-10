import CreatorGeometry
import CreatorSketch
import CreatorViewport

/// The overlay's region fills: one `OverlayFill` per closed region of the sketch (`SketchRegions.find`, so construction
/// geometry and suspended projections are left out and holes stay empty), in the plane's world space.
enum SketchRegionFills {
    static func fills(of sketch: Sketch, on plane: Plane) -> [OverlayFill] {
        SketchRegions.find(in: sketch).regions.compactMap { region in
            let triangles = RegionTriangulator.triangles(of: region)
            return triangles.isEmpty ? nil : OverlayFill(vertices: triangles.map(plane.point), tint: .region)
        }
    }
}
