import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// Split edges (roadmap "Naming: picks on merged faces"): `EdgeCurve.ends`, `Topology.runCount`,
/// `EdgePick.runCount` and the drift rule `EdgePick.hasDrifted(matching:inRuns:)`.
struct EdgeRunTests {
    let node = NodeID()
    var top: TopoTag { TopoTag(node: node, item: 0, role: .endCap) }
    var side: TopoTag { TopoTag(node: node, item: 0, role: .side(segment: 6)) }

    func near(_ a: Vector3, _ b: Vector3) -> Bool { (a - b).length <= 1e-9 }

    func line(_ id: Int, _ start: Vector3, _ end: Vector3, faces: [FaceID] = [FaceID(0), FaceID(1)]) -> EdgeInfo {
        EdgeInfo(id: EdgeID(id), kind: .line, direction: (end - start).normalized, length: (end - start).length,
                 midpoint: (start + end) * 0.5, convexity: .convex, faces: faces, curve: .line(start: start, end: end))
    }

    @Test func aLineEndsAtItsTwoPoints() {
        #expect(EdgeCurve.line(start: .zero, end: Vector3(1, 2, 3)).ends == [.zero, Vector3(1, 2, 3)])
    }

    @Test func anArcEndsWhereItsSweepTakesItsStart() throws {
        let quarter = EdgeCurve.circle(center: Vector3(1, 1, 0), axis: .unitZ, radius: 2, start: Vector3(3, 1, 0), sweep: .pi / 2)
        let ends = quarter.ends
        try #require(ends.count == 2)
        #expect(near(ends[0], Vector3(3, 1, 0)))
        #expect(near(ends[1], Vector3(1, 3, 0)))
        // About −Z the same start sweeps the other way round.
        let reversed = EdgeCurve.circle(center: Vector3(1, 1, 0), axis: -.unitZ, radius: 2, start: Vector3(3, 1, 0), sweep: .pi / 2)
        #expect(near(reversed.ends[1], Vector3(1, -1, 0)))
    }

    @Test func aFullCircleHasNoEnds() {
        #expect(EdgeCurve.circle(center: .zero, axis: .unitZ, radius: 2, start: Vector3(2, 0, 0), sweep: 2 * .pi).ends.isEmpty)
    }

    @Test func edgesMeetingEndToEndAreOneRun() {
        // The bracket's plate-top edge on the merged side, split where the flange began: y −16…12 and 12…15.
        let long = line(0, Vector3(-30, 12, 6), Vector3(-30, -16, 6))
        let short = line(1, Vector3(-30, 12, 6), Vector3(-30, 15, 6))
        #expect(Topology.runCount([long, short]) == 1)
        #expect(Topology.runCount([long]) == 1)
    }

    @Test func runsAreTransitiveAndApartEdgesAreSeparateRuns() {
        let a = line(0, .zero, Vector3(1, 0, 0)), b = line(1, Vector3(1, 0, 0), Vector3(2, 0, 0))
        let c = line(2, Vector3(2, 0, 0), Vector3(3, 0, 0)), apart = line(3, Vector3(5, 0, 0), Vector3(6, 0, 0))
        #expect(Topology.runCount([a, c, b]) == 1)
        #expect(Topology.runCount([a, b, c, apart]) == 2)
        #expect(Topology.runCount([]) == 0)
    }

    @Test func anEdgeWithoutKnownEndsIsARunOfItsOwn() {
        var a = line(0, .zero, Vector3(1, 0, 0)), b = line(1, Vector3(1, 0, 0), Vector3(2, 0, 0))
        b.curve = nil
        #expect(Topology.runCount([a, b]) == 2)
        a.curve = .circle(center: .zero, axis: .unitZ, radius: 1, start: Vector3(1, 0, 0), sweep: 2 * .pi)
        #expect(Topology.runCount([a, line(1, Vector3(1, 0, 0), Vector3(2, 0, 0))]) == 2)
    }

