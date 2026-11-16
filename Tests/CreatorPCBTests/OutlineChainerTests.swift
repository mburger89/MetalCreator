import CreatorGeometry
import Testing
@testable import CreatorPCB

struct OutlineChainerTests {
    static func line(_ a: Vector2, _ b: Vector2, _ name: String) -> EdgeItem {
        EdgeItem(shape: .line(a, b), identity: "edge:\(name)")
    }

    static let rectangle: [EdgeItem] = [
        line(Vector2(0, 0), Vector2(10, 0), "a"), line(Vector2(10, 0), Vector2(10, 5), "b"),
        line(Vector2(10, 5), Vector2(0, 5), "c"), line(Vector2(0, 5), Vector2(0, 0), "d"),
    ]

    private func message(_ items: [EdgeItem], tolerance: Double = 0.01) -> String? {
        do {
            _ = try OutlineChainer.chain(items, tolerance: tolerance)
            return nil
        } catch let problem as KiCadProblem {
            return problem.message
        } catch {
            return "other"
        }
    }

    private func area(_ loop: [Segment2D]) -> Double { ArcGeometry.signedArea(loop) }

    @Test func shuffledRectangleIsOneCounterClockwiseLoop() throws {
        let items = [Self.rectangle[2], Self.rectangle[0].flipped, Self.rectangle[3], Self.rectangle[1].flipped]
        let outline = try OutlineChainer.chain(items, tolerance: 0.01)
        #expect(outline.outer.count == 4 && outline.holes.isEmpty)
        #expect(abs(area(outline.outer) - 50) < 1e-9)
        #expect(zip(outline.outer, outline.outer.dropFirst() + [outline.outer[0]]).allSatisfy {
            ($0.endPoint - $1.startPoint).length < 1e-9
        })
    }

    @Test func loopStartsAtLowestKeyWhateverTheOrder() throws {
        let first = try OutlineChainer.chain(Self.rectangle, tolerance: 0.01)
        let rotated = try OutlineChainer.chain(Array(Self.rectangle[2...] + Self.rectangle[..<2]), tolerance: 0.01)
        #expect(first.outer == rotated.outer && first.outerKeys == rotated.outerKeys)
        #expect(first.outerKeys.first == first.outerKeys.min())
    }

    static var rounded: [EdgeItem] { roundedRectangle(gap: 0.004) }

    static func roundedRectangle(gap: Double) -> [EdgeItem] {
        let r = 2.0, w = 20.0, h = 10.0, c = r * (1 - 0.5.squareRoot())
        func arc(_ cx: Double, _ cy: Double, _ sx: Double, _ sy: Double, _ n: String) -> EdgeItem {
            // quarter arc about (cx, cy) from the x-side to the y-side
            EdgeItem(shape: .arc(start: Vector2(cx + sx * r, cy), mid: Vector2(cx + sx * (r - c), cy + sy * (r - c)),
                                 end: Vector2(cx, cy + sy * r)), identity: "edge:arc\(n)")
        }
        return [
            Self.line(Vector2(r, 0), Vector2(w - r - gap, 0), "b"), arc(w - r, r, 1, -1, "br"),
            Self.line(Vector2(w, r), Vector2(w, h - r), "r"), arc(w - r, h - r, 1, 1, "tr"),
            Self.line(Vector2(w - r, h), Vector2(r, h), "t"), arc(r, h - r, -1, 1, "tl"),
            Self.line(Vector2(0, h - r), Vector2(0, r), "l"), arc(r, r, -1, -1, "bl"),
        ]
    }

    @Test func roundedRectangleWithSmallGapsCloses() throws {
        let outline = try OutlineChainer.chain(Self.roundedRectangle(gap: 0.004), tolerance: 0.005)
        #expect(outline.outer.count == 8)
        #expect(abs(area(outline.outer) - (200 - (4 - .pi) * 4)) < 1e-6)
    }

    @Test func gapBetweenTwoArcsInsertsALine() throws {
        let a = EdgeItem(shape: .arc(start: Vector2(10, 0), mid: Vector2(0, 10), end: Vector2(-10, 0)), identity: "edge:a")
        let b = EdgeItem(shape: .arc(start: Vector2(-10, 0.003), mid: Vector2(0, -10), end: Vector2(10, 0)), identity: "edge:b")
        let outline = try OutlineChainer.chain([a, b], tolerance: 0.005)
        #expect(outline.outer.count == 3)
        #expect(outline.outer.filter { if case .line = $0 { return true } else { return false } }.count == 1)
    }

    @Test func circleCutoutIsAClockwiseFullCircleHole() throws {
        let hole = EdgeItem(shape: .circle(center: Vector2(5, 2), radius: 1), identity: "edge:c")
        let outline = try OutlineChainer.chain(Self.rectangle + [hole], tolerance: 0.01)
        #expect(outline.holes.count == 1 && outline.holes[0].count == 1)
        guard case .arc(_, _, let start, let end) = outline.holes[0][0] else { Issue.record("not an arc"); return }
        #expect(abs(abs(end.radians - start.radians) - 2 * .pi) < 1e-12)
        #expect(area(outline.holes[0]) < 0)
    }

    @Test func bezierBecomesAQuinticSpline() throws {
        let p = [Vector2(0, 0), Vector2(3, 4), Vector2(7, -2), Vector2(10, 0)]
        let items = [EdgeItem(shape: .bezier(p[0], p[1], p[2], p[3]), identity: "edge:z"),
                     Self.line(Vector2(10, 0), Vector2(10, 5), "b"), Self.line(Vector2(10, 5), Vector2(0, 5), "c"),
                     Self.line(Vector2(0, 5), Vector2(0, 0), "d"),
                    ]
        let outline = try OutlineChainer.chain(items, tolerance: 0.01)
        let spline = try #require(outline.outer.compactMap { segment -> SplineCurve2D? in
            if case .spline(let curve) = segment { return curve } else { return nil }
        }.first)
        #expect(spline.knots == [0, 1] && spline.multiplicities == [6, 6] && spline.poles.count == 6 && spline.isValid)
        for t in [0.25, 0.5, 0.75] {
            let s = 1 - t
            let expected = p[0] * (s * s * s) + p[1] * (3 * t * s * s) + p[2] * (3 * t * t * s) + p[3] * (t * t * t)
            #expect((spline.point(at: t) - expected).length < 1e-12)
        }
    }

    @Test func refusals() {
        #expect(message([]) == "The board has no outline on Edge.Cuts.")
        #expect(message(Array(Self.rectangle.dropLast())) == "The board outline isn't closed near (0, -5) mm."
            || message(Array(Self.rectangle.dropLast()))?.hasPrefix("The board outline isn't closed near") == true)
        let bowtie = [Self.line(Vector2(0, 0), Vector2(10, 5), "a"), Self.line(Vector2(10, 5), Vector2(10, 0), "b"),
                      Self.line(Vector2(10, 0), Vector2(0, 5), "c"), Self.line(Vector2(0, 5), Vector2(0, 0), "d"),
                     ]
        #expect(message(bowtie) == "The board outline crosses itself near (5, -2.5) mm.")
        let outside = EdgeItem(shape: .circle(center: Vector2(30, 2), radius: 1), identity: "edge:c")
        #expect(message(Self.rectangle + [outside]) == "A cutout lies outside the board outline near (31, -2) mm.")
    }
}

extension EdgeItem {
    var flipped: EdgeItem {
        guard case .line(let a, let b) = shape else { return self }
        return EdgeItem(shape: .line(b, a), identity: identity)
    }
}
