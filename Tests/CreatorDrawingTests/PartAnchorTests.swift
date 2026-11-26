import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

/// Anchors in assembly views name their part (DR-5 R3, R4, R16): two copies of one part, identical tags, spans 0..<7 and 7..<14.
@Suite("Part anchors")
struct PartAnchorTests {
    private typealias Fixture = TopologyFixtures
    private let top = StandardOrientation.top.frame
    private let first = NodeID()
    private let second = NodeID()
    private let mapping = ViewMapping(scale: 1, offset: .zero)
    private static let shift = 1000

    /// Copy `n` of the part: ids offset by 1000 n and x moved by 100 n.
    private func copy(_ n: Int) -> Topology {
        let part = AnnotationFixtures.topology()
        let offset = Vector3(100 * Double(n), 0, 0)
        let faces = part.faces.map { face -> FaceInfo in
            var moved = face
            moved.id = FaceID(face.id.rawValue + Self.shift * n)
            moved.centroid = face.centroid + offset
            if let axisPoint = face.axisPoint { moved.axisPoint = axisPoint + offset }
            return moved
        }
        let edges = part.edges.map { edge -> EdgeInfo in
            var moved = edge
            moved.id = EdgeID(edge.id.rawValue + Self.shift * n)
            moved.faces = edge.faces.map { FaceID($0.rawValue + Self.shift * n) }
            moved.midpoint = edge.midpoint + offset
            switch edge.curve {
            case .line(let a, let b)?: moved.curve = .line(start: a + offset, end: b + offset)
            case .circle(let center, let axis, let radius, let start, let sweep)?:
                moved.curve = .circle(center: center + offset, axis: axis, radius: radius, start: start + offset, sweep: sweep)
            case nil: break
            }
            return moved
        }
        return Topology(faces: faces, edges: edges)
    }

    private var assembly: Topology {
        let one = copy(0), two = copy(1)
        return Topology(faces: one.faces + two.faces, edges: one.edges + two.edges)
    }

    private var spans: [PartSpan] {
        let count = copy(0).faces.count
        return [
            PartSpan(output: first, faces: 0..<count, curves: 0..<0),
            PartSpan(output: second, faces: count..<(2 * count), curves: 0..<0),
        ]
    }

    private func part(_ n: Int) -> Topology { assembly.restricted(toFaces: spans[n].faces) }

    private func edgePick(_ n: Int, _ id: Int) -> EdgePick {
        let topology = part(n)
        let key = topology.key(of: topology.edge(EdgeID(id + Self.shift * n))!)!
        let matches = topology.edges(matching: key)
        return EdgePick(key: key, matchCount: matches.count, runCount: matches.count > 1 ? 1 : nil)
    }

    private func anchor(
        _ candidate: PickCandidate, purpose: PickPurpose = .dimension, isometric: Bool = false, parts: [PartSpan]? = nil,
        frame: ProjectionFrame? = nil
    ) -> Result<PickedAnchor, DrawingRefusal> {
        DrawingPick.anchor(
            for: candidate, click: Vector2(5, 5), purpose: purpose, topology: assembly, frame: frame ?? top,
            mapping: mapping, isIsometric: isometric, parts: parts ?? spans)
    }

    @Test func aPickInAnAssemblyIsWrapped() throws {
        let made = try anchor(.edge(EdgeID(1102), stroke: 0)).get()
        guard case .onPart(let named, .edge(let pick)) = made.target else {
            Issue.record("expected a wrapped edge, got \(made.target)")
            return
        }
        #expect(named == second)
        #expect(pick.matchCount == 1)
    }

    @Test func twinPartsEachHoldTheirOwnEdge() {
        let key = edgePick(0, 102)
        #expect(key.key == edgePick(1, 102).key)
        let one = DrawingAnchorResolver.resolve(.onPart(first, .edge(key)), in: assembly, frame: top, parts: spans)
        let two = DrawingAnchorResolver.resolve(.onPart(second, .edge(key)), in: assembly, frame: top, parts: spans)
        guard case .held(_, let oneEdges, _) = one, case .held(_, let twoEdges, _) = two else {
            Issue.record("both copies should hold")
            return
        }
        #expect(oneEdges == [EdgeID(102)] && twoEdges == [EdgeID(1102)])
    }

    @Test func withoutWrappingTwinsAreSeveral() {
        let result = DrawingAnchorResolver.resolve(.edge(edgePick(0, 102)), in: assembly, frame: top, parts: spans)
        #expect(result == .lost(.several(2)))
    }

    @Test func aSingleViewNeverWraps() throws {
        let single = AnnotationFixtures.topology()
        let made = try DrawingPick.anchor(
            for: .edge(EdgeID(102), stroke: 0), click: .zero, purpose: .dimension, topology: single, frame: top, mapping: mapping,
            isIsometric: false, parts: nil
        ).get()
        guard case .edge = made.target else {
            Issue.record("a single view's anchors are bare")
            return
        }
    }

