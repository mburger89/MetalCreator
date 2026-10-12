import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import Testing

/// Patterns spec §6 and §9 for a culled tree three deep, `{row;column;0}` (one placement per cell, the shape Face Pattern gives
/// Place): the instances Place makes are named by the whole path, a pick on one survives a cull of another, and a pick on a
/// culled one warns, naming its three-index path. The tree is a Grid Pattern's rows with every placement grafted into a branch
/// of its own, so none of this needs Face Pattern.
struct CellTreePickTests {
    /// 3 × 2 Ø5 holes 15 mm apart, grafted to `{row;column;0}`, a Cull Index, a Hole Pattern, an Edges by Tag and a Fillet.
    struct Fixture {
        var plate = PatternPlate(columns: 3, rows: 2, spacingX: 15, spacingY: 15)
        let cull: Node, holes: Node, rule: Node, fillet: Node

        init() {
            let layout = plate.h.add(GridPatternNode.self, ["countX": .integer(3), "countY": .integer(2),
                                                            "spacingX": .number(15), "spacingY": .number(15),
            ])
            let graft = plate.h.add(GraftNode.self)
            cull = plate.h.add(CullIndexNode.self)
            holes = plate.h.add(HolePatternNode.self, ["diameter": .number(5), "depth": .number(6)])
            plate.h.wire(layout, "placements", to: graft, "tree")
            plate.h.wire(graft, "tree", to: cull, "tree")
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            plate.h.wire(cull, "tree", to: holes, "placements")
            rule = plate.h.add(EdgesByTagNode.self)
            plate.h.wire(holes, "solid", to: rule, "solid")
            fillet = plate.h.add(FilletNode.self, ["radius": .number(0.5)])
            plate.h.wire(rule, "edges", to: fillet, "edges")
        }

        mutating func cull(_ text: String) { plate.h.set(cull, NodeSetting.cullIndices, .text(text)) }

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
            cull("")
            let solid = try onlySolid(try await plate.h.run([holes], kernel: kernel), holes)
            let edges = try paths.map { try #require(rim(of: $0, in: solid)).id }
            plate.h.set(rule, NodeSetting.picks, .edgePicks(solid.topology.picks(for: edges)))
        }

        func selected(_ report: EvaluationReport) throws -> (solid: Solid, edges: [EdgeInfo]) {
            let set = try #require(report.value(rule, "edges")?.edgeSets?.first)
            return (set.solid, set.edges.compactMap { set.solid.topology.edge($0) })
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

    static let every: Set<[Int]> = [[0, 0, 0], [0, 1, 0], [0, 2, 0], [1, 0, 0], [1, 1, 0], [1, 2, 0]]

    @Test func everyCellMakesAHoleAtItsThreeIndexPath() async throws {
        var f = Fixture()
        f.cull("")
        let report = try await f.plate.h.run([f.holes], kernel: OCCTKernel())
        #expect(try f.holePaths(report) == Self.every)
    }

    @Test(arguments: ["{0;1;0}", "{0;1}"])
    func aCulledCellLeavesTheOthersAtTheirPaths(_ text: String) async throws {
        var f = Fixture()
        f.cull(text)
        let report = try await f.plate.h.run([f.holes], kernel: OCCTKernel())
        #expect(try f.holePaths(report) == Self.every.subtracting([[0, 1, 0]]), "\(text)")
        #expect(report.isOK(f.holes), "a cull never warns")
    }

    @Test func aBareIndexOnCellsCullsNothingOrEverythingAsItsLastLevelHasOnlyZero() async throws {
        var f = Fixture()
        f.cull("1")
        let kept = try await f.plate.h.run([f.holes], kernel: OCCTKernel())
        #expect(try f.holePaths(kept) == Self.every)
        f.cull("0")
        let report = try await f.plate.h.run([f.holes], kernel: OCCTKernel())
        #expect(report.isOK(f.holes), "no holes is not an error")
        #expect(try onlySolid(report, f.holes).topology.faces.flatMap(\.tags).filter(\.node.isInstanceQualified).isEmpty)
    }

    @Test(arguments: ["{1;1;0}", "{1;1}", "{1}"])
    func aPickOnACulledCellWarnsNamingItsThreeIndexPathAndSelectsNothing(_ text: String) async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([[1, 1, 0]], kernel: kernel)
        f.cull(text)
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instance {1;1;0} no longer exists, so the edge picked on it isn't selected.", "\(text)")
        #expect(try f.selected(report).edges.isEmpty, "never a neighbour's rim")
    }

    @Test(arguments: ["{0;0;0}", "{0;2}", "{0}", "{1;0}, {1;2}"])
    func aPickOnOneCellSurvivesACullOfAnother(_ text: String) async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([[1, 1, 0]], kernel: kernel)
        let before = try f.selected(try await f.plate.h.run([f.rule], kernel: kernel))
        f.cull(text)
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(report.isOK(f.rule) && report.isOK(f.fillet), "after culling \(text): \(String(describing: report.state(f.rule)))")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { f.touches([1, 1, 0], $0, in: solid) }, "still the rim of {1;1;0}")
        #expect(before.edges.count == 1)
    }
}
