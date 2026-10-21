import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// The Face mapping of the lattice nodes (implicit spec §3.5): the `face` setting is a pick on the solid the region came from, found
/// by its topology tags among the solids the region was baked from; the face is measured once (`FaceChartCache`) and the lattice's
/// cells follow it. A pick that none of those solids has is the node's error.
enum LatticeFaceMapping {
    /// Names the inspector's button, which Task 10 adds: the words are final here, so Task 10 does not change them.
    static let nothingPicked = "Pick a face for the mapping: use “Pick Face in View…” on the part the region was made from."
    static let unreadablePick = "This lattice's picked face can't be read. Pick the face again."
    static let noSource = "Face mapping needs a region made from a solid with To Implicit, to know which solid the face is on."
    static let movedSource = "The region was moved after it left its solid, so the picked face is no longer where the solid has it. "
        + "Map the lattice before moving the region."
    static let wrongSolid = "The picked face isn't on the solid this region came from. Pick it again on that solid."

    /// The face map for a lattice filling `region`.
    /// - Parameter cells: the lattice's cells, whose edges along the face's two directions a periodic turn is rounded to; `nil` for
    ///   a lattice without cells (Voronoi).
    static func make(context: EvalContext, region: ImplicitSolid, cells: LatticeCells?, kernel: any Kernel) async throws
        -> (map: FaceMap, warnings: [String]) {
        let pick = try self.pick(context)
        let (blocks, resolution) = try resolve(pick, in: region)
        guard let face = resolution.faces.first else { throw NodeError.invalidValue(wrongSolid) }
        let chart = try await FaceChartCache.shared.chart(for: blocks, face: face.id, kernel: kernel)
        let edges = cells.map { (first: $0.nominalSize * $0.stretch.x, second: $0.nominalSize * $0.stretch.y) }
        let map = FaceMap(chart: chart, firstCell: edges?.first, secondCell: edges?.second)
        return (map, pickWarnings(pick, resolution) + chartWarnings(chart, region: region, cells: cells))
    }

    /// The `face` setting.
    private static func pick(_ context: EvalContext) throws -> FacePick {
        switch context.node.inputValues[NodeSetting.face] {
        case nil: throw NodeError.invalidValue(nothingPicked)
        case .facePick(let stored)?: return stored
        case .some: throw NodeError.invalidValue(unreadablePick)
        }
    }

    /// The solid the region was baked from that has the picked face, and what the pick names on it.
    private static func resolve(_ pick: FacePick, in region: ImplicitSolid) throws -> (DistanceBlocks, FaceResolution) {
        let sources = region.sourceBlocks
        guard !sources.isEmpty else { throw NodeError.invalidValue(region.holdsMovedSource ? movedSource : noSource) }
        if let found = found(pick, among: sources) { return found }
        // The same words the other face nodes use for a copy of a pattern that is gone.
        if let gone = sources.lazy.compactMap({ $0.source?.solid.topology.vanishedInstances(in: pick.tags).first }).first {
            throw NodeError.invalidValue("Instance \(InstancePath.text(gone)) no longer exists, so the picked face isn't there any "
                + "more. Pick the face again.")
        }
        throw NodeError.invalidValue(wrongSolid)
    }

    /// What a pick earns: several matches, a face a union merged, a face with no stable name (as Plane from Face's).
    private static func pickWarnings(_ pick: FacePick, _ resolution: FaceResolution) -> [String] {
        var warnings: [String] = []
        if resolution.isAmbiguous {
            warnings.append("The picked face was merged with a face from another part of the model that has since changed, so it isn't "
                + "clear which part was picked. The mapping follows the closest one; pick the face again to settle it.")
        } else if resolution.faces.count > 1 {
            warnings.append("The pick matches \(resolution.faces.count.display) faces; the mapping follows the first.")
        }
        if pick.touchesUnnamedFace {
            warnings.append("The picked face has no stable name, so the mapping may move to a different face when the model changes. "
                + "Pick it again after the change.")
        }
        return warnings
    }

    /// What the chart earns: a region past the part it was measured over, and a grid too coarse for the cells.
    private static func chartWarnings(_ chart: FaceChart, region: ImplicitSolid, cells: LatticeCells?) -> [String] {
        var warnings: [String] = []
        let (box, covered) = (region.bounds, chart.bounds)
        if box.min.x < covered.min.x || box.min.y < covered.min.y || box.min.z < covered.min.z || box.max.x > covered.max.x
            || box.max.y > covered.max.y || box.max.z > covered.max.z {
            warnings.append("The region reaches past the part the face is on; the mapping is held at the part's edge there.")
        }
        if let smallest = cells.map({ $0.smallest * $0.smallestStretch }), chart.spacing > smallest / 3 {
            let spacing = chart.spacing.millimetreText(locale: .messages)
            warnings.append("The part is big for the face mapping, which is measured every \(spacing) mm, so cells may look rough.")
        }
        return warnings
    }

    /// The baked solid whose topology the pick names, and what it names there.
    private static func found(_ pick: FacePick, among sources: [DistanceBlocks]) -> (DistanceBlocks, FaceResolution)? {
        for blocks in sources {
            guard let solid = blocks.source?.solid else { continue }
            let resolution = solid.topology.resolution(of: pick)
            if !resolution.faces.isEmpty { return (blocks, resolution) }
        }
        return nil
    }
}
