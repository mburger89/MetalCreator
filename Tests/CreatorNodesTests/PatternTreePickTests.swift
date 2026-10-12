import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import CreatorSketch
import Foundation
import Testing

/// Patterns spec §6 with trees (7a-3): a pick on the rim of the hole at `{1;1}` follows that path through edits to the
/// pattern, and says so, naming the path, when it is gone. A pick saved before trees (7a-2) still resolves.
/// Which node of the fixture an edit changes.
enum EditTarget { case grid, rows, holes }

@MainActor
struct PatternTreePickTests {
    /// 3 × 2 Ø5 holes 15 mm apart, cut into rows of 3 (Partition), an Edges by Tag on the result and a Fillet on its edges.
    struct Fixture {
        var plate: PatternPlate
        let rows: Node, holes: Node, rule: Node, fillet: Node

        init() {
            plate = PatternPlate(columns: 3, rows: 2, spacingX: 15, spacingY: 15)
            rows = plate.h.add(PartitionNode.self, ["size": .integer(3)])
            holes = plate.h.add(HolePatternNode.self, ["diameter": .number(5), "depth": .number(6)])
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            plate.h.wire(plate.placements, "placements", to: rows, "tree")
            plate.h.wire(rows, "tree", to: holes, "placements")
            rule = plate.h.add(EdgesByTagNode.self)
            plate.h.wire(holes, "solid", to: rule, "solid")
            fillet = plate.h.add(FilletNode.self, ["radius": .number(0.5)])
            plate.h.wire(rule, "edges", to: fillet, "edges")
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

        /// Picks the rims of the holes at `paths` on the rule, from a run of the pattern as it is.
        mutating func pick(_ paths: [[Int]], kernel: any Kernel) async throws {
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
    }

    struct Edit: CustomTestStringConvertible {
        let what: String
        let target: EditTarget
        let socket: SocketName
        let value: ConstantValue
        var testDescription: String { what }
    }

    @Test(arguments: [
        Edit(what: "the spacing", target: .grid, socket: "spacingX", value: .number(18)),
        Edit(what: "the diameter", target: .holes, socket: "diameter", value: .number(6)),
        Edit(what: "the depth", target: .holes, socket: "depth", value: .number(4)),
        Edit(what: "the number of rows", target: .grid, socket: "countY", value: .integer(3)),
    ])
    func aFilletOnAnInstancesRimFollowsItsPathThroughAnEditToThePattern(_ edit: Edit) async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([[1, 1]], kernel: kernel)
        let before = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(before.isOK(f.rule) && before.isOK(f.fillet), "before changing \(edit.what)")
        let node: Node = switch edit.target {
        case .grid: f.plate.grid
        case .rows: f.rows
        case .holes: f.holes
        }
        f.plate.h.set(node, edit.socket, edit.value)
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(report.isOK(f.rule) && report.isOK(f.fillet), "after changing \(edit.what): \(String(describing: report.state(f.rule)))")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { f.touches([1, 1], $0, in: solid) }, "still the rim of the instance at {1;1}")
    }

