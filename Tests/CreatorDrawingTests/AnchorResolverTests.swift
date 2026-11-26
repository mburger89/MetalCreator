import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

@Suite("Anchor resolution")
struct AnchorResolverTests {
    private typealias Fixture = TopologyFixtures
    private let front = StandardOrientation.front.frame

    private func resolve(_ target: AnchorTarget, _ topology: Topology, frame: ProjectionFrame? = nil) -> AnchorResolution {
        DrawingAnchorResolver.resolve(target, in: topology, frame: frame ?? front)
    }

    private func v(_ x: Double, _ y: Double, _ z: Double) -> Vector3 { Vector3(x, y, z) }

    /// Two edges of the plate: a bottom edge along x between faces 0 and 2, and an upright between faces 0 and 3.
    private func cornerPlate(gap: Double = 0, uprightFrom: Vector3? = nil) -> Topology {
        Fixture.plate(edges: [
            Fixture.line(0, v(0, 0, 0), v(40, 0, 0), between: 0, 2),
            Fixture.line(1, uprightFrom ?? v(40 + gap, 0, 0), v(40 + gap, 0, 30), between: 0, 3),
        ])
    }

    @Test func anExactMatchIsHeld() {
        let topology = cornerPlate()
        let result = resolve(.edge(Fixture.pick(topology, [0])), topology)
        #expect(result == .held(.segment(v(0, 0, 0), v(40, 0, 0)), edges: [EdgeID(0)], isRun: false))
    }

