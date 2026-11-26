import Foundation
import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Detail clip")
struct DetailClipTests {
    private let circle = HatchClip(center: Vector2(10, 5), radius: 4)
    private let parentID = ViewID()

    private func line(_ curve: ProjectedCurve, _ visibility: LineVisibility = .visible, _ cls: LineClass = .sharp,
                      source: ProjectionSource? = nil) -> ProjectedLine {
        ProjectedLine(visibility: visibility, lineClass: cls, curve: curve, source: source)
    }

    private func clip(_ curves: [ProjectedCurve]) -> [ProjectedCurve] {
        DetailClip.clip(Projection2D(lines: curves.map { line($0) }), to: circle).lines.map(\.curve)
    }

    private func dist(_ p: Vector2) -> Double { (p - circle.center).length }

    @Test func aLineIsCutAtTheCircle() {
        let result = clip([.line(Vector2(0, 5), Vector2(20, 5))])
        #expect(result.count == 1)
        guard case .line(let a, let b) = result[0] else { Issue.record("not a line"); return }
        #expect(abs(a.x - 6) < 1e-12 && abs(b.x - 14) < 1e-12 && abs(a.y - 5) < 1e-12)
    }

    @Test func aLineOutsideIsDropped() {
        #expect(clip([.line(Vector2(0, 20), Vector2(20, 20))]).isEmpty)
    }

    @Test func aLineInsideIsKept() {
        let curve = ProjectedCurve.line(Vector2(9, 5), Vector2(11, 6))
        #expect(clip([curve]) == [curve])
    }

