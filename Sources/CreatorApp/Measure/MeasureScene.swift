import CreatorGeometry
import CreatorKernel

/// What the resolver needs of the scene: the shown solids by index (as the Measure session's snapshot), which of them a pick may
/// land on, the section's pieces and the plane they were cut at.
struct MeasureScene {
    var solids: [Solid]
    /// Opaque, not a guide (meshes included).
    var pickable: [Bool]
    var parts: [SectionedPart]
    var plane: Plane?
}