    @Test func aSplitEdgeIsMeasuredAsItsRun() {
        let topology = Fixture.plate(edges: [
            Fixture.line(0, v(0, 0, 0), v(15, 0, 0), between: 0, 2),
            Fixture.line(1, v(15, 0, 0), v(40, 0, 0), between: 0, 2),
        ])
        let pick = Fixture.pick(topology, [0])
        #expect(pick.runCount == 1)
        #expect(
            resolve(.edge(pick), topology)
                == .held(.segment(v(0, 0, 0), v(40, 0, 0)), edges: [EdgeID(0), EdgeID(1)], isRun: true))
    }

    @Test func aCircleRunKeepsItsCentreAndSumsTheSweeps() {
        let half = Double.pi
        let first = Fixture.circle(0, center: v(0, 0, 0), axis: v(0, 0, 1), radius: 3, sweep: half, between: 0, 2)
        var second = first
        second.id = EdgeID(1)
        // The second half starts where the first ends.
        second.curve = .circle(center: v(0, 0, 0), axis: v(0, 0, 1), radius: 3, start: first.curve?.ends[1] ?? v(0, 0, 0), sweep: half)
        let topology = Fixture.plate(edges: [first, second])
        let result = resolve(.edge(EdgePick(key: topology.key(of: first)!, matchCount: 2, runCount: 1)), topology)
        guard case .held(.circle(let center, _, let radius, let sweep), _, let isRun) = result else {
            Issue.record("expected a held circle")
            return
        }
        #expect(center == v(0, 0, 0) && radius == 3 && isRun)
        #expect(abs(sweep - 2 * .pi) < 1e-9)
    }

    @Test func aChangedRunCountIsLost() {
        let topology = Fixture.plate(edges: [
            Fixture.line(0, v(0, 0, 0), v(15, 0, 0), between: 0, 2),
            Fixture.line(1, v(15, 0, 0), v(30, 10, 0), between: 0, 2),
        ])
        let pick = EdgePick(key: topology.key(of: topology.edges[0])!, matchCount: 2, runCount: 1)
        #expect(resolve(.edge(pick), topology) == .lost(.several(2)))
    }

    @Test func severalSeparateMatchesAreLost() {
        let topology = Fixture.plate(edges: [
            Fixture.line(0, v(0, 0, 0), v(10, 0, 0), between: 0, 2),
            Fixture.line(1, v(0, 0, 20), v(10, 0, 20), between: 0, 2),
        ])
        let pick = EdgePick(key: topology.key(of: topology.edges[0])!, matchCount: 1)
        let result = resolve(.edge(pick), topology)
        #expect(result == .lost(.several(2)))
        guard case .lost(let reason) = result else { return }
        #expect(reason.sentence.contains("2 edges"))
    }

    /// A face merged from two operands: the key `{p.endCap, q.endCap} | {p.side}` names the edge only after narrowing.
    private func narrowingTopology(edgeCount: Int) -> Topology {
        let faces = [Fixture.plane(0, .endCap, of: Fixture.node), Fixture.plane(1, .side(segment: 0), of: Fixture.node)]
        let edges = (0..<edgeCount).map {
            Fixture.line($0, v(0, 0, Double($0) * 20), v(10, 0, Double($0) * 20), between: 0, 1)
        }
        return Topology(faces: faces, edges: edges)
    }

    private var narrowedPick: EdgePick {
        let key = EdgeKey(Fixture.tags(.endCap).union(Fixture.tags(.endCap, of: Fixture.other)), Fixture.tags(.side(segment: 0)))
        return EdgePick(key: key, matchCount: 1)
    }

    @Test func aNarrowedKeyFindingOneIsHeld() {
        let topology = narrowingTopology(edgeCount: 1)
        #expect(topology.edges(matching: narrowedPick.key).isEmpty)
        #expect(resolve(.edge(narrowedPick), topology) == .held(.segment(v(0, 0, 0), v(10, 0, 0)), edges: [EdgeID(0)], isRun: false))
    }

    @Test func aNarrowedKeyFindingTwoIsLost() {
        #expect(resolve(.edge(narrowedPick), narrowingTopology(edgeCount: 2)) == .lost(.several(2)))
    }

    @Test func operandKeysAreNeverTried() {
        let faces = [Fixture.plane(0, .endCap, of: Fixture.node), Fixture.plane(1, .side(segment: 0), of: Fixture.third)]
        let topology = Topology(faces: faces, edges: [Fixture.line(0, v(0, 0, 0), v(10, 0, 0), between: 0, 1)])
        let merged = Fixture.tags(.endCap).union(Fixture.tags(.endCap, of: Fixture.other))
        let key = EdgeKey(merged, Fixture.tags(.side(segment: 0), of: Fixture.third))
        #expect(key.narrowed == nil)
        #expect(!topology.edges(resolving: key).isEmpty)
        #expect(resolve(.edge(EdgePick(key: key, matchCount: 1)), topology) == .lost(.missing))
    }

    @Test func aCornerIsTheSharedEnd() {
        let topology = cornerPlate()
        let result = resolve(.corner(Fixture.pick(topology, [0]), Fixture.pick(topology, [1])), topology)
        #expect(result == .held(.point(v(40, 0, 0)), edges: [EdgeID(0), EdgeID(1)], isRun: false))
    }

    @Test func aCornerWhoseEdgesPartIsLost() {
        let topology = cornerPlate(gap: 10)
        #expect(resolve(.corner(Fixture.pick(topology, [0]), Fixture.pick(topology, [1])), topology) == .lost(.cornerGone))
    }

    @Test func aCornerUsesTheRunsExtremeEnds() {
        let topology = Fixture.plate(edges: [
            Fixture.line(0, v(0, 0, 0), v(20, 0, 0), between: 0, 2),
            Fixture.line(1, v(20, 0, 0), v(40, 0, 0), between: 0, 2),
            Fixture.line(2, v(40, 0, 0), v(40, 0, 30), between: 0, 3),
            Fixture.line(3, v(20, 0, 0), v(20, 0, 30), between: 1, 3),
        ])
        let atEnd = resolve(.corner(Fixture.pick(topology, [0]), Fixture.pick(topology, [2])), topology)
        #expect(atEnd == .held(.point(v(40, 0, 0)), edges: [EdgeID(0), EdgeID(1), EdgeID(2)], isRun: true))
        #expect(resolve(.corner(Fixture.pick(topology, [0]), Fixture.pick(topology, [3])), topology) == .lost(.cornerGone))
    }

    @Test func joinConstantsMatchTheKernels() {
        #expect(DrawingAnchorResolver.joinTolerance == 1e-4)
        #expect(DrawingAnchorResolver.joinAngle == 0.01)
        for (gap, joined) in [(0.9e-4, true), (1.1e-4, false)] {
            let topology = cornerPlate(gap: 0)
            let apart = Fixture.plate(edges: [
                topology.edges[0], Fixture.line(1, v(40 + gap, 0, 0), v(80, 0, 0), between: 0, 3),
            ])
            #expect((Topology.runCount(apart.edges) == 1) == joined)
            let corner = resolve(.corner(Fixture.pick(apart, [0]), Fixture.pick(apart, [1])), apart)
            if joined {
                guard case .held = corner else {
                    Issue.record("a corner at a gap of \(gap) should hold")
                    continue
                }
            } else {
                #expect(corner == .lost(.cornerGone))
            }
        }
        for (off, one) in [(0.009, true), (0.011, false)] {
            let second = v(40 + cos(off) * 40, 0, sin(off) * 40)
            let topology = Fixture.plate(edges: [
                Fixture.line(0, v(0, 0, 0), v(40, 0, 0), between: 0, 2), Fixture.line(1, v(40, 0, 0), second, between: 0, 2),
            ])
            #expect((Topology.runCount(topology.edges) == 1) == one)
            let pick = EdgePick(key: topology.key(of: topology.edges[0])!, matchCount: 2, runCount: 1)
            if one {
                guard case .held(_, _, true) = resolve(.edge(pick), topology) else {
                    Issue.record("a bend of \(off) rad should stay one run")
                    continue
                }
            } else {
                #expect(resolve(.edge(pick), topology) == .lost(.several(2)))
            }
        }
    }

    @Test func aCentreOfALineIsLost() {
        let topology = cornerPlate()
        #expect(resolve(.centre(Fixture.pick(topology, [0])), topology) == .lost(.notLineOrCircle))
    }

    @Test func aCentreIsTheCirclesCentre() {
        let topology = Fixture.plate(edges: [Fixture.circle(0, center: v(5, 0, 6), axis: v(0, 1, 0), radius: 3, between: 0, 2)])
        #expect(resolve(.centre(Fixture.pick(topology, [0])), topology) == .held(.point(v(5, 0, 6)), edges: [EdgeID(0)], isRun: false))
    }

    @Test func aTiltedCentreIsForeshortened() {
        let tilt = 10.0 * .pi / 180
        let axis = v(0, cos(tilt), sin(tilt))
        let topology = Fixture.plate(edges: [Fixture.circle(0, center: v(5, 0, 6), axis: axis, radius: 3, between: 0, 2)])
        #expect(resolve(.centre(Fixture.pick(topology, [0])), topology) == .lost(.foreshortened))
    }

    @Test func aFaceThatFitsTwoIsLost() {
        let topology = Topology(faces: [Fixture.cylinder(0, .side(segment: 0)), Fixture.cylinder(1, .side(segment: 0))], edges: [])
        let pick = FacePick(tags: Fixture.tags(.side(segment: 0)))
        let result = resolve(.axis(pick), topology)
        #expect(result == .lost(.severalFaces(2)))
        guard case .lost(let reason) = result else { return }
        #expect(reason.sentence.contains("2 faces"))
    }

    @Test func aNarrowableCylinderIsStillMissing() {
        let topology = Topology(faces: [Fixture.cylinder(0, .side(segment: 0))], edges: [])
        let pick = FacePick(tags: Fixture.tags(.side(segment: 0)).union(Fixture.tags(.side(segment: 0), of: Fixture.other)))
        #expect(!topology.resolution(of: pick).faces.isEmpty)
        #expect(resolve(.axis(pick), topology) == .lost(.missing))
        #expect(resolve(.outline(pick, side: Vector2(0, 1)), topology) == .lost(.missing))
    }

    @Test func anOutlinePicksItsSide() {
        let topology = Topology(faces: [Fixture.cylinder(0, .side(segment: 0))], edges: [])
        let pick = FacePick(tags: Fixture.tags(.side(segment: 0)))
        let geometry = { (side: Double) in AnchorGeometry.cylinder(axisPoint: v(0, 0, 0), axis: v(1, 0, 0), radius: 5, side: side) }
        #expect(resolve(.outline(pick, side: Vector2(0, 1)), topology) == .held(geometry(1), edges: [], isRun: false))
        #expect(resolve(.outline(pick, side: Vector2(0, -1)), topology) == .held(geometry(-1), edges: [], isRun: false))
        #expect(resolve(.axis(pick), topology) == .held(geometry(0), edges: [], isRun: false))
    }

    @Test func aTurnedOutlineIsLost() {
        let topology = Topology(faces: [Fixture.cylinder(0, .side(segment: 0))], edges: [])
        let pick = FacePick(tags: Fixture.tags(.side(segment: 0)))
        #expect(resolve(.outline(pick, side: Vector2(1, 0)), topology) == .lost(.outlineTurned))
        // A cylinder seen end on has no outline side at all.
        #expect(resolve(.outline(pick, side: Vector2(0, 1)), topology, frame: StandardOrientation.left.frame) == .lost(.outlineTurned))
    }

    @Test func aPlaneIsNotACylinder() {
        let topology = Fixture.plate(edges: [])
        let pick = FacePick(tags: Fixture.tags(.startCap))
        #expect(resolve(.axis(pick), topology) == .lost(.notCylinder))
    }

    @Test func aPointIsNeverResolved() {
        #expect(resolve(.point(Vector2(1, 2)), Fixture.plate(edges: [])) == .lost(.missing))
    }

    @Test func lastingNames() {
        #expect(!AnchorNaming.isLasting([]))
        #expect(!AnchorNaming.isLasting(Fixture.tags(.unnamed(face: 4))))
        #expect(!AnchorNaming.isLasting(Fixture.tags(.startCap).union(Fixture.tags(.unnamed(face: 4), of: Fixture.other))))
        #expect(AnchorNaming.isLasting(Fixture.tags(.startCap)))
    }

    @Test func everyReasonHasItsSentence() {
        let table: [(LostReason, String)] = [
            (.missing, "What it was attached to is no longer in the part."),
            (.several(3), "What it was attached to now fits 3 edges, and a dimension never guesses which."),
            (.severalFaces(2), "What it was attached to now fits 2 faces, and a dimension never guesses which."),
            (.notLineOrCircle, "What it measured is no longer a straight line or a circle."),
            (.cornerGone, "The two edges that met at its corner no longer meet at one point."),
            (.notCylinder, "The face it was attached to is no longer a cylinder."),
            (.outlineTurned, "The cylinder it was attached to has turned, so the side of its outline can't be told."),
            (.foreshortened, "What it measures now runs at an angle to the view, so its size here would be foreshortened."),
            (.notAHole, "The hole it called out is no longer a plain, counterbored or countersunk hole."),
            (.sourceRemoved, "The Output this view showed was removed."),
            (.viewFailed("The view failed."), "The view failed."),
            (.noPart, "This view has no part to measure."),
            (.refused("Too big."), "Too big."),
        ]
        for (reason, sentence) in table { #expect(reason.sentence == sentence) }
        #expect(LostReason.sourceRemoved.sentence == DrawingProjector.removedSentence)
    }
}
