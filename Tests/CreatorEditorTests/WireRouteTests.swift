import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

/// The taut route (cable ties spec 2026-10-26 §5.1): an untied wire is today's one cubic; a tied one is a chain of cubics
/// through each tie's lane, meeting ties in stored flow order and then by ID, joining tangent-continuously at every lane;
/// lanes are 4 points apart across the flow in target order; the band is 6 points along the flow and 3 beyond the outer
/// lanes.
@MainActor
struct WireRouteTests {
    let source1 = Endpoint(node: nodeID(1), socket: "value"), source2 = Endpoint(node: nodeID(2), socket: "value")
    let source3 = Endpoint(node: nodeID(5), socket: "value")
    let upper = Endpoint(node: nodeID(3), socket: "value"), lower = Endpoint(node: nodeID(4), socket: "value")
    let third = Endpoint(node: nodeID(6), socket: "value")

    var links: [Link] { [Link(from: source1, to: upper), Link(from: source2, to: lower), Link(from: source3, to: third)] }
    var outputs: [Endpoint: Vector2] { [source1: Vector2(168, 60), source2: Vector2(168, 260), source3: Vector2(168, 460)] }
    var inputs: [Endpoint: Vector2] { [upper: Vector2(600, 60), lower: Vector2(600, 260), third: Vector2(600, 460)] }

    func routing(_ ties: [CableTie], flow: CanvasFlow = .horizontal) -> WireRouting {
        WireRouting(links: links, ties: Dictionary(uniqueKeysWithValues: ties.map { ($0.id, $0) }), outputs: outputs,
                    inputs: inputs, flow: flow)
    }

    func tie(_ n: Int, at position: Vector2, _ wires: Set<Endpoint>) -> CableTie {
        CableTie(id: tieID(n), position: position, wires: wires)
    }

    @Test func anUntiedRouteIsTodaysOneCubic() throws {
        let route = try #require(routing([]).routes[upper])
        #expect(route.pieces == [WireGeometry(from: Vector2(168, 60), to: Vector2(600, 60), flow: .horizontal)])
        #expect(route.pinned == [Vector2(168, 60), Vector2(600, 60)])
    }

    @Test func aTiedRouteRunsThroughItsLane() throws {
        let routed = routing([tie(1, at: Vector2(384, 160), [upper, lower])])
        let route = try #require(routed.routes[upper])
        #expect(route.pinned == [Vector2(168, 60), Vector2(384, 158), Vector2(600, 60)])
        let expected = [
            WireGeometry(from: Vector2(168, 60), to: Vector2(384, 158), flow: .horizontal),
            WireGeometry(from: Vector2(384, 158), to: Vector2(600, 60), flow: .horizontal),
        ]
        #expect(route.pieces == expected)
        #expect(routed.routes[lower]?.pinned == [Vector2(168, 260), Vector2(384, 162), Vector2(600, 260)])
        #expect(routed.routes[third]?.pieces.count == 1, "a wire the tie doesn't hold is untouched")
    }

