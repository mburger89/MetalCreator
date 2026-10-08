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
            regions.append(SketchRegion(outer: face.loop.map(\.segment), holes: holes.map { $0.map(\.segment) },
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
        let areaTolerance = 1e-9 * max(1, abs(a.area), abs(b.area))
        if abs(a.area - b.area) > areaTolerance { return a.area > b.area }
        if abs(a.centroid.x - b.centroid.x) > 1e-9 { return a.centroid.x < b.centroid.x }
        return a.centroid.y < b.centroid.y
    }
}
