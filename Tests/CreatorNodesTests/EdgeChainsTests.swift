import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorNodes

/// Edge chains (Curve Pattern, patterns spec §3): curves that meet end to end are one chain, from one free end to the other.
struct EdgeChainsTests {
    func line(_ a: Vector3, _ b: Vector3) -> EdgeCurve { .line(start: a, end: b) }

    let a = Vector3(0, 0, 0), b = Vector3(10, 0, 0), c = Vector3(10, 10, 0), d = Vector3(0, 10, 0)

    @Test func shuffledAndReversedEdgesJoinIntoOneOrderedOpenChain() throws {
        let chains = EdgeChains.chains(of: [line(c, b), line(a, b), line(c, d)])
        let chain = try #require(chains.first)
        #expect(chains.count == 1 && !chain.isClosed)
        #expect(chain.pieces.map(\.startPoint) == [a, b, c])
        #expect(chain.pieces.map(\.endPoint) == [b, c, d])
        #expect(isClose(chain.length, 30))
    }

    @Test func edgesThatEndWhereTheyBeganAreAClosedChain() throws {
        let chains = EdgeChains.chains(of: [line(a, b), line(c, b), line(c, d), line(a, d)])
        let chain = try #require(chains.first)
        #expect(chains.count == 1 && chain.isClosed && chain.pieces.count == 4)
        #expect(isClose(chain.length, 40))
    }

    @Test func separateEdgesAreSeparateChainsInTheOrderGiven() {
        let far = Vector3(100, 0, 0)
        let chains = EdgeChains.chains(of: [line(a, b), line(far, far + b), line(c, d)])
        #expect(chains.map(\.pieces.count) == [1, 1, 1])
        #expect(chains.map { $0.pieces[0].startPoint } == [a, far, c])
    }

    @Test func aFullCircleIsAChainOfItsOwnBesideALine() throws {
        let circle = EdgeCurve.circle(center: .zero, axis: .unitZ, radius: 5, start: Vector3(5, 0, 0), sweep: 2 * .pi)
        let chains = EdgeChains.chains(of: [line(a, b), circle])
        #expect(chains.count == 2 && chains[1].isClosed && chains[0].isClosed == false)
        #expect(isClose(chains[1].length, 10 * .pi))
    }

    @Test func aBranchingSetFallsIntoSeveralChainsWithNoEdgeLost() {
        let hub = Vector3(0, 0, 0)
        let arms = [line(hub, Vector3(10, 0, 0)), line(hub, Vector3(0, 10, 0)), line(hub, Vector3(-10, 0, 0))]
        let chains = EdgeChains.chains(of: arms)
        #expect(chains.map(\.pieces.count).reduce(0, +) == 3)
        #expect(chains.count == 2)
    }

    @Test func anArcContinuesALineAndIsSampledAlongItsLength() throws {
        // A quarter circle of radius 10 about the origin from (10, 0) to (0, 10), then a line from there to (0, 20): the chain starts
        // at the first curve with a free end, so the arc given first sets the way it runs.
        let arc = EdgeCurve.circle(center: .zero, axis: .unitZ, radius: 10, start: Vector3(10, 0, 0), sweep: .pi / 2)
        let chain = try #require(EdgeChains.chains(of: [arc, line(Vector3(0, 10, 0), Vector3(0, 20, 0))]).first)
        #expect(chain.pieces.count == 2 && isClose(chain.length, 5 * .pi + 10))
        let half = try #require(chain.sample(at: 2.5 * .pi))
        #expect(isClose(half.point, Vector3(10 * cos(.pi / 4), 10 * sin(.pi / 4), 0)))
        #expect(isClose(half.tangent, Vector3(-sin(.pi / 4), cos(.pi / 4), 0)))
        let onLine = try #require(chain.sample(at: 5 * .pi + 4))
        #expect(isClose(onLine.point, Vector3(0, 14, 0)) && isClose(onLine.tangent, .unitY))
    }

    @Test func aClockwiseArcRunsTheOtherWay() throws {
        let arc = EdgeCurve.circle(center: .zero, axis: .unitZ, radius: 10, start: Vector3(10, 0, 0), sweep: -.pi / 2)
        let end = try #require(arc.sample(at: arc.pathLength))
        #expect(isClose(end.point, Vector3(0, -10, 0)) && isClose(end.tangent, -.unitX))
        #expect(isClose(arc.endPoint, Vector3(0, -10, 0)))
        #expect(isClose(arc.reversed.startPoint, Vector3(0, -10, 0)) && isClose(arc.reversed.endPoint, Vector3(10, 0, 0)))
    }

    @Test func countsAndSpacingsFollowTheirRules() {
        let open = CurveChain([line(a, Vector3(60, 0, 0))], isClosed: false)
        #expect(open.distances(count: 4) == [0, 20, 40, 60])
        #expect(open.distances(count: 1) == [0] && open.distances(count: 0).isEmpty)
        #expect(open.count(spacing: 20) == 4 && open.count(spacing: 25) == 3 && open.count(spacing: 70) == 1)
        let closed = CurveChain([line(a, Vector3(60, 0, 0))], isClosed: true)
        #expect(closed.distances(count: 4) == [0, 15, 30, 45])
        #expect(closed.count(spacing: 20) == 3 && closed.count(spacing: 70) == 1)
        #expect(open.count(spacing: 0) == 0)
    }

    @Test func aProfileGivesItsOutlineThenItsHolesAsChains() throws {
        let outer = Profile2D.rectangle(width: 40, height: 20, plane: .xy).outer
        let hole = Profile2D.circle(radius: 3, center: .zero, plane: .xy).outer
        let chains = EdgeChains.chains(of: Profile2D(plane: .xy, outer: outer, holes: [hole]))
        #expect(chains.count == 2 && chains.allSatisfy(\.isClosed))
        #expect(isClose(chains[0].length, 120) && isClose(chains[1].length, 6 * .pi))
    }
}
