import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import CreatorSketch
import Testing

/// Patterns spec §6: a pick on a patterned instance follows its path through edits to the pattern, and says so,
/// naming the path, when the instance is gone.
struct PatternPickStabilityTests {
    /// 3 × 2 Ø5 holes 15 mm apart in the plate, an Edges by Tag on the result and a Fillet on its edges.
    struct Fixture {
        var plate: PatternPlate
        let holes: Node, rule: Node, fillet: Node

        init() {
            plate = PatternPlate(columns: 3, rows: 2, spacingX: 15, spacingY: 15)
            holes = plate.h.add(HolePatternNode.self, ["diameter": .number(5), "depth": .number(6)])
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            plate.h.wire(plate.placements, "placements", to: holes, "placements")
            rule = plate.h.add(EdgesByTagNode.self)
            plate.h.wire(holes, "solid", to: rule, "solid")
            fillet = plate.h.add(FilletNode.self, ["radius": .number(0.5)])
            plate.h.wire(rule, "edges", to: fillet, "edges")
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

        /// Picks the rims of the holes `indices` on the rule, from a run of the pattern as it is.
        mutating func pick(_ indices: [Int], kernel: any Kernel) async throws {
            let solid = try onlySolid(try await plate.h.run([holes], kernel: kernel), holes)
            let edges = try indices.map { try #require(rim(of: $0, in: solid)).id }
            plate.h.set(rule, NodeSetting.picks, .edgePicks(solid.topology.picks(for: edges)))
        }

        /// The edges the rule selects now, and the holes they belong to.
        func selected(_ report: EvaluationReport) throws -> (solid: Solid, edges: [EdgeInfo]) {
            let set = try #require(report.value(rule, "edges")?.edgeSets?.first)
            return (set.solid, set.edges.compactMap { set.solid.topology.edge($0) })
        }
    }

    /// An edit to the pattern: a socket of the grid that lays it out, or of the Hole Pattern.
    struct Edit: CustomTestStringConvertible {
        let what: String
        let onGrid: Bool
        let socket: SocketName
        let value: ConstantValue
        var testDescription: String { what }
    }

    /// Whether `edge` is a rim of hole `index`: one of its faces is that hole's bore.
    func touchesHole(_ index: Int, _ edge: EdgeInfo, in solid: Solid, _ f: Fixture) -> Bool {
        edge.faces.compactMap { solid.topology.face($0) }.contains { $0.tags.contains(f.bore(index)) }
    }

    @Test(arguments: [
        Edit(what: "the spacing", onGrid: true, socket: "spacingX", value: .number(18)),
        Edit(what: "the diameter", onGrid: false, socket: "diameter", value: .number(6)),
        Edit(what: "the depth", onGrid: false, socket: "depth", value: .number(4)),
        Edit(what: "the number of columns", onGrid: true, socket: "countX", value: .integer(4)),
        Edit(what: "the number of rows", onGrid: true, socket: "countY", value: .integer(3)),
    ])
    func aFilletOnAnInstancesRimFollowsItsPositionInTheListThroughAnEditToTheHoles(_ edit: Edit) async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([4], kernel: kernel)
        let before = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(before.isOK(f.rule) && before.isOK(f.fillet), "before changing \(edit.what)")
        f.plate.h.set(edit.onGrid ? f.plate.grid : f.holes, edit.socket, edit.value)
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(report.isOK(f.rule) && report.isOK(f.fillet), "after changing \(edit.what): \(String(describing: report.state(f.rule)))")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { touchesHole(4, $0, in: solid, f) }, "still the rim of the instance at {4}")
    }

