import CreatorGeometry
import Foundation
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
        #expect(message(Array(Self.rectangle.dropLast())) == "The board outline isn't closed near (0, 0) mm.")
        let bowtie = [Self.line(Vector2(0, 0), Vector2(10, 5), "a"), Self.line(Vector2(10, 5), Vector2(10, 0), "b"),
                      Self.line(Vector2(10, 0), Vector2(0, 5), "c"), Self.line(Vector2(0, 5), Vector2(0, 0), "d"),
                     ]
        #expect(message(bowtie) == "The board outline crosses itself near (5, -2.5) mm.")
        let outside = EdgeItem(shape: .circle(center: Vector2(30, 2), radius: 1), identity: "edge:c")
        #expect(message(Self.rectangle + [outside]) == "A cutout lies outside the board outline near (31, -2) mm.")
    }
}

extension OutlineChainerTests {
    private func square(_ x: Double, _ y: Double, _ size: Double, _ name: String) -> [EdgeItem] {
        let points = [Vector2(x, y), Vector2(x + size, y), Vector2(x + size, y + size), Vector2(x, y + size)]
        return points.indices.map { Self.line(points[$0], points[($0 + 1) % 4], "\(name)\($0)") }
    }

    private func described(_ items: [EdgeItem]) -> String {
        do {
            let outline = try OutlineChainer.chain(items, tolerance: 0.01)
            return "\(outline.outer) \(outline.holes) \(outline.outerKeys) \(outline.holeKeys)"
        } catch let problem as KiCadProblem {
            return problem.message
        } catch {
            return "other"
        }
    }

    @Test func sharedVertexResultIsTheSameForEveryRotation() {
        let items = Self.rectangle + square(0, 0, 2, "h")
        let expected = described(items)
        for turn in items.indices {
            #expect(described(Array(items[turn...] + items[..<turn])) == expected)
            #expect(described(Array(items[turn...] + items[..<turn]).reversed().map(\.flipped)) == expected)
        }
        #expect(expected == "The board outline crosses itself near (0, 0) mm.")
    }

    @Test func twentyCutoutsAreOrderIndependent() {
        var items = square(0, 0, 100, "o")
        for index in 0..<20 {
            items += square(5 + Double(index % 5) * 18, 5 + Double(index / 5) * 22, 8, "h\(index)_")
        }
        let expected = described(items)
        #expect(!expected.hasPrefix("The board"))
        var state: UInt64 = 12_345
        for _ in 0..<10 {
            var shuffled = items
            for index in shuffled.indices.reversed() {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                shuffled.swapAt(index, Int(state >> 33) % (index + 1))
                if state & 1 == 1 { shuffled[index] = shuffled[index].flipped }
            }
            #expect(described(shuffled) == expected)
        }
    }

    @Test func fiveThousandPiecesUseTheGrid() throws {
        let count = 5_000
        let points = (0..<count).map { index -> Vector2 in
            let angle = 2 * Double.pi * Double(index) / Double(count)
            return Vector2(100 * cos(angle), 100 * sin(angle))
        }
        var items = points.indices.map { Self.line(points[$0], points[($0 + 1) % count], "p\($0)") }
        items.reverse()
        var evaluations = 0
        let outline = try OutlineChainer.chain(items, tolerance: 0.01, distanceEvaluations: &evaluations)
        #expect(evaluations > 0 && evaluations <= 50 * count)
        #expect(outline.outer.count == count)
    }

    @Test func overlappingAndDuplicatedEdgesAreCrossings() {
        let points = [(0, 0), (6, 0), (6, 5), (5, 5), (5, 0), (2, 0), (2, 3), (0, 3)].map { Vector2(Double($0.0), Double($0.1)) }
        let doubled = points.indices.map { Self.line(points[$0], points[($0 + 1) % points.count], "w\($0)") }
        #expect(message(doubled)?.hasPrefix("The board outline crosses itself") == true)
        let flat = [Self.line(Vector2(0, 0), Vector2(5, 0), "a"), Self.line(Vector2(5, 0), Vector2(0, 0), "b")]
        #expect(message(flat)?.hasPrefix("The board outline crosses itself") == true)
    }

    @Test func aPieceInsideACutoutIsRefused() {
        let items = square(0, 0, 100, "o") + square(10, 10, 60, "h") + square(20, 20, 10, "i")
        #expect(message(items) == "The board outline has a piece inside a cutout near (20, -30) mm, which isn't supported.")
    }

    @Test func aCutoutOverTheEdgeIsRefused() {
        #expect(message(square(0, 0, 100, "o") + square(200, 0, 10, "h"))?.hasPrefix("A cutout lies outside") == true)
    }

    @Test func fullCircleFromThreePoints() {
        let segment = ArcGeometry.arc(start: Vector2(0, 0), mid: Vector2(0, 4), end: Vector2(0, 0))
        guard case .arc(let centre, let radius, let start, let end) = segment else { Issue.record("not an arc"); return }
        #expect(centre == Vector2(0, 2) && radius == 2 && abs(end.radians - start.radians - 2 * .pi) < 1e-12)
    }

    @Test func collinearPointsMakeALineAtAnyScale() {
        for scale in [1e-6, 1.0, 1e5] {
            let segment = ArcGeometry.arc(start: Vector2(0, 0), mid: Vector2(scale, scale), end: Vector2(2 * scale, 2 * scale))
            #expect(segment == .line(Vector2(0, 0), Vector2(2 * scale, 2 * scale)))
        }
        #expect(ArcGeometry.arc(start: Vector2(0, 0), mid: Vector2(1000, 1e-7), end: Vector2(2000, 0)).isLine)
    }

    @Test func arcsAcrossTheSeamKeepContinuousAngles() {
        func point(_ degrees: Double) -> Vector2 { Vector2(10 * cos(degrees * .pi / 180), 10 * sin(degrees * .pi / 180)) }
        let ccw = ArcGeometry.arc(start: point(170), mid: point(180), end: point(190))
        guard case .arc(_, let radius, let a, let b) = ccw else { Issue.record("not an arc"); return }
        #expect(abs(radius - 10) < 1e-9 && abs((b.radians - a.radians) - 20 * .pi / 180) < 1e-9)
        let clockwise = ArcGeometry.arc(start: point(190), mid: point(180), end: point(170))
        guard case .arc(_, _, let c, let d) = clockwise else { Issue.record("not an arc"); return }
        #expect(abs((d.radians - c.radians) + 20 * .pi / 180) < 1e-9)
    }

    @Test func aClockwiseArcLoopBecomesCounterClockwise() throws {
        let items = [
            EdgeItem(shape: .arc(start: Vector2(10, 0), mid: Vector2(0, -10), end: Vector2(-10, 0)), identity: "edge:a"),
            EdgeItem(shape: .arc(start: Vector2(-10, 0), mid: Vector2(0, 10), end: Vector2(10, 0)), identity: "edge:b"),
        ]
        let outline = try OutlineChainer.chain(items, tolerance: 0.01)
        #expect(abs(ArcGeometry.signedArea(outline.outer) - 100 * .pi) < 1e-6)
    }
}

extension Segment2D {
    var isLine: Bool { if case .line = self { return true } else { return false } }
}

extension EdgeItem {
    var flipped: EdgeItem {
        guard case .line(let a, let b) = shape else { return self }
        return EdgeItem(shape: .line(b, a), identity: identity)
    }
}