    @Test func twoEdgesMeetingAtACornerAreTwoRuns() {
        let across = line(0, .zero, Vector3(10, 0, 0)), up = line(1, Vector3(10, 0, 0), Vector3(10, 10, 0))
        #expect(Topology.runCount([across, up]) == 2, "a right-angle corner is two edges to a person picking")
        let almost = line(2, Vector3(10, 0, 0), Vector3(20, 0.5, 0))
        #expect(Topology.runCount([across, almost]) == 2, "even a shallow bend is a corner")
    }

    @Test func aStraightRunAndATangentArcAreOneRun() {
        let across = line(0, .zero, Vector3(10, 0, 0))
        // A quarter arc leaving (10, 0) upwards: centre (10, 5), radius 5, from (10, 0) round to (15, 5).
        let arc = EdgeInfo(id: EdgeID(1), kind: .circle, direction: .unitZ, length: 5 * .pi / 2, midpoint: Vector3(13.5, 1.5, 0),
                           convexity: .convex, faces: [FaceID(0), FaceID(1)],
                           curve: .circle(center: Vector3(10, 5, 0), axis: .unitZ, radius: 5, start: Vector3(10, 0, 0), sweep: .pi / 2))
        #expect(Topology.runCount([across, arc]) == 1, "the arc leaves the line's end along the line")
        let corner = line(2, Vector3(10, 0, 0), Vector3(10, 10, 0))
        #expect(Topology.runCount([corner, arc]) == 2, "the arc turns away from a line that leaves the same point at an angle")
    }

    @Test func halvesOfASplitArcAreOneRun() {
        func piece(_ id: Int, from degrees: Double) -> EdgeInfo {
            let start = Vector3(5 * cos(degrees * .pi / 180), 5 * sin(degrees * .pi / 180), 0)
            return EdgeInfo(id: EdgeID(id), kind: .circle, direction: .unitZ, length: 1, midpoint: start, convexity: .convex,
                            faces: [FaceID(0), FaceID(1)],
                            curve: .circle(center: .zero, axis: .unitZ, radius: 5, start: start, sweep: .pi / 4))
        }
        #expect(Topology.runCount([piece(0, from: 0), piece(1, from: 45)]) == 1)
        #expect(Topology.runCount([piece(0, from: 0), piece(1, from: 90)]) == 2, "a gap")
    }

    /// OCCT edge ends sit up to the vertex tolerance (often 1e-5 mm) from the vertex they share after a blend.
    @Test func halvesThatEndAFewMicrometresApartAreStillOneRun() {
        let first = line(0, Vector3(-30, 12, 6), Vector3(-30, -16, 6))
        let second = line(1, Vector3(-30, 12.00002, 6), Vector3(-30, 15, 6))
        #expect(Topology.runCount([first, second]) == 1)
        let apart = line(2, Vector3(-30, 12.01, 6), Vector3(-30, 15, 6))
        #expect(Topology.runCount([first, apart]) == 2, "a hundredth of a millimetre is a real gap")
    }

    @Test func anEdgeLeavesEachEndAlongItself() throws {
        #expect(EdgeCurve.line(start: .zero, end: Vector3(0, 4, 0)).endDirections == [Vector3(0, 1, 0), Vector3(0, -1, 0)])
        let quarter = EdgeCurve.circle(center: .zero, axis: .unitZ, radius: 2, start: Vector3(2, 0, 0), sweep: .pi / 2)
        let directions = quarter.endDirections
        try #require(directions.count == 2)
        #expect(near(directions[0], Vector3(0, 1, 0)), "counter-clockwise from (2, 0)")
        #expect(near(directions[1], Vector3(1, 0, 0)), "back along the arc from (0, 2)")
        #expect(EdgeCurve.circle(center: .zero, axis: .unitZ, radius: 2, start: Vector3(2, 0, 0), sweep: 2 * .pi).endDirections.isEmpty)
        #expect(EdgeCurve.line(start: .zero, end: .zero).endDirections.isEmpty)
    }

