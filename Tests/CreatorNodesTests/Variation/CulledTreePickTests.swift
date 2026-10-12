import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import Testing

/// Patterns spec §6 and §9 for culling a tree of placements: an instance is named by its tree path, culling keeps the path of
/// every survivor, a pick on one survives a cull of another and does not move to a neighbour, and a pick on a culled instance
/// warns, naming its path, and selects nothing.
struct CulledTreePickTests {
    /// Where the cull sits: after a Grid Pattern's tree of placements, or on the Grid Points before Points to Placements.
    enum Stage: CaseIterable, Sendable {
        case afterLayout, beforePlacements
    }

    /// 3 × 2 Ø5 holes 15 mm apart in rows of 3 (`{row;column}`), a Cull Index on them, a Hole Pattern, an Edges by Tag on the
    /// result and a Fillet on its edges.
    struct Fixture {
        var plate: PatternPlate
        let cull: Node, holes: Node, rule: Node, fillet: Node

        init(_ stage: Stage = .afterLayout, culler: any NodeDefinition.Type = CullIndexNode.self) {
            plate = PatternPlate(columns: 3, rows: 2, spacingX: 15, spacingY: 15)
            cull = plate.h.add(culler)
            holes = plate.h.add(HolePatternNode.self, ["diameter": .number(5), "depth": .number(6)])
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            switch stage {
            case .afterLayout:
                let layout = plate.h.add(GridPatternNode.self, ["countX": .integer(3), "countY": .integer(2),
                                                                "spacingX": .number(15), "spacingY": .number(15),
                ])
                plate.h.wire(layout, "placements", to: cull, "tree")
                plate.h.wire(cull, "tree", to: holes, "placements")
            case .beforePlacements:
                let rows = plate.h.add(PartitionNode.self, ["size": .integer(3)])
                let placed = plate.h.add(PointsToPlacementsNode.self)
                plate.h.wire(plate.grid, "points", to: rows, "tree")
                plate.h.wire(rows, "tree", to: cull, "tree")
                plate.h.wire(cull, "tree", to: placed, "points")
                plate.h.wire(placed, "placements", to: holes, "placements")
            }
            rule = plate.h.add(EdgesByTagNode.self)
            plate.h.wire(holes, "solid", to: rule, "solid")
            fillet = plate.h.add(FilletNode.self, ["radius": .number(0.5)])
            plate.h.wire(rule, "edges", to: fillet, "edges")
        }

        /// Culls what `text` names (Cull Index's setting) or keeps what it says (Cull Pattern's).
        mutating func cull(_ text: String) {
            let setting = plate.h.nodes[cull.id]?.typeID == CullPatternNode.typeID ? NodeSetting.cullPattern : NodeSetting.cullIndices
            plate.h.set(cull, setting, .text(text))
        }

        /// The tag of the bore of the hole at `path`, the way Hole Pattern names it.
        func bore(_ path: [Int]) -> TopoTag {
            TopoTag(node: NodeID.instanceScoped([holes.id, holes.id]), item: InstancePath.item(for: path) ?? -1, role: .side(segment: 1))
        }

        /// The rim of the hole at `path` on the plate's top.
        func rim(of path: [Int], in solid: Solid) -> EdgeInfo? {
            let top = TopoTag(node: plate.plate.id, item: 0, role: .endCap)
            return solid.topology.edges.first { edge in
                guard edge.kind == .circle, !edge.isSeam, edge.faces.count == 2 else { return false }
                let sides = edge.faces.compactMap { solid.topology.face($0) }
                return sides.contains { $0.tags.contains(bore(path)) } && sides.contains { $0.tags.contains(top) }
            }
        }