    /// A pick names the instance's place in the tree, not the physical hole: rows of 4 make {1;1} the hole that was {1;2},
    /// with no warning.
    @Test func aLongerRowMovesAPickToTheHoleThatHoldsItsPlaceInTheTree() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([[1, 1]], kernel: kernel)
        func center(_ report: EvaluationReport) throws -> Vector3 {
            let edge = try #require(try f.selected(report).edges.first)
            guard case .circle(let center, _, _, _, _)? = edge.curve else { throw NodeError.invalidValue("not a circle") }
            return center
        }
        let before = try center(try await f.plate.h.run([f.rule], kernel: kernel))
        f.plate.h.set(f.rows, "size", .integer(4))  // 6 points in rows of 4 and 2.
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == nil)
        #expect(!isClose(try center(report), before), "{1;1} is another hole now")
    }

    @Test func aPickOnAPathThatIsGoneWarnsNamingItAndSelectsNothing() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([[1, 1]], kernel: kernel)
        f.plate.h.set(f.plate.grid, "countY", .integer(1))  // One row of 3: {0;0} to {0;2}.
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instance {1;1} no longer exists, so the edge picked on it isn't selected.")
        #expect(try f.selected(report).edges.isEmpty, "never a neighbour's rim")
    }

    @Test func everyVanishedPathIsNamedInPathOrder() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([[0, 2], [1, 1]], kernel: kernel)
        f.plate.h.set(f.rows, "size", .integer(2))
        f.plate.h.set(f.plate.grid, "countY", .integer(1))  // 3 points in rows of 2 and 1: {0;0}, {0;1}, {1;0}.
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instances {0;2} and {1;1} no longer exist, so the edges picked on them aren't selected.")
    }

    @Test func aProjectedRimFollowsItsPathAndWarnsNamingItWhenTheHoleIsGone() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        let solid = try onlySolid(try await f.plate.h.run([f.holes], kernel: kernel), f.holes)
        let rim = try #require(f.rim(of: [1, 1], in: solid))
        var drawing = Sketch()
        _ = drawing.add(SketchEntity(.projected(ProjectionSource(reference: "p1", curve: .circle(center: .zero, radius: 1)))))
        let pick = ConstantValue.edgePicks(solid.topology.picks(for: [rim.id]))
        let sketch = f.plate.h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing), NodeSetting.projection("p1"): pick])
        f.plate.h.wire(f.holes, "solid", to: sketch, "references")
        let before = try await f.plate.h.run([sketch], kernel: kernel)
        #expect(before.warning(sketch)?.contains("no longer exists") != true)
        f.plate.h.set(f.plate.grid, "countY", .integer(1))
        let report = try await f.plate.h.run([sketch], kernel: kernel)
        #expect(report.warning(sketch)?.contains("Projected edge 1 was picked on instance {1;1}, which no longer exists.") == true,
                "\(String(describing: report.warning(sketch)))")
    }

    // MARK: A pick saved in the 7a-2 form

    /// 7a-2 named instance `i` of a flat list `{i}` by the tag item `i` on the node `instanceScoped([placer, tool])`. The file
    /// below is one master 9e5d2d5 wrote (`LegacyDocuments`), not one built by today's code; a flat list is a tree of one level,
    /// so `{4}` must still be the item 4 and the pick must still find the rim of that hole, with no warning.
    @Test func aPickInAFileWrittenBy7a2StillResolvesAfterTheFileIsReopened() async throws {
        #expect(InstancePath.item(for: [4]) == 4)
        let reopened = try DocumentModel(data: Data(LegacyDocuments.holePatternPickFormat6.utf8), registry: BuiltInNodes.registry,
                                         kernel: OCCTKernel())
        let nodes = reopened.graph.nodes.values
        let holes = try #require(nodes.first { $0.typeID == HolePatternNode.typeID })
        let rule = try #require(nodes.first { $0.typeID == EdgesByTagNode.typeID })
        guard case .edgePicks(let picks)? = rule.inputValues[NodeSetting.picks] else {
            Issue.record("the file should hold edge picks")
            return
        }
        let stored = Set(picks.flatMap { $0.key.first.union($0.key.second) })
        let bore = TopoTag(node: NodeID.instanceScoped([holes.id, holes.id]), item: 4, role: .side(segment: 1))
        #expect(stored.contains(bore), "the stored pick names the copy by its flat index, under the same node as today")
        #expect(bore.node.rawValue.uuidString == "88C22DFA-1AF1-8F98-8C92-541F49C0DE7D")

        reopened.previewNode = rule.id
        await reopened.waitForEvaluation()
        guard case .ok? = reopened.results[rule.id]?.state else {
            Issue.record("the old pick should resolve with no warning: \(String(describing: reopened.results[rule.id]?.state))")
            return
        }
        let set = try #require(reopened.results[rule.id]?.outputs?["edges"]?.edgeSets?.first)
        #expect(set.edges.count == 1)
        let edge = try #require(set.edges.first.flatMap { set.solid.topology.edge($0) })
        #expect(edge.faces.compactMap { set.solid.topology.face($0) }.contains { $0.tags.contains(bore) })
    }
}
