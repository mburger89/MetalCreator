import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif
import Foundation
import Testing

/// Curve Pattern (patterns spec §3): placements along edges or an outline, facing along the tangent, one branch per chain.
struct CurvePatternNodeTests {
    func rows(_ report: EvaluationReport, _ node: Node) throws -> [[Plane]] {
        let tree = try #require(report.value(node, "placements")?.asTree, "\(String(describing: report.state(node)))")
        return tree.leaves.map { leaf in leaf.items.compactMap { if case .plane(let plane) = $0 { plane } else { nil } } }
    }

    /// A 40 × 20 rectangle outline, wired into a Curve Pattern with `settings`.
    func outline(_ settings: [SocketName: ConstantValue]) async throws -> (rows: [[Plane]], report: EvaluationReport, node: Node) {
        var h = Harness()
        let rectangle = h.add(RectangleNode.self, ["width": .number(40), "height": .number(20)])
        let node = h.add(CurvePatternNode.self, settings)
        h.wire(rectangle, "profile", to: node, "profile")
        let report = try await h.run([node])
        return (report.error(node) == nil ? try rows(report, node) : [], report, node)
    }

    #if canImport(CreatorOCCT)
    /// The four edges of a 40 × 20 × 6 box that run along X, as an edge set wired into a Curve Pattern.
    func boxEdges(_ settings: [SocketName: ConstantValue]) async throws -> (rows: [[Plane]], report: EvaluationReport, node: Node) {
        var h = Harness()
        let box = h.box(40, 20, 6)
        let along = h.add(EdgesByDirectionNode.self, ["direction": .vector(.unitX)])
        let node = h.add(CurvePatternNode.self, settings)
        h.wire(box, "solid", to: along, "solid")
        h.wire(along, "edges", to: node, "edges")
        let report = try await h.run([node], kernel: OCCTKernel())
        return (report.error(node) == nil ? try rows(report, node) : [], report, node)
    }
    #endif

    @Test func aClosedOutlineGetsItsPlacementsEvenlyRoundWithoutRepeatingTheStart() async throws {
        let (rows, _, _) = try await outline(["count": .integer(6)])
        let row = try #require(rows.first)
        #expect(rows.count == 1 && row.count == 6)
        // Perimeter 120, a placement every 20 mm from the first corner (−20, −10): along the bottom, up the right, back along the top.
        let expected = [Vector3(-20, -10, 0), Vector3(0, -10, 0), Vector3(20, -10, 0), Vector3(20, 10, 0), Vector3(0, 10, 0),
                        Vector3(-20, 10, 0),
        ]
        #expect(zip(row.map(\.origin), expected).allSatisfy { isClose($0, $1) }, "\(row.map(\.origin))")
    }

    @Test func eachPlacementFacesAlongTheTangent() async throws {
        let (rows, _, _) = try await outline(["count": .integer(6)])
        let normals = try #require(rows.first).map(\.normal)
        let expected = [Vector3.unitX, .unitX, .unitY, -.unitX, -.unitX, -.unitY]
        #expect(zip(normals, expected).allSatisfy { isClose($0, $1) }, "\(normals)")
    }

    @Test func bySpacingStandsThemOneSpacingApartFromTheStart() async throws {
        let (rows, _, _) = try await outline(["mode": .integer(1), "spacing": .number(25)])
        // 120 / 25 = 4 whole spacings round a closed chain: 0, 25, 50, 75.
        #expect(try #require(rows.first).count == 4)
        let second = try #require(rows.first)[1]
        #expect(isClose(second.origin, Vector3(5, -10, 0)))
    }

    #if canImport(CreatorOCCT)
    @Test func theEdgesOfAFilteredSetFormOneBranchPerChainAndOpenChainsRunEndToEnd() async throws {
        let (rows, report, node) = try await boxEdges(["count": .integer(3)])
        #expect(report.isOK(node), "\(String(describing: report.state(node)))")
        #expect(rows.count == 4, "four parallel edges are four chains")
        for row in rows {
            #expect(row.count == 3)
            #expect(isClose(abs(row[2].origin.x - row[0].origin.x), 40), "from one end to the other")
            #expect(isClose(abs(row[1].origin.x - row[0].origin.x), 20))
            #expect(row.allSatisfy { abs(abs($0.normal.x) - 1) < 1e-9 }, "facing along the edge")
        }
    }

    @Test func aCircleEdgeIsAClosedChainAndItsPlacementsFaceAlongItsTangent() async throws {
        var h = Harness()
        let circle = h.add(CircleNode.self, ["diameter": .number(20)])
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(10)])
        let edges = h.add(AllEdgesNode.self)
        let node = h.add(CurvePatternNode.self, ["count": .integer(4)])
        h.wire(circle, "profile", to: extrude, "profile")
        h.wire(extrude, "solid", to: edges, "solid")
        h.wire(edges, "edges", to: node, "edges")
        let report = try await h.run([node], kernel: OCCTKernel())
        let rows = try rows(report, node)
        #expect(rows.count == 2, "the rim at each end")
        for row in rows {
            #expect(row.count == 4)
            #expect(row.allSatisfy { abs(Vector3($0.origin.x, $0.origin.y, 0).length - 10) < 1e-6 })
            // Facing along the tangent: at right angles to the radius.
            #expect(row.allSatisfy { abs($0.normal.dot(Vector3($0.origin.x, $0.origin.y, 0))) < 1e-6 })
            #expect(isClose(row[0].origin, -row[2].origin + Vector3(0, 0, 2 * row[0].origin.z)), "opposite quarter-turns")
        }
    }
    #endif

    @Test func nothingToFollowOrTwoThingsToFollowIsRefused() async throws {
        var h = Harness()
        let lone = h.add(CurvePatternNode.self)
        let rectangle = h.add(RectangleNode.self)
        let box = h.box(10, 10, 10)
        let edges = h.add(AllEdgesNode.self)
        let both = h.add(CurvePatternNode.self)
        h.wire(box, "solid", to: edges, "solid")
        h.wire(edges, "edges", to: both, "edges")
        h.wire(rectangle, "profile", to: both, "profile")
        let report = try await h.run([lone, both])
        #expect(report.error(lone) == "Wire edges or a profile for the pattern to follow.")
        #expect(report.error(both) == "Wire either edges or a profile to follow, not both.")
    }

    @Test(arguments: [
        (["count": .integer(-1)], "“count” can't be negative."),
        (["mode": .integer(1), "spacing": .number(0)], "“spacing” must be greater than 0 mm."),
        (["mode": .integer(2)], "Choose By count or By spacing for “mode”."),
        (["count": .integer(2_001)], "Patterns are limited to 2,000 instances."),
        (["mode": .integer(1), "spacing": .number(0.01)], "Patterns are limited to 2,000 instances."),
    ] as [([SocketName: ConstantValue], String)])
    func aBadInputIsRefusedInPlainWords(settings: [SocketName: ConstantValue], message: String) async throws {
        let (_, report, node) = try await outline(settings)
        #expect(report.error(node) == message)
    }
}
