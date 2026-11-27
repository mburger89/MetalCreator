import CreatorGeometry
import CreatorKernel
import Foundation
import Synchronization
import Testing

@testable import CreatorDrawing

/// Balloons on the two-copy assembly of DR-5 Task 3: item numbers, lost rules, feet (R4, R5, R21).
@Suite("Balloon composer")
struct BalloonComposerTests {
    private let first = NodeID()
    private let second = NodeID()
    private static let shift = 1000
    private let top = StandardOrientation.top.frame

    private func copy(_ n: Int, lift: Double = 0) -> Topology {
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
            case .line(let a, let b)?:
                let up = n == 0 && edge.id.rawValue == 102 ? Vector3(0, lift, 0) : .zero
                moved.curve = .line(start: a + offset + up, end: b + offset + up)
            case .circle(let center, let axis, let radius, let start, let sweep)?:
                moved.curve = .circle(center: center + offset, axis: axis, radius: radius, start: start + offset, sweep: sweep)
            case nil: break
            }
            return moved
        }
        return Topology(faces: faces, edges: edges)
    }

    private func assembly(lift: Double = 0) -> Topology {
        let one = copy(0, lift: lift), two = copy(1)
        return Topology(faces: one.faces + two.faces, edges: one.edges + two.edges)
    }

    private var spans: [PartSpan] {
        let count = copy(0).faces.count
        return [
            PartSpan(output: first, faces: 0..<count, curves: 0..<0),
            PartSpan(output: second, faces: count..<(2 * count), curves: 0..<0),
        ]
    }

    private func projection(lift: Double = 0) -> Projection2D {
        Projection2D(lines: [
            AnnotationFixtures.line(.line(Vector2(0, lift), Vector2(40, lift)), edge: 102),
            AnnotationFixtures.line(.line(Vector2(100, 0), Vector2(140, 0)), edge: 1102),
        ])
    }

    private func balloon(_ view: DrawingView, part n: Int, lift: Double = 0) -> DrawingAnnotation {
        let topology = assembly(lift: lift).restricted(toFaces: spans[n].faces)
        let id = EdgeID(102 + Self.shift * n)
        let key = topology.key(of: topology.edge(id)!)!
        let pick = EdgePick(key: key, matchCount: topology.edges(matching: key).count)
        let leader = LeaderEnd(target: .onPart(n == 0 ? first : second, .edge(pick)), hint: Vector2(20 + 100 * Double(n), -3))
        return DrawingAnnotation(view: view.id, kind: .balloon(Balloon(leader: leader, offset: Vector2(8, -12))))
    }

    private func view() -> DrawingView {
        DrawingView(
            kind: .base, source: first, orientation: .standard(.top), center: Vector2(150, 150), showsCentreMarks: false,
            assembly: [first, second])
    }

    private func facts(_ left: String = "Left", _ right: String = "Right") -> TitleBlockFacts {
        TitleBlockFacts(parts: [
            first: PartFacts(name: left, quantity: 1, isRemoved: false),
            second: PartFacts(name: right, quantity: 1, isRemoved: false),
        ])
    }

    private func compose(
        _ view: DrawingView, _ annotations: [DrawingAnnotation], lift: Double = 0, parts: [PartSpan]? = nil,
        facts: TitleBlockFacts? = nil, remembered: [AnnotationID: LastGood] = [:]
    ) -> SheetPicture {
        let sheet = DrawingSheet(name: "Sheet 1", views: [view], annotations: annotations)
        let document = DrawingDocument(sheets: [sheet])
        let content = ViewContent(projection: projection(lift: lift), topology: assembly(lift: lift), parts: parts ?? spans)
        return SheetComposer.compose(
            sheet, in: document, contents: [view.id: content], facts: facts ?? self.facts(), remembered: remembered)
    }

    private func numberText(_ picture: SheetPicture, _ annotation: DrawingAnnotation) -> [String] {
        AnnotationFixtures.texts(picture, of: annotation.id).map(\.original)
    }

    @Test func balloonsShowTheirItemNumbers() {
        let v = view()
        let a = balloon(v, part: 0), b = balloon(v, part: 1)
        let picture = compose(v, [a, b])
        #expect(numberText(picture, a) == ["1"] && numberText(picture, b) == ["2"])
        #expect(picture.annotationReports[a.id]?.status == .held)
    }

    @Test func balloonsAndListAgree() {
        let v = view()
        let a = balloon(v, part: 0), b = balloon(v, part: 1)
        let picture = compose(v, [a, b])
        #expect(picture.annotationReports[a.id]?.label == "Balloon 1" && picture.annotationReports[b.id]?.label == "Balloon 2")
        let document = DrawingDocument(sheets: [DrawingSheet(name: "Sheet 1", views: [v], annotations: [a, b])])
        let numbered = PartItems.numbered(document, names: PartItems.names(of: facts().parts))
        #expect(numbered.number(of: first) == 1 && numbered.number(of: second) == 2)
        let swapped = compose(v, [a, b], facts: facts("Z", "Right"))
        #expect(swapped.annotationReports[a.id]?.label == "Balloon 2" && swapped.annotationReports[b.id]?.label == "Balloon 1")
        #expect(numberText(swapped, a) == ["2"] && numberText(swapped, b) == ["1"])
    }

    @Test func aBalloonFollowsItsEdge() throws {
        let v = view()
        let a = balloon(v, part: 0)
        func foot(_ lift: Double) throws -> Vector2 {
            let picture = compose(v, [a], lift: lift)
            let report = try #require(picture.annotationReports[a.id])
            #expect(report.status == .held)
            guard case .leaders(let points)? = report.current?.figure else {
                Issue.record("expected a leaders figure")
                return .zero
            }
            return points[0]
        }
        let low = try foot(0), high = try foot(5)
        #expect(abs(low.y) < 1e-9 && abs(high.y - 5) < 1e-9)
    }

    @Test func aBalloonsCentreIsItsSheetFootPlusItsOffset() throws {
        let v = view()
        let sheet = DrawingSheet(name: "Sheet 1", views: [v])
        let content = ViewContent(projection: projection(), topology: assembly(), parts: spans)
        let mapping = try #require(ViewMapping.of(content: content, center: v.center, scale: sheet.scale.value))
        for n in 0...1 {
            let a = balloon(v, part: n)
            guard case .balloon(let made) = a.kind else { throw Failure.notABalloon }
            let report = try #require(compose(v, [a]).annotationReports[a.id])
            // The foot is the pick's nearest point to the hint: (20, 0) on copy 0's edge, (120, 0) on copy 1's.
            let foot = mapping.sheet(Vector2(20 + 100 * Double(n), 0))
            let centre = try #require(report.textCenter)
            #expect(LayoutSupport.close(centre, foot + made.offset, 1e-9), "copy \(n): \(centre) against \(foot + made.offset)")
        }
        // A lost balloon is drawn at the same place from its last foot.
        let a = balloon(v, part: 0)
        let last = LastGood(values: [], lines: ["1"], figure: .leaders([Vector2(20, 0)]))
        let lost = try #require(compose(v, [a], parts: [spans[1]], remembered: [a.id: last]).annotationReports[a.id])
        #expect(LayoutSupport.close(try #require(lost.textCenter), mapping.sheet(Vector2(20, 0)) + Vector2(8, -12), 1e-9))
    }

    private enum Failure: Error { case notABalloon }

    @Test func aLostBalloonKeepsItsNumber() throws {
        let v = view()
        let a = balloon(v, part: 0), b = balloon(v, part: 1)
        let last = LastGood(values: [], lines: ["1"], figure: .leaders([Vector2(20, 0)]))
        let picture = compose(v, [a, b], parts: [spans[1]], remembered: [a.id: last])
        let report = try #require(picture.annotationReports[a.id])
        #expect(report.status == .lost(.partNotShown))
        let texts = AnnotationFixtures.texts(picture, of: a.id)
        #expect(texts.map(\.original) == ["1?"] && texts.allSatisfy(\.isLost))
        let strokes = AnnotationFixtures.strokes(picture, of: a.id)
        #expect(!strokes.isEmpty && strokes.allSatisfy(\.isLost))
        let fills = picture.fills.filter { $0.annotation == a.id }
        #expect(!fills.isEmpty && fills.allSatisfy { $0.isLost })
        #expect(picture.lostAnnotations == [a.id])
        #expect(picture.annotationReports[b.id]?.status == .held)
    }

    @Test func aLostBalloonWithNoLastGoodIsALoneQuestionMark() throws {
        let v = view()
        let a = balloon(v, part: 0)
        let picture = compose(v, [a], parts: [spans[1]])
        let texts = AnnotationFixtures.texts(picture, of: a.id)
        #expect(texts.map(\.original) == ["?"] && texts.allSatisfy(\.isLost))
        #expect(AnnotationFixtures.strokes(picture, of: a.id).isEmpty)
        #expect(picture.lostAnnotations == [a.id])
    }

    @Test func aBalloonInAnIsometricView() throws {
        let topology = AnnotationFixtures.topology()
        var v = AnnotationFixtures.makeView()
        v.orientation = .standard(.isometricFrontRight)
        let ellipse = ProjectedCurve.ellipse(
            center: Vector2(20, 10), majorAxis: Vector2(1, 0), majorRadius: 6, minorRadius: 3, start: 0, sweep: 2 * .pi)
        let hint = Vector2(30, 12)
        let leader = LeaderEnd(target: AnnotationFixtures.pick(topology, 0), hint: hint)
        let a = DrawingAnnotation(view: v.id, kind: .balloon(Balloon(leader: leader, offset: Vector2(10, 10))))
        let content = ViewContent(
            projection: Projection2D(lines: [AnnotationFixtures.line(ellipse, edge: 0)]), topology: topology)
        let sheet = DrawingSheet(name: "Sheet 1", views: [v], annotations: [a])
        let facts = TitleBlockFacts(parts: [v.source: PartFacts(name: "Only", quantity: 1, isRemoved: false)])
        let picture = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]), contents: [v.id: content], facts: facts)
        let report = try #require(picture.annotationReports[a.id])
        #expect(report.status == .held)
        guard case .leaders(let points)? = report.current?.figure else {
            Issue.record("expected a leaders figure")
            return
        }
        let expected = CurveNearest.point(on: ellipse, to: hint)
        #expect(LayoutSupport.close(points[0], expected, 1e-9))
        let u = points[0] - Vector2(20, 10)
        let residual: Double = u.x * u.x / 36 + u.y * u.y / 9 - 1
        #expect(abs(residual) < 1e-6)
    }

    @Test func aBalloonRemembersItsFoot() throws {
        let v = view()
        let a = balloon(v, part: 0)
        let report = try #require(compose(v, [a]).annotationReports[a.id])
        let current = try #require(report.current)
        #expect(current.lines == ["1"] && current.values.isEmpty)
        guard case .leaders(let points) = current.figure else {
            Issue.record("expected leaders")
            return
        }
        #expect(points.count == 1 && LayoutSupport.close(points[0], Vector2(20, 0), 1e-9))
    }

    @Test func refreshSkipsBalloons() {
        let v = view()
        let a = balloon(v, part: 0)
        let found = AnnotationRefresh.lastGood(
            for: a, topology: assembly(), frame: top, format: NumberFormat(units: .millimetres, settings: DrawingSettings()),
            standard: .iso, parts: spans, isPictorial: false)
        #expect(found == nil)
        let reason = AnnotationRefresh.lostReason(
            of: a, topology: assembly(), frame: top, format: NumberFormat(units: .millimetres, settings: DrawingSettings()),
            standard: .iso, parts: spans, isPictorial: false)
        #expect(reason == nil)
    }

    /// DR-5 minors R15: a compose restricts each span once however many anchors lie on it; the next compose does it again.
    @Test func aComposeRestrictsEachSpanOnce() {
        let view = view()
        let annotations = [balloon(view, part: 0), balloon(view, part: 0), balloon(view, part: 0), balloon(view, part: 1)]
        let seen = Mutex<[PartSpan]>([])
        let plain = compose(view, annotations)
        let hook: @Sendable (PartSpan) -> Void = { span in seen.withLock { $0.append(span) } }
        let counted = SpanScopes.$observer.withValue(hook, operation: { compose(view, annotations) })
        #expect(counted == plain)
        #expect(seen.withLock { $0 }.count == 2)
        #expect(Set(seen.withLock { $0 }) == Set(spans))
        _ = SpanScopes.$observer.withValue(hook, operation: { compose(view, annotations) })
        #expect(seen.withLock { $0 }.count == 4)
    }
}