    @Test func anUntickedPartLosesItsAnchors() {
        let result = DrawingAnchorResolver.resolve(
            .onPart(second, .edge(edgePick(1, 102))), in: assembly, frame: top, parts: [spans[0]])
        #expect(result == .lost(.partNotShown))
        #expect(LostReason.partNotShown.sentence == "The part it was on isn't in this view any more.")
        #expect(DrawingAnchorResolver.scope(of: .onPart(second, .point(.zero)), in: assembly, parts: []).isFailure)
    }

    @Test func aCurveOnNoPartIsRefused() {
        let result = anchor(.edge(EdgeID(1102), stroke: 0), parts: [spans[0]])
        guard case .failure(let refusal) = result else {
            Issue.record("a line on no part is refused")
            return
        }
        #expect(refusal.sentence == DrawingPick.freeCurveSentence)
        guard case .failure(let balloon) = anchor(.edge(EdgeID(1102), stroke: 0), purpose: .balloon, parts: [spans[0]]) else {
            Issue.record("refused for a balloon too")
            return
        }
        #expect(balloon.sentence == DrawingPick.balloonFreeCurveSentence)
    }

    @Test func holeCalloutsReadTheirPart() {
        let ring = edgePick(1, 0)
        let reading = HoleReader.read(.onPart(second, .edge(ring)), in: assembly, frame: top, parts: spans)
        guard case .hole(_, let center, _, let radius) = reading else {
            Issue.record("expected a hole, got \(reading)")
            return
        }
        #expect(abs(center.x - 120) < 1e-9 && radius == 3)
        #expect(HoleReader.read(.onPart(second, .edge(ring)), in: assembly, frame: top, parts: [spans[0]]) == .lost(.partNotShown))
    }

    @Test func aDimensionBetweenTwoParts() throws {
        let view = AnnotationFixtures.makeView()
        let one = AnchorTarget.onPart(first, .edge(edgePick(0, 100)))
        let two = AnchorTarget.onPart(second, .edge(edgePick(1, 100)))
        let dimension = AnnotationFixtures.dimension(view.id, .linear(.horizontal), [one, two])
        let format = NumberFormat(units: .millimetres, standard: .iso, decimalSign: .point)
        let evaluated = try #require(
            AnnotationEvaluator.evaluate(dimension, topology: assembly, frame: top, format: format, parts: spans))
        #expect(evaluated.anchors == [.held, .held])
        guard case .success(let held) = evaluated.outcome else {
            Issue.record("a dimension between two parts holds")
            return
        }
        #expect(held.current.values.count == 1 && abs(held.current.values[0] - 100) < 1e-9)
    }

    @Test func balloonPicksTakeWhatLeadersTake() throws {
        let candidates: [PickCandidate] = [
            .edge(EdgeID(1102), stroke: 0), .edge(EdgeID(1000), stroke: 0), .outline(FaceID(1002), stroke: 0),
            .corner(EdgeID(1102), at: Vector2(100, 0)),
        ]
        for isometric in [false, true] {
            for candidate in candidates {
                let front = StandardOrientation.front.frame
                let leader = anchor(candidate, purpose: .leader, isometric: isometric, frame: front)
                let balloon = anchor(candidate, purpose: .balloon, isometric: isometric, frame: front)
                #expect(balloon.isSuccess == leader.isSuccess, "\(candidate) isometric \(isometric)")
                #expect(balloon.isSuccess, "\(candidate) isometric \(isometric)")
                #expect(try balloon.get().target.part == second)
            }
        }
    }

    @Test func balloonRefusalsSayBalloon() {
        let unnamed = [
            FaceInfo(
                id: FaceID(0), kind: .plane, normal: Vector3(0, 0, 1), area: 1, centroid: .zero, tags: Fixture.tags(.unnamed(face: 0))),
            FaceInfo(
                id: FaceID(1), kind: .plane, normal: Vector3(0, 0, -1), area: 1, centroid: .zero, tags: Fixture.tags(.unnamed(face: 1))),
        ]
        let topology = Topology(
            faces: unnamed, edges: [Fixture.line(0, Vector3(0, 0, 0), Vector3(10, 0, 0), between: 0, 1)])
        let parts = [PartSpan(output: first, faces: 0..<2, curves: 0..<0)]
        func result(_ purpose: PickPurpose) -> String? {
            let found = DrawingPick.anchor(
                for: .edge(EdgeID(0), stroke: 0), click: .zero, purpose: purpose, topology: topology, frame: top, mapping: mapping,
                isIsometric: false, parts: parts)
            if case .failure(let refusal) = found { return refusal.sentence }
            return nil
        }
        #expect(result(.balloon) == "This edge has no lasting name, so a balloon can't hold on to it.")
        #expect(result(.leader) == DrawingPick.noEdgeNameSentence)
    }
}

extension Result {
    fileprivate var isSuccess: Bool { if case .success = self { true } else { false } }
    fileprivate var isFailure: Bool { !isSuccess }
}
