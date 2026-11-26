import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite struct DatumLayoutTests {
    let h = 2.5
    let style = AnnotationStyle.iso
    var triangleHeight: Double { 1.2 * h * DrawingSymbols.sixty }

    func squareCentre(_ drawing: AnnotationDrawing) -> Vector2? {
        for case let .polyline(points) in drawing.segments where points.count == 5 {
            return Vector2((points[0].x + points[2].x) / 2, (points[0].y + points[2].y) / 2)
        }
        return nil
    }

    @Test func onALine() {
        let drawing = DatumLayout.onLine(
            letter: "A", foot: Vector2(100, 50), along: Vector2(1, 0), distance: 10, edgeEnds: nil, h: h, style: style)
        #expect(drawing.fills.count == 1)
        let triangle = drawing.fills[0]
        #expect(triangle[0].y == 50 && triangle[1].y == 50 && triangle[2].y > 50)
        #expect(squareCentre(drawing) == Vector2(100, 60))
        #expect(drawing.texts.first?.original == "A")
    }

    @Test func aScaledDirectionDrawsTheSame() {
        let unit = DatumLayout.onLine(
            letter: "A", foot: Vector2(100, 50), along: Vector2(1, 0), distance: 10, edgeEnds: nil, h: h, style: style)
        let scaled = DatumLayout.onLine(
            letter: "A", foot: Vector2(100, 50), along: Vector2(2, 0), distance: 10, edgeEnds: nil, h: h, style: style)
        #expect(scaled.fills == unit.fills)
        #expect(squareCentre(scaled) == Vector2(100, 60))
    }

    @Test func belowALine() {
        let drawing = DatumLayout.onLine(
            letter: "A", foot: Vector2(100, 50), along: Vector2(1, 0), distance: -10, edgeEnds: nil, h: h, style: style)
        #expect(drawing.fills[0][2].y < 50)
        #expect(squareCentre(drawing) == Vector2(100, 40))
    }

    @Test func theDistanceIsClamped() {
        let drawing = DatumLayout.onLine(
            letter: "A", foot: Vector2(0, 0), along: Vector2(1, 0), distance: 1, edgeEnds: nil, h: h, style: style)
        #expect(abs((squareCentre(drawing)?.y ?? 0) - DatumLayout.minimumDistance(h: h)) <= 1e-12)
        #expect(abs(DatumLayout.minimumDistance(h: h) - (triangleHeight + h + h)) <= 1e-12)
    }

    @Test func onAnExtensionLine() {
        let ends = (Vector2(0, 0), Vector2(40, 0))
        let drawing = DatumLayout.onLine(
            letter: "A", foot: Vector2(60, 0), along: Vector2(1, 0), distance: 10, edgeEnds: ends, h: h, style: style)
        let expected = SheetSegment.line(
            Vector2(40 + style.extensionGap, 0), Vector2(60 + 0.6 * h + style.extensionOvershoot, 0))
        #expect(drawing.segments.contains(expected))
        // A foot on the edge draws none.
        let on = DatumLayout.onLine(
            letter: "A", foot: Vector2(20, 0), along: Vector2(1, 0), distance: 10, edgeEnds: ends, h: h, style: style)
        #expect(on.segments.count == drawing.segments.count - 1)
    }

    @Test func onADimensionLine() {
        let drawing = DatumLayout.onDimensionLine(
            letter: "B", end: Vector2(120, 80), other: Vector2(80, 80), distance: 12, h: h, style: style)
        let triangle = drawing.fills[0]
        #expect(abs(triangle[0].x - 120) <= 1e-12 && abs(triangle[1].x - 120) <= 1e-12)
        #expect(abs(triangle[2].x - (120 + triangleHeight)) <= 1e-12)
        #expect(squareCentre(drawing) == Vector2(132, 80))
    }

    @Test func hangingUnderALabel() {
        let drawing = DatumLayout.hanging(letter: "C", below: Vector2(10, 20), distance: 9, h: h, style: style)
        #expect(drawing.fills[0][2] == Vector2(10, 20 - triangleHeight))
        #expect(squareCentre(drawing) == Vector2(10, 11))
    }
}
