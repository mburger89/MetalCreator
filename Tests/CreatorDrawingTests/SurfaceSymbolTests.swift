import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite struct SurfaceSymbolTests {
    let h = 2.5
    let k = DrawingSymbols.slant

    @Test func theBasicSymbolHasTwoLegsAt60Degrees() {
        let segments = DrawingSymbols.surface(.any, apex: .zero, h: h, extension: nil, standard: .iso)
        #expect(segments == [.line(.zero, Vector2(-1.4 * h * k, 1.4 * h)), .line(.zero, Vector2(3 * h * k, 3 * h))])
    }

    @Test func removalRequiredAddsTheBar() {
        let segments = DrawingSymbols.surface(.removalRequired, apex: .zero, h: h, extension: nil, standard: .iso)
        #expect(segments.count == 3)
        #expect(segments[2] == .line(Vector2(-1.4 * h * k, 1.4 * h), Vector2(1.4 * h * k, 1.4 * h)))
    }

    @Test func removalProhibitedAddsTheInscribedCircle() {
        let segments = DrawingSymbols.surface(.removalProhibited, apex: .zero, h: h, extension: nil, standard: .iso)
        guard segments.count == 3, case let .arc(center, radius, _, sweep) = segments[2] else {
            Issue.record("expected the circle")
            return
        }
        let h1 = 1.4 * h
        #expect(abs(radius - h1 / 3) <= 1e-12 && abs(sweep - 2 * .pi) <= 1e-12)
        #expect(abs(center.x) <= 1e-12 && abs(center.y - 2 * h1 / 3) <= 1e-12)
        // Tangent to the short leg: its distance from the centre is the radius.
        let leg = Vector2(-h1 * k, h1)
        let distance = abs(leg.x * center.y - leg.y * center.x) / (leg.x * leg.x + leg.y * leg.y).squareRoot()
        #expect(abs(distance - radius) <= 1e-12)
        // And to the long leg.
        let long = Vector2(3 * h * k, 3 * h)
        let longDistance = abs(long.x * center.y - long.y * center.x) / (long.x * long.x + long.y * long.y).squareRoot()
        #expect(abs(longDistance - radius) <= 1e-12)
    }

    @Test func aParameterAddsTheExtension() {
        let segments = DrawingSymbols.surface(.any, apex: Vector2(1, 2), h: h, extension: 8, standard: .iso)
        #expect(segments.count == 3)
        let top = Vector2(1 + 3 * h * k, 2 + 3 * h)
        #expect(segments[2] == .line(top, Vector2(top.x + 8, top.y)))
    }

    @Test func layPerpendicularIsTheGlyph() {
        let origin = Vector2(3, 4)
        #expect(
            DrawingSymbols.layPerpendicular(origin: origin, h: h, standard: .iso)
                == DrawingSymbols.characteristic(.perpendicularity, origin: origin, h: 0.8 * h))
    }
}