    @Test func theRouteMeetsItsTiesInStoredFlowOrderThenByID() throws {
        let ordered = routing([tie(1, at: Vector2(450, 100), [upper, lower]), tie(2, at: Vector2(300, 100), [upper, lower])])
        #expect(ordered.routes[upper]?.pinned
                == [Vector2(168, 60), Vector2(300, 98), Vector2(450, 98), Vector2(600, 60)], "by position.x, not by ID")
        let level = routing([tie(2, at: Vector2(384, 100), [upper, lower]), tie(1, at: Vector2(384, 300), [upper, lower])])
        #expect(level.routes[upper]?.pinned
                == [Vector2(168, 60), Vector2(384, 298), Vector2(384, 98), Vector2(600, 60)], "level ties go by ID")
    }

    /// Each piece enters its end and leaves its start along the flow, so at every lane the incoming and outgoing tangents
    /// point the same way along the flow (G1), whichever way the lane lies, behind the source included.
    @Test func thePiecesJoinTangentContinuouslyAtEveryLaneEvenBehindTheSource() throws {
        for flow in [CanvasFlow.horizontal, .vertical] {
            let ties = [tie(1, at: Vector2(384, 160), [upper, lower]), tie(2, at: Vector2(100, 900), [upper, lower])]
            let route = try #require(routing(ties, flow: flow).routes[upper])
            #expect(route.pieces.count == 3)
            for (piece, next) in zip(route.pieces, route.pieces.dropFirst()) {
                #expect(piece.end == next.start)
                let incoming = piece.end - piece.control2, outgoing = next.control1 - next.start
                if flow == .horizontal {
                    #expect(incoming.y == 0 && outgoing.y == 0 && incoming.x > 0 && outgoing.x > 0, "\(flow)")
                } else {
                    #expect(incoming.x == 0 && outgoing.x == 0 && incoming.y > 0 && outgoing.y > 0, "\(flow)")
                }
            }
            let bounds = route.bounds(padding: 0)
            #expect(bounds.origin.isFinite && bounds.size.isFinite)
        }
    }

    @Test func lanesAreFourPointsApartAcrossTheFlowInTargetOrder() throws {
        let layout = try #require(routing([tie(1, at: Vector2(384, 160), [third, upper, lower])]).ties[tieID(1)])
        #expect(layout.lanes == [upper: Vector2(384, 156), lower: Vector2(384, 160), third: Vector2(384, 164)])
    }

    /// In the vertical flow the tie is drawn at its transpose and its lanes spread across x. Here every target has the same
    /// x, so the endpoint order decides.
    @Test func inTheVerticalFlowLanesSpreadAcrossXInEndpointOrder() throws {
        let layout = try #require(routing([tie(1, at: Vector2(384, 160), [third, lower, upper])], flow: .vertical).ties[tieID(1)])
        #expect(layout.lanes == [upper: Vector2(156, 384), lower: Vector2(160, 384), third: Vector2(164, 384)])
        #expect(layout.band == CanvasRect(origin: Vector2(153, 381), size: Vector2(14, 6)))
    }

    @Test func theBandSpansTheLanesWithItsOverhang() throws {
        let two = try #require(routing([tie(1, at: Vector2(384, 160), [upper, lower])]).ties[tieID(1)])
        #expect(two.band == CanvasRect(origin: Vector2(381, 155), size: Vector2(6, 10)))
        let sources = (0..<20).map { Endpoint(node: nodeID(100 + $0), socket: "value") }
        let targets = (0..<20).map { Endpoint(node: nodeID(200 + $0), socket: "value") }
        let many = WireRouting(
            links: zip(sources, targets).map { Link(from: $0, to: $1) },
            ties: [tieID(1): CableTie(id: tieID(1), position: Vector2(384, 160), wires: Set(targets))],
            outputs: Dictionary(uniqueKeysWithValues: sources.enumerated().map { ($1, Vector2(168, Double($0) * 30)) }),
            inputs: Dictionary(uniqueKeysWithValues: targets.enumerated().map { ($1, Vector2(600, Double($0) * 30)) }),
            flow: .horizontal)
        let band = try #require(many.ties[tieID(1)]?.band)
        #expect(band.size == Vector2(6, 19 * 4 + 6), "twenty lanes")
        #expect(Set(many.ties[tieID(1)]?.lanes.values.map(\.y) ?? []).count == 20, "each wire its own lane")
    }

    @Test func aRouteIsCulledByTheBoundsOfAllItsPieces() throws {
        let route = try #require(routing([tie(1, at: Vector2(384, 900), [upper, lower])]).routes[upper])
        let pieces = route.pieces.map { $0.bounds(padding: 4) }
        #expect(route.bounds(padding: 4) == pieces.dropFirst().reduce(pieces[0]) { $0.union($1) })
        #expect(route.bounds(padding: 4).contains(Vector2(384, 898)), "the lane far below")
    }

    @Test func distanceAndBoxesReadTheTautRoute() throws {
        let route = try #require(routing([]).routes[upper])
        #expect(abs(route.distance(to: Vector2(384, 64)) - 4) < 1e-9)
        #expect(route.intersects(CanvasRect(corner: Vector2(370, 40), Vector2(400, 80))))
        #expect(!route.intersects(CanvasRect(corner: Vector2(370, 100), Vector2(400, 120))))
        #expect(route.pointsInside(CanvasRect(corner: Vector2(370, 100), Vector2(400, 120))).isEmpty)
        #expect(route.intersects(CanvasRect(corner: Vector2(0, 0), Vector2(900, 900))), "lying wholly inside counts")
        #expect(route.pointsInside(CanvasRect(corner: Vector2(370, 40), Vector2(400, 80))).allSatisfy {
            abs($0.y - 60) < 1e-9 && (370...400).contains($0.x)
        })
        #expect(abs(route.middle.y - 60) < 1e-9, "the samples are the Bernstein sums, so within rounding")
    }

    @Test func theEditorRoutesTheLevelItShows() throws {
        let scene = TieScene()
        let editor = scene.editor(ties: [scene.tie()])
        #expect(editor.wireRouting.routes[scene.upper]?.pinned == [Vector2(168, 60), Vector2(384, 158), Vector2(600, 60)])
        #expect(editor.wireRouting.routes[scene.third]?.pinned == [Vector2(168, 460), Vector2(600, 460)])
        #expect(editor.wireRouting.ties[tieID(1)]?.band == CanvasRect(origin: Vector2(381, 155), size: Vector2(6, 10)))
    }
}
