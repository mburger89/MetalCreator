import CreatorGeometry
import Foundation
import Testing

@testable import CreatorDrawing

@Suite struct ToleranceGlyphTests {
    let h = 2.5
    let origin = Vector2(10, 20)
    let k = DrawingSymbols.slant
    let s = DrawingSymbols.sixty

    func p(_ x: Double, _ y: Double) -> Vector2 { Vector2(origin.x + x * h, origin.y + y * h) }

    func near(_ a: Vector2, _ b: Vector2, _ tolerance: Double = 1e-12) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }

    func nearSegment(_ a: SheetSegment, _ b: SheetSegment) -> Bool {
        switch (a, b) {
        case let (.line(a0, a1), .line(b0, b1)): return near(a0, b0) && near(a1, b1)
        case let (.polyline(x), .polyline(y)): return x.count == y.count && zip(x, y).allSatisfy { near($0, $1) }
        case let (.arc(c0, r0, s0, w0), .arc(c1, r1, s1, w1)):
            return near(c0, c1) && abs(r0 - r1) <= 1e-12 && abs(s0 - s1) <= 1e-12 && abs(w0 - w1) <= 1e-12
        default: return false
        }
    }

    func expect(_ c: GeometricCharacteristic, _ expected: [SheetSegment], sourceLocation: SourceLocation = #_sourceLocation) {
        let got = DrawingSymbols.characteristic(c, origin: origin, h: h)
        #expect(got.count == expected.count, sourceLocation: sourceLocation)
        for (a, b) in zip(got, expected) { #expect(nearSegment(a, b), sourceLocation: sourceLocation) }
    }

    func full(_ x: Double, _ y: Double, _ r: Double) -> SheetSegment {
        .arc(center: p(x, y), radius: r * h, start: 0, sweep: 2 * .pi)
    }

    @Test func straightnessIsOneLine() { expect(.straightness, [.line(p(0, 0.5), p(1, 0.5))]) }
    @Test func flatnessIsAParallelogram() {
        expect(.flatness, [.polyline([p(0, 0.2), p(0.7, 0.2), p(1, 0.8), p(0.3, 0.8), p(0, 0.2)])])
    }
    @Test func circularityIsACircle() { expect(.circularity, [full(0.5, 0.5, 0.5)]) }
    @Test func cylindricityHasTwoTangentLines() {
        expect(
            .cylindricity,
            [
                full(0.5, 0.5, 0.3),
                .line(p(0.3 + 0.3 * s, 0.35 - 0.4 * s), p(0.7 + 0.3 * s, 0.35 + 0.4 * s)),
                .line(p(0.3 - 0.3 * s, 0.65 - 0.4 * s), p(0.7 - 0.3 * s, 0.65 + 0.4 * s)),
            ])
        // The unit-box ends the plan gives, and each line's distance from the centre.
        let unit = DrawingSymbols.characteristic(.cylindricity, origin: .zero, h: 1)
        guard case let .line(a0, a1) = unit[1], case let .line(b0, b1) = unit[2] else {
            Issue.record("expected two lines")
            return
        }
        #expect(near(a0, Vector2(0.3 + 0.3 * s, 0.35 - 0.4 * s)) && near(a1, Vector2(0.7 + 0.3 * s, 0.35 + 0.4 * s)))
        #expect(near(b0, Vector2(0.3 - 0.3 * s, 0.65 - 0.4 * s)) && near(b1, Vector2(0.7 - 0.3 * s, 0.65 + 0.4 * s)))
        for (from, to) in [(a0, a1), (b0, b1)] {
            let dx = to.x - from.x, dy = to.y - from.y
            let distance = abs(dx * (0.5 - from.y) - dy * (0.5 - from.x)) / (dx * dx + dy * dy).squareRoot()
            #expect(abs(distance - 0.3) <= 1e-12)
        }
    }
    @Test func lineProfileIsAnArc() { expect(.lineProfile, [.arc(center: p(0.5, 0.25), radius: 0.5 * h, start: 0, sweep: .pi)]) }
    @Test func surfaceProfileAddsItsBase() {
        expect(
            .surfaceProfile, [.arc(center: p(0.5, 0.25), radius: 0.5 * h, start: 0, sweep: .pi), .line(p(0, 0.25), p(1, 0.25))])
    }
    @Test func parallelismIsTwoSlantedLines() {
        expect(.parallelism, [.line(p(0.1, 0), p(0.1 + k, 1)), .line(p(0.4, 0), p(0.4 + k, 1))])
    }
    @Test func perpendicularityIsAnInvertedT() {
        expect(.perpendicularity, [.line(p(0.5, 0), p(0.5, 1)), .line(p(0, 0), p(1, 0))])
    }
    @Test func angularityIsAWedge() { expect(.angularity, [.polyline([p(1, k), p(0, 0), p(1, 0)])]) }
    @Test func positionIsACrossedCircle() {
        expect(.position, [full(0.5, 0.5, 0.35), .line(p(0, 0.5), p(1, 0.5)), .line(p(0.5, 0), p(0.5, 1))])
    }
    @Test func concentricityIsTwoCircles() { expect(.concentricity, [full(0.5, 0.5, 0.5), full(0.5, 0.5, 0.25)]) }
    @Test func symmetryIsThreeLines() {
        expect(.symmetry, [.line(p(0.15, 0.2), p(0.85, 0.2)), .line(p(0, 0.5), p(1, 0.5)), .line(p(0.15, 0.8), p(0.85, 0.8))])
    }
    @Test func circularRunoutIsOneArrow() {
        expect(.circularRunout, [.line(p(0.1, 0.1), p(0.9, 0.9)), .polyline([p(0.6, 0.9), p(0.9, 0.9), p(0.9, 0.6)])])
    }
    @Test func totalRunoutIsTwoArrowsOnABase() {
        expect(
            .totalRunout,
            [
                .line(p(0, 0.1), p(0.6, 0.7)), .line(p(0.4, 0.1), p(1, 0.7)), .line(p(0, 0.1), p(0.4, 0.1)),
                .polyline([p(0.35, 0.7), p(0.6, 0.7), p(0.6, 0.45)]), .polyline([p(0.75, 0.7), p(1, 0.7), p(1, 0.45)]),
            ])
    }

    @Test func slantsAreExactConstants() {
        #expect(DrawingSymbols.slant == (3.0).squareRoot() / 3)
        #expect(DrawingSymbols.sixty == (3.0).squareRoot() / 2)
        let parallel = DrawingSymbols.characteristic(.parallelism, origin: .zero, h: 1)
        guard case let .line(_, first) = parallel[0], case let .line(_, second) = parallel[1] else {
            Issue.record("expected lines")
            return
        }
        #expect(first.x == 0.1 + DrawingSymbols.slant)
        #expect(second.x == 0.4 + DrawingSymbols.slant)
        guard case let .polyline(angular) = DrawingSymbols.characteristic(.angularity, origin: .zero, h: 1)[0] else {
            Issue.record("expected a polyline")
            return
        }
        #expect(angular[0].x == 1)
        #expect(angular[0].y == DrawingSymbols.slant)
        // At another origin and size the points are only close, since adding the origin rounds.
        let moved = DrawingSymbols.characteristic(.angularity, origin: origin, h: h)
        guard case let .polyline(points) = moved[0] else {
            Issue.record("expected a polyline")
            return
        }
        #expect(near(points[0], p(1, k)))
    }

    @Test func everyGlyphFitsItsCellLoosely() {
        let slack = 0.05 * h
        for c in GeometricCharacteristic.allCases {
            var points: [Vector2] = []
            for segment in DrawingSymbols.characteristic(c, origin: origin, h: h) {
                switch segment {
                case let .line(a, b): points += [a, b]
                case let .polyline(list): points += list
                case let .arc(center, radius, start, sweep):
                    points += [Vector2(center.x + radius * cos(start), center.y + radius * sin(start))]
                    points += [Vector2(center.x + radius * cos(start + sweep), center.y + radius * sin(start + sweep))]
                    for quarter in 0..<4 {
                        let angle = Double(quarter) * .pi / 2
                        let within = sweep >= 2 * .pi - 1e-12 || (angle >= start && angle <= start + sweep)
                        if within { points.append(Vector2(center.x + radius * cos(angle), center.y + radius * sin(angle))) }
                    }
                default: break
                }
            }
            for point in points {
                #expect(point.x >= origin.x - slack && point.x <= origin.x + h + slack, "\(c)")
                #expect(point.y >= origin.y - slack && point.y <= origin.y + h + slack, "\(c)")
            }
        }
    }

    @Test func circledLetterIsCentred() {
        let center = Vector2(30, 40)
        let (segments, text) = DrawingSymbols.circled("M", center: center, h: h, standard: .iso)
        guard case let .arc(c, radius, _, sweep) = segments[0] else {
            Issue.record("expected an arc")
            return
        }
        #expect(near(c, center) && abs(radius - 0.6 * h) <= 1e-12 && abs(sweep - 2 * .pi) <= 1e-12)
        #expect(abs(text.height - 0.7 * h) <= 1e-12)
        #expect(abs(text.origin.x + text.run.width / 2 - center.x) <= 1e-9)
        #expect(abs(text.origin.y + text.height / 2 - center.y) <= 1e-9)
    }

    @Test func noTextIsOutsideWinAnsi() {
        for letter in ["M", "L", "F", "T", "P", "Ø"] {
            #expect(!DrawingSymbols.circled(letter, center: .zero, h: h, standard: .iso).text.run.hasReplacements)
        }
    }
}