        /// Picks the rims of the holes at `paths` on the rule, from a run with nothing culled.
        mutating func pick(_ paths: [[Int]], kernel: any Kernel) async throws {
            let culled = plate.h.nodes[cull.id]?.typeID == CullPatternNode.typeID
            cull(culled ? "1" : "")
            let solid = try onlySolid(try await plate.h.run([holes], kernel: kernel), holes)
            let edges = try paths.map { try #require(rim(of: $0, in: solid)).id }
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

        func touches(_ path: [Int], _ edge: EdgeInfo, in solid: Solid) -> Bool {
            edge.faces.compactMap { solid.topology.face($0) }.contains { $0.tags.contains(bore(path)) }
        }

        /// The paths of the holes the Hole Pattern made.
        func holePaths(_ report: EvaluationReport) throws -> Set<[Int]> {
            let solid = try onlySolid(report, holes)
            let items = solid.topology.faces.flatMap(\.tags).filter(\.node.isInstanceQualified).map(\.item)
            return Set(items.compactMap { InstancePath.indices(ofItem: $0) })
        }
    }

    @Test(arguments: ["0", "2", "{0;0}", "{1;0}", "{0}", "0, {1;2}"], Stage.allCases)
    func aPickOnOneInstanceSurvivesACullOfAnother(_ cull: String, _ stage: Stage) async throws {
        let kernel = OCCTKernel()
        var f = Fixture(stage)
        try await f.pick([[1, 1]], kernel: kernel)
        let before = try f.selected(try await f.plate.h.run([f.rule], kernel: kernel))
        f.cull(cull)
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(report.isOK(f.rule) && report.isOK(f.fillet), "after culling \(cull) \(stage): \(String(describing: report.state(f.rule)))")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { f.touches([1, 1], $0, in: solid) }, "still the rim of {1;1}")
        #expect(isClose(try f.center(of: try #require(edges.first)), try f.center(of: try #require(before.edges.first))),
                "the same physical hole: a cull never moves a pick to a neighbour")
    }

    @Test(arguments: Stage.allCases)
    func aCullLeavesTheSurvivorsAtTheirTreePaths(_ stage: Stage) async throws {
        let kernel = OCCTKernel()
        var f = Fixture(stage)
        f.cull("1")
        let report = try await f.plate.h.run([f.holes], kernel: kernel)
        #expect(try f.holePaths(report) == [[0, 0], [0, 2], [1, 0], [1, 2]], "{0;2} and {1;2}, not {0;1} and {1;1}: \(stage)")
        #expect(report.isOK(f.holes), "a cull never warns")
    }

    @Test(arguments: ["{1;1}", "1", "{1}"], Stage.allCases)
    func aPickOnACulledPathWarnsNamingItAndSelectsNothing(_ cull: String, _ stage: Stage) async throws {
        let kernel = OCCTKernel()
        var f = Fixture(stage)
        try await f.pick([[1, 1]], kernel: kernel)
        f.cull(cull)
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instance {1;1} no longer exists, so the edge picked on it isn't selected.", "\(cull) \(stage)")
        #expect(try f.selected(report).edges.isEmpty, "never a neighbour's rim")
    }

    @Test func aWholeBranchCulledNamesEveryPickOnIt() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([[0, 0], [0, 2], [1, 1]], kernel: kernel)
        f.cull("{0}")
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instances {0;0} and {0;2} no longer exist, so the edges picked on them aren't selected.")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { f.touches([1, 1], $0, in: solid) })
    }

    @Test func aPickComesBackWhenTheCullIsUndone() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([[1, 1]], kernel: kernel)
        f.cull("1")
        _ = try await f.plate.h.run([f.rule], kernel: kernel)
        f.cull("")
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.isOK(f.rule))
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { f.touches([1, 1], $0, in: solid) })
    }

    @Test func aCullPatternKeepsTheTreePathsOfTheItemsItKeeps() async throws {
        let kernel = OCCTKernel()
        var f = Fixture(.afterLayout, culler: CullPatternNode.self)
        try await f.pick([[1, 2], [1, 1]], kernel: kernel)
        f.cull("1 0")
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(try f.holePaths(try await f.plate.h.run([f.holes], kernel: kernel)) == [[0, 0], [0, 2], [1, 0], [1, 2]])
        #expect(report.warning(f.rule) == "Instance {1;1} no longer exists, so the edge picked on it isn't selected.")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { f.touches([1, 2], $0, in: solid) }, "{1;2} keeps its place")
    }

    @Test func aPickSurvivesACullAndARowLengthChangeTogether() async throws {
        let kernel = OCCTKernel()
        var f = Fixture(.beforePlacements)
        try await f.pick([[1, 1]], kernel: kernel)
        f.cull("0")
        f.plate.h.set(f.plate.grid, "spacingX", .number(18))
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(report.isOK(f.rule) && report.isOK(f.fillet))
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { f.touches([1, 1], $0, in: solid) })
    }
}