    @Test func anArcStaysAnArc() throws {
        let result = clip([.arc(center: Vector2(10, 5), radius: 6, start: 0, sweep: 2 * Double.pi)])
        #expect(result.isEmpty)
        // The arc of radius 4 about (10, 1) meets the clip circle at 30 and 150 degrees; the part between them is inside.
        let crossing = clip([.arc(center: Vector2(10, 1), radius: 4, start: 0, sweep: Double.pi)])
        #expect(crossing.count == 1)
        guard case .arc(let c, let r, let start, let sweep) = try #require(crossing.first) else {
            Issue.record("not an arc")
            return
        }
        #expect(c == Vector2(10, 1) && r == 4)
        #expect(abs(start - Double.pi / 6) < 1e-9)
        #expect(abs(start + sweep - 5 * Double.pi / 6) < 1e-9)
    }

    @Test func aFullCircleCutAtItsStartIsOneArc() throws {
        // About (7, 5) with radius 2 the angle 0 point (9, 5) is inside and the angle 180 degrees point (5, 5) outside, so the two
        // inside runs [0, a] and [b, 2 pi] meet at angle 0 and are one arc.
        let result = clip([.arc(center: Vector2(7, 5), radius: 2, start: 0, sweep: 2 * Double.pi)])
        #expect(result.count == 1)
        guard case .arc(let c, let r, let start, let sweep) = try #require(result.first) else {
            Issue.record("not an arc")
            return
        }
        #expect(c == Vector2(7, 5) && r == 2 && sweep > 0 && sweep < 2 * Double.pi)
        for angle in [start, start + sweep] {
            #expect(abs(dist(Vector2(c.x + r * cos(angle), c.y + r * sin(angle))) - 4) < 1e-9)
        }
        #expect(start > Double.pi && start + sweep > 2 * Double.pi)
    }

    @Test func anEllipseThatOnlyJustLeavesTheCircleIsCut() {
        // The ellipse pokes 0.0002 mm out of the circle at both ends of its major axis, over about a hundredth of a radian, which is
        // less than the 256-step sampling's spacing: no sample sees it, only the dip between samples does. The ellipse starts half a
        // step before its vertex so that neither sample beside the vertex is outside either.
        let step = 2 * Double.pi / 256
        let curve = ProjectedCurve.ellipse(
            center: Vector2(10, 5), majorAxis: Vector2(1, 0), majorRadius: 4.0002, minorRadius: 2, start: -step / 2,
            sweep: 2 * Double.pi)
        let result = clip([curve])
        #expect(result.count == 2)
        for piece in result {
            guard case .ellipse(let c, _, let major, let minor, let start, let sweep) = piece else {
                Issue.record("not an ellipse")
                continue
            }
            for t in [start, start + sweep] {
                #expect(abs(dist(Vector2(c.x + major * cos(t), c.y + minor * sin(t))) - 4) < 1e-9)
            }
        }
    }

    @Test func aFullCircleInsideStaysFull() {
        let full = ProjectedCurve.arc(center: Vector2(10, 5), radius: 1, start: 0, sweep: 2 * Double.pi)
        #expect(clip([full]) == [full])
    }

    @Test func anEllipseIsCutAtItsCrossings() {
        let curve = ProjectedCurve.ellipse(
            center: Vector2(10, 5), majorAxis: Vector2(1, 0), majorRadius: 8, minorRadius: 2, start: 0, sweep: 2 * Double.pi)
        let result = clip([curve])
        #expect(result.count == 2)
        for piece in result {
            guard case .ellipse(let c, let axis, let major, let minor, let start, let sweep) = piece else {
                Issue.record("not an ellipse"); continue
            }
            #expect(c == Vector2(10, 5) && axis == Vector2(1, 0) && major == 8 && minor == 2)
            for t in [start, start + sweep] {
                let p = Vector2(c.x + major * cos(t), c.y + minor * sin(t))
                #expect(abs(dist(p) - 4) < 1e-9)
            }
        }
    }

    @Test func aPolylineIsSplitIntoRuns() {
        let result = clip([
            .polyline([Vector2(0, 5), Vector2(10, 5), Vector2(20, 5)]),
            .polyline([Vector2(10, 20), Vector2(10, 5), Vector2(10, 20)]),
        ])
        #expect(result.count == 2)
        guard case .polyline(let first) = result[0] else { Issue.record("not a polyline"); return }
        #expect(first.count == 4 || first.count == 3)
        #expect(abs(first[0].x - 6) < 1e-12 && abs(first[first.count - 1].x - 14) < 1e-12)
        let loop = [Vector2(0, 5), Vector2(20, 5), Vector2(20, 20), Vector2(0, 20), Vector2(0, 5), Vector2(10, 5)]
        let split = clip([.polyline(loop)])
        #expect(split.count == 2)
    }

    @Test func nothingLiesOutsideTheCircle() {
        var seed: UInt64 = 12345
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(1 << 53) * 24 - 7
        }
        var curves: [ProjectedCurve] = []
        for index in 0..<500 {
            switch index % 4 {
            case 0: curves.append(.line(Vector2(next(), next()), Vector2(next(), next())))
            case 1: curves.append(.arc(center: Vector2(next(), next()), radius: abs(next()) + 0.1, start: next(), sweep: next() / 3))
            case 2:
                curves.append(.ellipse(center: Vector2(next(), next()), majorAxis: Vector2(0.6, 0.8), majorRadius: abs(next()) + 1,
                                       minorRadius: abs(next()) / 2 + 0.1, start: next(), sweep: next() / 3))
            default: curves.append(.polyline([Vector2(next(), next()), Vector2(next(), next()), Vector2(next(), next())]))
            }
        }
        for piece in clip(curves) { expectInside(piece) }
    }

    private func expectInside(_ piece: ProjectedCurve) {
        switch piece {
        case .line(let a, let b): #expect(dist(a) <= 4 + 1e-9 && dist(b) <= 4 + 1e-9 && dist(lerpMid(a, b)) <= 4 + 1e-9)
        case .polyline(let points): for p in points { #expect(dist(p) <= 4 + 1e-9) }
        case .arc(let c, let r, let s, let w):
            for k in 0...20 {
                let t = s + w * Double(k) / 20
                #expect(dist(Vector2(c.x + r * cos(t), c.y + r * sin(t))) <= 4 + 1e-9)
            }
        case .ellipse(let c, let axis, let major, let minor, let s, let w):
            let cross = Vector2(-axis.y, axis.x)
            for k in 0...20 {
                let t = s + w * Double(k) / 20
                let u = major * cos(t), v = minor * sin(t)
                #expect(dist(Vector2(c.x + u * axis.x + v * cross.x, c.y + u * axis.y + v * cross.y)) <= 4 + 1e-9)
            }
        }
    }

    private func lerpMid(_ a: Vector2, _ b: Vector2) -> Vector2 { Vector2((a.x + b.x) / 2, (a.y + b.y) / 2) }

    @Test func sourcesAndClassesAreKept() {
        let source = ProjectionSource.edge(EdgeID(7))
        let projection = Projection2D(lines: [
            line(.line(Vector2(0, 5), Vector2(20, 5)), .hidden, .smooth, source: source),
            line(.line(Vector2(0, 50), Vector2(20, 50))),
            line(.line(Vector2(8, 4), Vector2(9, 4)), .visible, .outline, source: .face(FaceID(2))),
        ])
        let lines = DetailClip.clip(projection, to: circle).lines
        #expect(lines.count == 2)
        #expect(lines[0].visibility == .hidden && lines[0].lineClass == .smooth && lines[0].source == source)
        #expect(lines[1].lineClass == .outline && lines[1].source == .face(FaceID(2)))
    }

    @Test func hatchStopsAtTheCircle() {
        let region = HatchRegion(part: 0, edges: [[Vector2(-20, -20), Vector2(40, -20), Vector2(40, 30), Vector2(-20, 30)]])
        let parent = ViewContent(projection: Projection2D(), hatch: [region])
        let detail = DetailClip.content(of: parent, circle: DetailCircle(parent: parentID, center: Vector2(10, 5), radius: 4))
        #expect(detail.hatch == [region])
        #expect(detail.hatchClips == [circle])
        let mapping = ViewMapping(scale: 2, offset: Vector2(100, 100))
        func check(_ content: ViewContent, _ bounds: [HatchClip]) {
            let strokes = HatchPattern.strokes(
                content.hatch, mapping: mapping, clips: content.hatchClips, spacing: 1, width: 0.25, view: parentID)
            #expect(!strokes.isEmpty)
            for stroke in strokes {
                for segment in stroke.segments {
                    guard case .line(let a, let b) = segment else { continue }
                    for p in [a, b] {
                        let m = mapping.model(p)
                        for clip in bounds { #expect((m - clip.center).length <= clip.radius + 1e-9) }
                    }
                }
            }
        }
        check(detail, [circle])
        let inner = DetailClip.content(of: detail, circle: DetailCircle(parent: parentID, center: Vector2(13, 5), radius: 4))
        #expect(inner.hatchClips == [circle, HatchClip(center: Vector2(13, 5), radius: 4)])
        check(inner, inner.hatchClips)
        #expect(inner.framing == Rect2D(min: Vector2(9, 1), max: Vector2(17, 9)))
    }

    @Test func noParentIsAProblem() {
        let content = DetailClip.content(of: nil, circle: DetailCircle(parent: parentID, center: .zero, radius: 1))
        #expect(content.problem == "The view this detail enlarged was deleted.")
        #expect(content.projection == nil)
    }

    @Test func aPendingParentIsPending() {
        let parent = ViewContent(projection: nil, isPending: true, problem: "x", warnings: ["w"])
        let content = DetailClip.content(of: parent, circle: DetailCircle(parent: parentID, center: .zero, radius: 1))
        #expect(content.isPending && content.problem == "x" && content.warnings == ["w"])
    }
}