    /// A pick names the instance's place in the list, not the physical hole (User decision 7): a fourth column makes
    /// {4} another hole, the one that was {5} before it, with no warning.
    @Test func aChangedColumnCountMovesAPickToTheHoleThatHoldsItsPlaceInTheList() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([4], kernel: kernel)
        func center(_ report: EvaluationReport) throws -> Vector3 {
            let edge = try #require(try f.selected(report).edges.first)
            guard case .circle(let center, _, _, _, _)? = edge.curve else { throw NodeError.invalidValue("not a circle") }
            return center
        }
        let before = try center(try await f.plate.h.run([f.rule], kernel: kernel))
        f.plate.h.set(f.plate.grid, "countX", .integer(4))
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == nil)
        #expect(!isClose(try center(report), before), "{4} is another hole now")
    }

    @Test func aPickOnAnInstanceThatIsGoneWarnsNamingItAndSelectsNothing() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([4], kernel: kernel)
        f.plate.h.set(f.plate.grid, "countY", .integer(1))  // 3 holes: {0}, {1}, {2}
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instance {4} no longer exists, so the edge picked on it isn't selected.")
        #expect(try f.selected(report).edges.isEmpty, "never a neighbour's rim")
    }

    @Test func aProjectedRimFollowsItsHoleAndWarnsNamingItWhenTheHoleIsGone() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        let solid = try onlySolid(try await f.plate.h.run([f.holes], kernel: kernel), f.holes)
        let rim = try #require(f.rim(of: 4, in: solid))
        var drawing = Sketch()
        _ = drawing.add(SketchEntity(.projected(ProjectionSource(reference: "p1", curve: .circle(center: .zero, radius: 1)))))
        let pick = ConstantValue.edgePicks(solid.topology.picks(for: [rim.id]))
        let sketch = f.plate.h.add(SketchNode.self, [NodeSetting.sketch: .sketch(drawing), NodeSetting.projection("p1"): pick])
        f.plate.h.wire(f.holes, "solid", to: sketch, "references")
        let before = try await f.plate.h.run([sketch], kernel: kernel)
        #expect(before.warning(sketch)?.contains("no longer exists") != true, "hole {4} is still there")
        f.plate.h.set(f.plate.grid, "countY", .integer(1))  // 3 holes: {0}, {1}, {2}
        let report = try await f.plate.h.run([sketch], kernel: kernel)
        let expected = "Projected edge 1 was picked on instance {4}, which no longer exists." + SketchProjections.ignored
        #expect(report.warning(sketch)?.contains(expected) == true, "no neighbour's rim: \(String(describing: report.warning(sketch)))")
    }

    @Test func onlyTheVanishedPickIsDroppedWhenAnotherStillHolds() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([1, 4], kernel: kernel)
        f.plate.h.set(f.plate.grid, "countY", .integer(1))
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instance {4} no longer exists, so the edge picked on it isn't selected.")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { touchesHole(1, $0, in: solid, f) })
    }

    @Test func everyVanishedPathIsNamed() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([3, 4, 5], kernel: kernel)
        f.plate.h.set(f.plate.grid, "countY", .integer(1))
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instances {3}, {4}, and {5} no longer exist, so the edges picked on them aren't selected.")
    }

    @Test func aPickOnABossesTipFollowsItAndErrorsWhenTheBossIsGone() async throws {
        let kernel = OCCTKernel()
        var plate = PatternPlate(columns: 3, rows: 1, spacingX: 15)
        let bosses = plate.h.add(BossPatternNode.self, ["diameter": .number(6), "height": .number(5)])
        plate.h.wire(plate.plate, "solid", to: bosses, "part")
        plate.h.wire(plate.placements, "placements", to: bosses, "placements")
        let face = plate.h.add(PlaneFromFaceNode.self)
        plate.h.wire(bosses, "solid", to: face, "solid")
        let qualifier = NodeID.instanceScoped([bosses.id, bosses.id])
        let part = try onlySolid(try await plate.h.run([bosses], kernel: kernel), bosses)
        let tip = try #require(part.topology.faces.first { $0.tags.contains(TopoTag(node: qualifier, item: 2, role: .side(segment: 2))) })
        plate.h.set(face, NodeSetting.face, .facePick(try #require(part.topology.facePick(for: tip.id))))

        let before = try await plate.h.run([face], kernel: kernel)
        #expect(isClose(try #require(before.value(face, "plane")?.planes?.first).origin, Vector3(15, 0, 5)))
        plate.h.set(plate.grid, "spacingX", .number(20))
        let moved = try await plate.h.run([face], kernel: kernel)
        #expect(isClose(try #require(moved.value(face, "plane")?.planes?.first).origin, Vector3(20, 0, 5)), "{2} followed its boss")
        plate.h.set(plate.grid, "countX", .integer(2))
        let gone = try await plate.h.run([face], kernel: kernel)
        #expect(gone.error(face) == "Instance {2} no longer exists, so the picked face isn't there any more. Pick the face again.")
    }
}
