import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Foundation
import Testing

/// Face Pattern (patterns spec §3): a grid on a picked flat face, clipped to the face, its holes and an edge margin.
struct FacePatternNodeTests {
    /// A Face Pattern on the top of the 60 × 40 × 6 plate (z = 0), with a Ø20 hole through its middle when `drilled`.
    struct Fixture {
        var plate: PatternPlate
        let pattern: Node
        let part: Node

        init(drilled: Bool = false, hole diameter: Double = 20, _ settings: [SocketName: ConstantValue] = [:]) {
            plate = PatternPlate()
            pattern = plate.h.add(FacePatternNode.self, settings)
            if drilled {
                let hole = plate.cylinder(diameter: diameter, from: -7, to: 1)
                let cut = plate.h.add(BooleanNode.self, ["operation": .integer(1)])
                plate.h.wire(plate.plate, "solid", to: cut, "target")
                plate.h.wire(hole, "solid", to: cut, "tools")
                part = cut
            } else {
                part = plate.plate
            }
            plate.h.wire(part, "solid", to: pattern, "solid")
        }

        /// Picks the face of the part with the given outward normal (the top is +Z) and returns the report of the pattern.
        mutating func pick(normal: Vector3 = .unitZ, kernel: any Kernel = OCCTKernel()) async throws -> EvaluationReport {
            let solid = try onlySolid(try await plate.h.run([part], kernel: kernel), part)
            let face = try #require(solid.topology.faces.filter { $0.kind == .plane && $0.normal.map { isClose($0, normal) } == true }
                .max { $0.centroid.dot(normal) < $1.centroid.dot(normal) })
            plate.h.set(pattern, NodeSetting.face, .facePick(try #require(solid.topology.facePick(for: face.id))))
            return try await plate.h.run([pattern], kernel: kernel)
        }

        /// `value` to a micrometre: OCCT's centroids carry noise of 1e-16.
        static func snapped(_ value: Double) -> Double { (value * 1e6).rounded() / 1e6 + 0 }

        func tree(_ report: EvaluationReport) throws -> DataTree {
            try #require(report.value(pattern, "placements")?.asTree, "\(String(describing: report.state(pattern)))")
        }

        /// The placements of each row, empty cells left out: row `j` is the `j`th row the face's box reaches.
        func rows(_ report: EvaluationReport) throws -> [[Plane]] {
            let leaves = try tree(report).leaves
            return Dictionary(grouping: leaves, by: { $0.path.indices[0] }).sorted { $0.key < $1.key }.map { _, cells in
                cells.flatMap { cell in cell.items.compactMap { if case .plane(let plane) = $0 { plane } else { nil } } }
            }
        }

        /// Where each placed vent is, by its path `{row;column;0}`.
        func positions(_ report: EvaluationReport) throws -> [[Int]: Vector2] {
            var found: [[Int]: Vector2] = [:]
            for leaf in try tree(report).leaves {
                for (index, item) in leaf.items.enumerated() {
                    if case .plane(let plane) = item {
                        found[leaf.path.indices + [index]] = Vector2(Fixture.snapped(plane.origin.x), Fixture.snapped(plane.origin.y))
                    }
                }
            }
            return found
        }
    }

    @Test func aGridFillsTheFaceKeepingTheMarginFromItsEdges() async throws {
        var f = Fixture()
        let report = try await f.pick()
        let rows = try f.rows(report)
        // The face is 60 × 40 about its centroid (0, 0, 0). With a margin of 3 only |x| <= 27 and |y| <= 17 qualify: columns
        // −20…20 in rows −10…10, and the rows at y = ±20 (reached by the face's box, kept as branches of empty cells) are empty.
        #expect(rows.map(\.count) == [0, 5, 5, 5, 0])
        let positions = try f.positions(report)
        // Rows are counted from the lowest row the box reaches (y = −20) and columns from the lowest column (x = −30), so
        // the vent at (−20, −10) is {1;1;0} and the one at (20, 10) is {3;5;0}.
        #expect(positions[[1, 1, 0]] == Vector2(-20, -10) && positions[[3, 5, 0]] == Vector2(20, 10) && positions.count == 15)
        #expect(rows[1].map { Fixture.snapped($0.origin.x) } == [-20, -10, 0, 10, 20])
        #expect(rows.map { $0.first.map { Fixture.snapped($0.origin.y) } } == [nil, -10, 0, 10, nil])
        #expect(rows.flatMap { $0 }.allSatisfy { $0.normal == .unitZ && isClose($0.origin.z, 0) && $0.xAxis == .unitX })
    }

