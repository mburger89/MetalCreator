import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import Testing

/// Patterns spec §6 and §9 through Cull by Field: a pick on one instance survives a field cull of another, and a pick on a
/// culled instance warns, naming its path, and selects nothing (the existing rule, as for Cull Index). A 3 × 2 plate of Ø5
/// holes 15 mm apart: hole {1} is at (0, −7.5). The field is the distance from a centre ÷ 15, culling what is below a
/// half, so a centre on a hole culls that hole alone and a centre far away culls nothing.
struct CulledByFieldPickTests {
    struct Fixture {
        var plate = PatternPlate(columns: 3, rows: 2, spacingX: 15, spacingY: 15)
        let centre: Node, holes: Node, rule: Node, fillet: Node

        init() {
            centre = plate.h.add(VectorNode.self, ["x": .number(1000), "y": .number(1000)])
            let field = plate.h.add(RadialGradientNode.self, ["radius": .number(15)])
            let cull = plate.h.add(CullByFieldNode.self, ["level": .number(0.5), "keep": .integer(0)])
            holes = plate.h.add(HolePatternNode.self, ["diameter": .number(5), "depth": .number(6)])
            rule = plate.h.add(EdgesByTagNode.self)
            fillet = plate.h.add(FilletNode.self, ["radius": .number(0.5)])
            plate.h.wire(centre, "vector", to: field, "center")
            plate.h.wire(field, "field", to: cull, "field")
            plate.h.wire(plate.placements, "placements", to: cull, "placements")
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            plate.h.wire(cull, "placements", to: holes, "placements")
            plate.h.wire(holes, "solid", to: rule, "solid")
            plate.h.wire(rule, "edges", to: fillet, "edges")
        }

        /// Culls hole {1} (the field is 0 there) and no other.
        mutating func cullHoleOne() {
            plate.h.set(centre, "x", .number(0))
            plate.h.set(centre, "y", .number(-7.5))
        }

        mutating func cullNothing() {
            plate.h.set(centre, "x", .number(1000))
            plate.h.set(centre, "y", .number(1000))
        }

        func bore(_ index: Int) -> TopoTag {
            TopoTag(node: NodeID.instanceScoped([holes.id, holes.id]), item: index, role: .side(segment: 1))
        }

        /// The rim of hole `index` on the plate's top.
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
            cullNothing()
            let solid = try onlySolid(try await plate.h.run([holes], kernel: kernel), holes)
            let edges = try indices.map { try #require(rim(of: $0, in: solid)).id }
            plate.h.set(rule, NodeSetting.picks, .edgePicks(solid.topology.picks(for: edges)))
        }

        func selected(_ report: EvaluationReport) throws -> (solid: Solid, edges: [EdgeInfo]) {
            let set = try #require(report.value(rule, "edges")?.edgeSets?.first)
            return (set.solid, set.edges.compactMap { set.solid.topology.edge($0) })
        }
    }

    @Test func aPickOnOneInstanceSurvivesAFieldCullOfAnother() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([4], kernel: kernel)
        let before = try f.selected(try await f.plate.h.run([f.rule], kernel: kernel))
        f.cullHoleOne()
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(report.isOK(f.rule) && report.isOK(f.fillet), "\(String(describing: report.state(f.rule)))")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1)
        #expect(edges.allSatisfy { edge in
            edge.faces.compactMap { solid.topology.face($0) }.contains { $0.tags.contains(f.bore(4)) }
        }, "still the rim of {4}")
        guard case .circle(let after, _, _, _, _)? = edges.first?.curve,
              case .circle(let was, _, _, _, _)? = before.edges.first?.curve else {
            Issue.record("expected circles")
            return
        }
        #expect(isClose(after, was), "the same physical hole: a cull never moves a pick to a neighbour")
    }

    @Test func aFieldCullLeavesTheSurvivorsAtTheirIndices() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        f.cullHoleOne()
        let report = try await f.plate.h.run([f.holes], kernel: kernel)
        let solid = try onlySolid(report, f.holes)
        let items = Set(solid.topology.faces.flatMap(\.tags).filter(\.node.isInstanceQualified).map(\.item))
        #expect(items == [0, 2, 3, 4, 5], "the holes are {0} and {2} to {5}, not renumbered")
        #expect(report.isOK(f.holes), "a cull never warns")
    }

    @Test func aPickOnACulledInstanceWarnsNamingItAndSelectsNothing() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([1], kernel: kernel)
        f.cullHoleOne()
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instance {1} no longer exists, so the edge picked on it isn't selected.")
        #expect(try f.selected(report).edges.isEmpty, "never a neighbour's rim")
    }
}
