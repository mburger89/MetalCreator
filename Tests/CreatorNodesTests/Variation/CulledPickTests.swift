import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Testing

/// Patterns spec §6 and §9 for culling: a pick on an instance survives a cull of another instance, and a pick on a culled
/// instance warns, naming its path, and selects nothing. The placements are one flat list (Grid Points → Points to
/// Placements → Cull Index), so an instance's path is `{i}`, its index in the list; `CulledTreePickTests` does the same over
/// a tree of placements.
struct CulledPickTests {
    /// Which side of Points to Placements the cull is on. Both must number the survivors alike: a cull of the Grid Points
    /// is as natural as one of the placements.
    enum Stage: CaseIterable, Sendable {
        case afterPlacements, beforePlacements
    }

    /// 3 × 2 Ø5 holes 15 mm apart, a Cull Index on the points or the placements, an Edges by Tag on the result and a
    /// Fillet on its edges.
    struct Fixture {
        var plate: PatternPlate
        let cull: Node, holes: Node, rule: Node, fillet: Node

        init(_ stage: Stage = .afterPlacements) {
            plate = PatternPlate(columns: 3, rows: 2, spacingX: 15, spacingY: 15)
            cull = plate.h.add(CullIndexNode.self)
            holes = plate.h.add(HolePatternNode.self, ["diameter": .number(5), "depth": .number(6)])
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            switch stage {
            case .afterPlacements:
                plate.h.wire(plate.placements, "placements", to: cull, "tree")
                plate.h.wire(cull, "tree", to: holes, "placements")
            case .beforePlacements:
                // The plate's own Points to Placements is left unused: this one reads the culled points.
                let placed = plate.h.add(PointsToPlacementsNode.self)
                plate.h.wire(plate.grid, "points", to: cull, "tree")
                plate.h.wire(cull, "tree", to: placed, "points")
                plate.h.wire(placed, "placements", to: holes, "placements")
            }
            rule = plate.h.add(EdgesByTagNode.self)
            plate.h.wire(holes, "solid", to: rule, "solid")
            fillet = plate.h.add(FilletNode.self, ["radius": .number(0.5)])
            plate.h.wire(rule, "edges", to: fillet, "edges")
        }

        /// Culls what `text` names (`CullIndexNode`'s setting).
        mutating func cull(_ text: String) {
            plate.h.set(cull, NodeSetting.cullIndices, .text(text))
        }

        /// The tag of hole `index`'s bore, the way Hole Pattern names it.
        func bore(_ index: Int) -> TopoTag {
            TopoTag(node: NodeID.instanceScoped([holes.id, holes.id]), item: index, role: .side(segment: 1))
        }

        /// The rim of hole `index` on the plate's top: the circle between its bore and the plate's end cap.
        func rim(of index: Int, in solid: Solid) -> EdgeInfo? {
            let top = TopoTag(node: plate.plate.id, item: 0, role: .endCap)
            return solid.topology.edges.first { edge in
                guard edge.kind == .circle, !edge.isSeam, edge.faces.count == 2 else { return false }
                let sides = edge.faces.compactMap { solid.topology.face($0) }
                return sides.contains { $0.tags.contains(bore(index)) } && sides.contains { $0.tags.contains(top) }
            }
        }

        /// Picks the rims of the holes `indices` on the rule, from a run with nothing culled.
        mutating func pick(_ indices: [Int], kernel: any Kernel) async throws {
            cull("")
            let solid = try onlySolid(try await plate.h.run([holes], kernel: kernel), holes)
            let edges = try indices.map { try #require(rim(of: $0, in: solid)).id }
            plate.h.set(rule, NodeSetting.picks, .edgePicks(solid.topology.picks(for: edges)))
        }

        /// The edges the rule selects now.
        func selected(_ report: EvaluationReport) throws -> (solid: Solid, edges: [EdgeInfo]) {
            let set = try #require(report.value(rule, "edges")?.edgeSets?.first)
            return (set.solid, set.edges.compactMap { set.solid.topology.edge($0) })
        }

        func center(of edge: EdgeInfo) throws -> Vector3 {
            guard case .circle(let center, _, _, _, _)? = edge.curve else { throw NodeError.invalidValue("not a circle") }
            return center
        }
    }

    func touchesHole(_ index: Int, _ edge: EdgeInfo, in solid: Solid, _ f: Fixture) -> Bool {
        edge.faces.compactMap { solid.topology.face($0) }.contains { $0.tags.contains(f.bore(index)) }
    }

    #if canImport(CreatorOCCT)
    @Test(arguments: ["1", "0", "2, 3", "{3}", "5"], Stage.allCases)
    func aPickOnOneInstanceSurvivesACullOfAnother(_ cull: String, _ stage: Stage) async throws {
        let kernel = OCCTKernel()
        var f = Fixture(stage)
        try await f.pick([4], kernel: kernel)
        let before = try f.selected(try await f.plate.h.run([f.rule], kernel: kernel))
        f.cull(cull)
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(report.isOK(f.rule) && report.isOK(f.fillet), "after culling \(cull) \(stage): \(String(describing: report.state(f.rule)))")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { touchesHole(4, $0, in: solid, f) }, "still the rim of {4}")
        #expect(isClose(try f.center(of: try #require(edges.first)), try f.center(of: try #require(before.edges.first))),
                "the same physical hole: a cull never moves a pick to a neighbour")
    }

    @Test(arguments: Stage.allCases)
    func aCullLeavesTheSurvivorsAtTheirIndices(_ stage: Stage) async throws {
        let kernel = OCCTKernel()
        var f = Fixture(stage)
        f.cull("1, 2")
        let report = try await f.plate.h.run([f.holes], kernel: kernel)
        let solid = try onlySolid(report, f.holes)
        let items = Set(solid.topology.faces.flatMap(\.tags).filter(\.node.isInstanceQualified).map(\.item))
        #expect(items == [0, 3, 4, 5], "the holes are {0}, {3}, {4} and {5}, not {0} to {3}: \(stage)")
        #expect(report.isOK(f.holes), "a cull never warns")
    }

    @Test(arguments: Stage.allCases)
    func aPickOnACulledInstanceWarnsNamingItAndSelectsNothing(_ stage: Stage) async throws {
        let kernel = OCCTKernel()
        var f = Fixture(stage)
        try await f.pick([1], kernel: kernel)
        f.cull("1")
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instance {1} no longer exists, so the edge picked on it isn't selected.")
        #expect(try f.selected(report).edges.isEmpty, "never a neighbour's rim")
    }

    @Test func onlyTheCulledPicksAreDroppedWhenAnotherStillHolds() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([1, 4], kernel: kernel)
        f.cull("1")
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instance {1} no longer exists, so the edge picked on it isn't selected.")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { touchesHole(4, $0, in: solid, f) })
    }

    @Test func aPickComesBackWhenTheCullIsUndone() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([1], kernel: kernel)
        f.cull("1")
        _ = try await f.plate.h.run([f.rule], kernel: kernel)
        f.cull("")
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.isOK(f.rule))
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { touchesHole(1, $0, in: solid, f) })
    }

    @Test func aPickSurvivesACullAndACountChangeTogether() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([4], kernel: kernel)
        f.cull("0")
        f.plate.h.set(f.plate.grid, "spacingX", .number(18))
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(report.isOK(f.rule) && report.isOK(f.fillet))
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { touchesHole(4, $0, in: solid, f) })
    }
    #endif
}