    @Test func staggerMovesEverySecondRowHalfAPitch() async throws {
        var f = Fixture(["stagger": .bool(true)])
        let rows = try f.rows(try await f.pick())
        #expect(rows.map(\.count) == [0, 6, 5, 6, 0])
        #expect(rows[1].map { Fixture.snapped($0.origin.x) } == [-25, -15, -5, 5, 15, 25])
        #expect(rows[2].map { Fixture.snapped($0.origin.x) } == [-20, -10, 0, 10, 20])
    }

    @Test func aHoleInTheFaceAddsItsOwnMargin() async throws {
        var f = Fixture(drilled: true)
        let rows = try f.rows(try await f.pick())
        let kept = rows.flatMap { $0 }.map { Vector2(Fixture.snapped($0.origin.x), Fixture.snapped($0.origin.y)) }
        // Every grid position on the face that is 3 mm clear of the outline and of the Ø20 hole (13 mm from the centre).
        var expected: [Vector2] = []
        for y in stride(from: -10.0, through: 10, by: 10) {
            for x in stride(from: -20.0, through: 20, by: 10) where Vector2(x, y).length >= 13 { expected.append(Vector2(x, y)) }
        }
        #expect(Set(kept) == Set(expected) && kept.count == 10, "\(kept)")
        #expect(!kept.contains(Vector2(0, 0)) && !kept.contains(Vector2(10, 0)))
    }

    @Test func aBiggerMarginDropsTheOuterColumnsAndRows() async throws {
        var f = Fixture(["margin": .number(12)])
        let rows = try f.rows(try await f.pick())
        #expect(rows.map(\.count) == [0, 0, 3, 0, 0], "|x| <= 18 and |y| <= 8")
    }

    /// Patterns spec §6: a pick on a vent follows the vent. A margin, a hole or a spacing of a hole changes which cells are
    /// clipped, never the path of a cell that stays (a path counted among the placements kept would shift every one after a gap).
    @Test func aVentKeepsItsPathWhenTheMarginGrowsByAPitch() async throws {
        var f = Fixture()
        let before = try f.positions(try await f.pick())
        f.plate.h.set(f.pattern, "margin", .number(13))
        let after = try f.positions(try await f.plate.h.run([f.pattern], kernel: OCCTKernel()))
        #expect(before.count == 15 && after.count == 3, "|x| <= 17 and |y| <= 7: three vents on the middle row")
        #expect(after.allSatisfy { before[$0.key] == $0.value }, "\(after) against \(before)")
        #expect(after[[2, 2, 0]] == Vector2(-10, 0) && after[[2, 4, 0]] == Vector2(10, 0))
    }

    @Test func aVentKeepsItsPathWhenAHoleGrows() async throws {
        var small = Fixture(drilled: true)
        var large = Fixture(drilled: true, hole: 30)
        let before = try small.positions(try await small.pick())
        let after = try large.positions(try await large.pick())
        #expect(before.count == 10 && after.count == 6, "a Ø30 hole takes the vents within 18 mm of the centre")
        #expect(after.allSatisfy { before[$0.key] == $0.value }, "\(after) against \(before)")
    }