    /// Face 0: top. Face 1: the side. `split` cuts the top-side edge in two at y = 12.
    func topology(split: Bool) -> Topology {
        let edges = split
            ? [line(0, Vector3(-30, 12, 6), Vector3(-30, -16, 6)), line(1, Vector3(-30, 12, 6), Vector3(-30, 15, 6))]
            : [line(0, Vector3(-30, 15, 6), Vector3(-30, -16, 6))]
        return Topology(faces: [
            FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero, tags: [top]),
            FaceInfo(id: FaceID(1), kind: .plane, normal: -.unitX, area: 1, centroid: .zero, tags: [side]),
        ], edges: edges)
    }

    @Test func pickingASplitEdgeRecordsItsRunCount() {
        #expect(topology(split: true).picks(for: [EdgeID(0), EdgeID(1)])
            == [EdgePick(key: EdgeKey([top], [side]), matchCount: 2, runCount: 1)])
    }

    @Test func aWholeEdgeRecordsNoRunCount() {
        #expect(topology(split: false).picks(for: [EdgeID(0)]) == [EdgePick(key: EdgeKey([top], [side]), matchCount: 1)])
    }

    /// Ordinals count edges, so a pick of one piece records no runs.
    @Test func pickingOnePieceRecordsItsOrdinalNotItsRuns() {
        #expect(topology(split: true).picks(for: [EdgeID(1)])
            == [EdgePick(key: EdgeKey([top], [side]), matchCount: 2, ordinals: [1])])
    }

    @Test func aSplitOrRejoinedEdgeIsNotDrift() {
        let split = EdgePick(key: EdgeKey([top], [side]), matchCount: 2, runCount: 1)
        #expect(!split.hasDrifted(matching: 2, inRuns: 1))
        #expect(!split.hasDrifted(matching: 1, inRuns: 1), "the edge is whole again")
        let whole = EdgePick(key: EdgeKey([top], [side]), matchCount: 1)
        #expect(!whole.hasDrifted(matching: 2, inRuns: 1), "the edge is split now")
    }

    @Test func moreOrFewerRunsAreDrift() {
        let split = EdgePick(key: EdgeKey([top], [side]), matchCount: 2, runCount: 1)
        #expect(split.hasDrifted(matching: 3, inRuns: 2))
        #expect(split.hasDrifted(matching: 0, inRuns: 0))
        let whole = EdgePick(key: EdgeKey([top], [side]), matchCount: 1)
        #expect(whole.hasDrifted(matching: 2, inRuns: 2), "a second edge, apart from the first")
    }

    /// A pick saved before runs were recorded has no `runCount`: each recorded edge counts as its own run. It
    /// drifts when its edges become fewer runs, and not when a recorded edge is split into more pieces.
    @Test func aPickWithoutARunCountCountsEachEdgeAsARun() {
        let saved = EdgePick(key: EdgeKey([top], [side]), matchCount: 2)
        #expect(!saved.hasDrifted(matching: 2, inRuns: 1))
        #expect(saved.hasDrifted(matching: 1, inRuns: 1), "2 recorded runs, now 1")
        #expect(!saved.hasDrifted(matching: 3, inRuns: 2), "one of the 2 recorded edges split in two")
    }

    @Test func aPickOfSomeMatchesComparesEdgesOnly() {
        let some = EdgePick(key: EdgeKey([top], [side]), matchCount: 2, ordinals: [1])
        #expect(some.hasDrifted(matching: 1, inRuns: 1))
        #expect(!some.hasDrifted(matching: 2, inRuns: 1))
    }

    @Test func aRunCountRoundTripsAndIsWrittenOnlyWhenRecorded() throws {
        let split = EdgePick(key: EdgeKey([top], [side]), matchCount: 2, runCount: 1)
        let whole = EdgePick(key: EdgeKey([top], [side]), matchCount: 1)
        #expect(try JSONDecoder().decode([EdgePick].self, from: try JSONEncoder().encode([split, whole])) == [split, whole])
        let text = try #require(String(bytes: try JSONEncoder().encode(whole), encoding: .utf8))
        #expect(!text.contains("runCount"))
    }
}
