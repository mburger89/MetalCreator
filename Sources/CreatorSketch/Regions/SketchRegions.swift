import CreatorGeometry

/// Finds the closed regions of a solved sketch (spec §5).
public enum SketchRegions {
    /// The regions bounded by the sketch's non-construction curves (projected edges included),
    /// at their current positions. Faces nest even–odd: a face inside another is its hole, and
    /// a face inside a hole is a region again.
    public static func find(in sketch: Sketch) -> SketchRegionResult {
        let curves = sketch.curves(includingConstruction: false)
        let graph = RegionGraph(curves: curves)
        let labels = graph.componentLabels()
        var faces: [Face] = []
        var outlines: [Int: [LoopSegment]] = [:]
        var outlineAreas: [Int: Double] = [:]
        for cycle in graph.faceCycles() {
            let loop = graph.loop(cycle)
            let area = LoopMeasure.area(loop)
            let component = labels[cycle[0].origin(graph)]
            if area > 0 {
                faces.append(Face(loop: loop, area: area, component: component))
            } else if area < outlineAreas[component, default: .infinity] {
                outlines[component] = loop
                outlineAreas[component] = area
            }
        }
        // Each component's depth is the number of other components' faces around it; its parent
        // is the smallest of those faces.
        var depth: [Int: Int] = [:]
        var parent: [Int: Int] = [:]
        for (component, outline) in outlines {
            let probe = outline[0].midpoint
            let around = faces.indices.filter { faces[$0].component != component && LoopMeasure.contains(faces[$0].loop, probe) }
            depth[component] = around.count
            parent[component] = around.min { faces[$0].area < faces[$1].area }
        }
        var regions: [SketchRegion] = []
        for (index, face) in faces.enumerated() where depth[face.component, default: 0] % 2 == 0 {
            let holes = outlines.keys.sorted().filter { parent[$0] == index }.compactMap { outlines[$0] }
            let loops = [face.loop] + holes
            let area = loops.reduce(0) { $0 + LoopMeasure.area($1) }
            let moments = loops.reduce(Vector2.zero) { $0 + LoopMeasure.moments($1) }
            let sortedHoles = holes.map { ($0, LoopMeasure.area($0), LoopMeasure.moments($0)) }
                .map { loop, area, moments in (loop: loop, area: abs(area), centroid: moments * (1 / area)) }
                .sorted { isOrderedBefore(area: $0.area, $0.centroid, before: $1.area, $1.centroid) }
            regions.append(SketchRegion(outer: emitted(face.loop), holes: sortedHoles.map { emitted($0.loop) },
                                        area: area, centroid: moments * (1 / area)))
        }
        regions.sort(by: isOrderedBefore)
        let used = graph.usedSources
        let open = curves.indices.filter { !used.contains($0) }.map { curves[$0].source }
        return SketchRegionResult(regions: regions, openCurves: open)
    }

    struct Face {
        var loop: [LoopSegment]
        var area: Double
        var component: Int
    }

    /// Area descending, then centroid x, then y, each compared with a tolerance so rounding
    /// noise can't reorder equal regions.
    static func isOrderedBefore(_ a: SketchRegion, _ b: SketchRegion) -> Bool {
        isOrderedBefore(area: a.area, a.centroid, before: b.area, b.centroid)
    }

    /// The region order for any area and centroid: also orders a region's holes (spec §5 step 5).
    static func isOrderedBefore(area a: Double, _ aCentroid: Vector2, before b: Double, _ bCentroid: Vector2) -> Bool {
        let areaTolerance = 1e-9 * max(1, abs(a), abs(b))
        if abs(a - b) > areaTolerance { return a > b }
        if abs(aCentroid.x - bCentroid.x) > pointTolerance { return aCentroid.x < bCentroid.x }
        return aCentroid.y < bCentroid.y
    }

    /// Points closer than this (mm) on an axis compare equal on it.
    static let pointTolerance = 1e-9

    /// A walked loop as it is emitted (spec §5 step 5): counter-clockwise, so a loop the face
    /// walk ran clockwise (a hole's outline) is reversed with each arc turned into its
    /// counter-clockwise form, then rotated to start at the segment whose start point is
    /// lexicographically smallest (x, then y). Hole loop indices and segment indices name walls
    /// (`TopoRole.side(loop:segment:)`), so neither may depend on where the walk began.
    ///
    /// An arc a counter-clockwise loop runs along clockwise (a notch cut into an outline) keeps
    /// its traversal sense, stored with `end < start`, so the loop stays continuous; the shim
    /// does not build such arcs yet (S4 handoff).
    static func emitted(_ loop: [LoopSegment]) -> [Segment2D] {
        let counterClockwise = LoopMeasure.area(loop) < 0 ? loop.reversed().map(\.reversed) : loop
        guard var first = counterClockwise.indices.first else { return [] }
        for index in counterClockwise.indices.dropFirst()
        where precedes(counterClockwise[index].start, counterClockwise[first].start) {
            first = index
        }
        return (counterClockwise[first...] + counterClockwise[..<first]).map(\.segment)
    }

    /// Lexicographic order on points, x then y, with `pointTolerance`.
    static func precedes(_ a: Vector2, _ b: Vector2) -> Bool {
        if abs(a.x - b.x) > pointTolerance { return a.x < b.x }
        return abs(a.y - b.y) > pointTolerance && a.y < b.y
    }
}
