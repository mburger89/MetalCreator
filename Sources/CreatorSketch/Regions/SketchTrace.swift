/// Which sketch entity made each segment of a Sketch node's profiles: evaluation output for tools that
/// map a profile edge back to the drawing (dimensions spec §3.5). Never saved.
public struct SketchTrace: Hashable, Sendable {
    /// The sketch as evaluated: projections resolved, wired values applied, solution remembered.
    public var sketch: Sketch
    /// Profile item → loop → segment: `SketchRegion.sources`, in region order.
    public var regionSources: [[[SketchEntityID]]]

    public init(sketch: Sketch, regionSources: [[[SketchEntityID]]]) {
        self.sketch = sketch
        self.regionSources = regionSources
    }

    /// The entity behind one profile segment; nil when any index is out of range.
    public func entity(item: Int, loop: Int, segment: Int) -> SketchEntityID? {
        guard regionSources.indices.contains(item), regionSources[item].indices.contains(loop),
              regionSources[item][loop].indices.contains(segment) else { return nil }
        return regionSources[item][loop][segment]
    }
}
