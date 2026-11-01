import CreatorGeometry
import CreatorKernel

/// What the resolver needs of the scene: the shown solids by index (as the Measure session's snapshot), which of them a pick may
/// land on, the section's pieces and the plane they were cut at.
struct MeasureScene {
    var solids: [Solid]
    /// Opaque, not a guide (meshes included).
    var pickable: [Bool]
    var parts: [SectionedPart] { didSet { sectionBounds = MeasureSectionPick.bounds(of: parts) } }
    /// The world bounds of each part's section pieces, made with `parts` (hover's pre-check).
    private(set) var sectionBounds: [[MeasureSectionPick.Box]]
    var plane: Plane?

    init(solids: [Solid], pickable: [Bool], parts: [SectionedPart], plane: Plane?) {
        (self.solids, self.pickable, self.parts, self.plane) = (solids, pickable, parts, plane)
        sectionBounds = MeasureSectionPick.bounds(of: parts)
    }
}