    @Test func aFaceNarrowerThanHalfAPitchStaggersWithoutImpossibleColumns() async throws {
        var h = Harness()
        let slab = h.box(4, 40, 6, at: Vector3(0, 0, -6))
        let pattern = h.add(FacePatternNode.self, ["stagger": .bool(true), "margin": .number(0)])
        h.wire(slab, "solid", to: pattern, "solid")
        let kernel = OCCTKernel()
        let solid = try onlySolid(try await h.run([slab], kernel: kernel), slab)
        let top = try #require(solid.topology.faces.first { $0.kind == .plane && $0.normal == .unitZ })
        h.set(pattern, NodeSetting.face, .facePick(try #require(solid.topology.facePick(for: top.id))))
        let report = try await h.run([pattern], kernel: kernel)
        let tree = try #require(report.value(pattern, "placements")?.asTree, "\(String(describing: report.state(pattern)))")
        let origins = tree.items.compactMap { item -> Vector3? in if case .plane(let plane) = item { plane.origin } else { nil } }
        #expect(!origins.isEmpty && origins.allSatisfy { abs($0.x) < 1e-6 }, "only the unstaggered rows reach a 4 mm face")
    }

    @Test func aSideFaceFacesOutAlongItsNormal() async throws {
        var f = Fixture(["margin": .number(1)])
        let rows = try f.rows(try await f.pick(normal: .unitX))
        let placements = rows.flatMap { $0 }
        #expect(!placements.isEmpty)
        #expect(placements.allSatisfy { $0.normal == .unitX && isClose($0.origin.x, 30) })
    }

    @Test func aCurvedFaceIsRefused() async throws {
        var h = Harness()
        let circle = h.add(CircleNode.self, ["diameter": .number(20)])
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(10)])
        let pattern = h.add(FacePatternNode.self)
        h.wire(circle, "profile", to: extrude, "profile")
        h.wire(extrude, "solid", to: pattern, "solid")
        let kernel = OCCTKernel()
        let solid = try onlySolid(try await h.run([extrude], kernel: kernel), extrude)
        let side = try #require(solid.topology.faces.first { $0.kind == .cylinder })
        h.set(pattern, NodeSetting.face, .facePick(try #require(solid.topology.facePick(for: side.id))))
        #expect(try await h.run([pattern], kernel: kernel).error(pattern) == "Face Pattern works on flat faces for now.")
    }

    @Test func noPickOrAPickThatIsGoneSaysSo() async throws {
        var f = Fixture()
        let none = try await f.plate.h.run([f.pattern], kernel: OCCTKernel())
        #expect(none.error(f.pattern) == "Pick a face for this pattern to fill.")
        let stranger = FacePick(tags: [TopoTag(node: NodeID(), item: 0, role: .endCap)])
        f.plate.h.set(f.pattern, NodeSetting.face, .facePick(stranger))
        let gone = try await f.plate.h.run([f.pattern], kernel: OCCTKernel())
        #expect(gone.error(f.pattern) == "The picked face isn't on this solid any more. Pick it again.")
        f.plate.h.set(f.pattern, NodeSetting.face, .bool(true))
        #expect(try await f.plate.h.run([f.pattern], kernel: OCCTKernel()).error(f.pattern)
            == "This pattern's picked face can't be read. Pick the face again.")
    }

    @Test(arguments: [
        (["spacingX": .number(0)], "“spacingX” must be greater than 0 mm."),
        (["spacingY": .number(-1)], "“spacingY” must be greater than 0 mm."),
        (["margin": .number(-1)], "“margin” must be 0 or more."),
        (["spacingX": .number(0.5), "spacingY": .number(0.5)], "Patterns are limited to 2,000 instances."),
        (["spacingX": .number(0.01), "spacingY": .number(0.01)],
         "Face Pattern would have to try more than 200,000 positions: raise the spacing."),
        (["spacingX": .number(1e-300), "spacingY": .number(1e-300)],
         "Face Pattern would have to try more than 200,000 positions: raise the spacing."),
        (["spacingX": .number(1e-300)],
         "Face Pattern would have to try more than 200,000 positions: raise the spacing."),
        (["spacingY": .number(1e-300), "stagger": .bool(true)],
         "Face Pattern would have to try more than 200,000 positions: raise the spacing."),
    ] as [([SocketName: ConstantValue], String)])
    func aBadInputIsRefusedInPlainWords(settings: [SocketName: ConstantValue], message: String) async throws {
        var f = Fixture(settings)
        #expect(try await f.pick().error(f.pattern) == message)
    }

    @Test func theClippedAreaForThePreviewIsTheFaceMovedInByTheMargin() async throws {
        var f = Fixture()
        _ = try await f.pick()
        let kernel = OCCTKernel()
        let solid = try onlySolid(try await f.plate.h.run([f.part], kernel: kernel), f.part)
        guard case .facePick(let pick)? = f.plate.h.nodes[f.pattern.id]?.inputValues[NodeSetting.face] else {
            Issue.record("no pick stored")
            return
        }
        let loops = FacePatternNode.clippedArea(of: solid, pick: pick, margin: 3)
        #expect(loops.count == 1)
        let loop = try #require(loops.first)
        #expect(Set(loop.map { Vector2($0.x, $0.y) }) == [Vector2(-27, -17), Vector2(27, -17), Vector2(27, 17), Vector2(-27, 17)])
        #expect(loop.allSatisfy { isClose($0.z, 0) })
        #expect(FacePatternNode.clippedArea(of: solid, pick: FacePick(tags: []), margin: 3).isEmpty)
    }

    @Test func aPlaceOverTheFacePatternCopiesToolsInTheTreeOfCells() async throws {
        var f = Fixture()
        _ = try await f.pick()
        let tool = f.plate.cylinder(diameter: 4, from: 0, to: 3)
        let place = f.plate.h.add(PlaceNode.self)
        f.plate.h.wire(f.pattern, "placements", to: place, "placements")
        f.plate.h.wire(tool, "solid", to: place, "tool")
        let report = try await f.plate.h.run([place], kernel: FakeKernel())
        let tree = try #require(report.value(place, "solids")?.asTree, "\(String(describing: report.state(place)))")
        #expect(tree.depth == 3 && tree.itemCount == 15, "a cell is a branch of one copy, an empty cell a branch of none")
        let perRow = Dictionary(grouping: tree.leaves, by: { $0.path.indices[0] }).sorted { $0.key < $1.key }
        #expect(perRow.map { $0.value.reduce(0) { $0 + $1.items.count } } == [0, 5, 5, 5, 0])
    }
}
