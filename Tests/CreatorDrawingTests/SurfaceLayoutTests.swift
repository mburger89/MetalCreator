import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite struct SurfaceLayoutTests {
    let h = 2.5
    let k = DrawingSymbols.slant
    let format = NumberFormat(units: .millimetres, standard: .iso, decimalSign: .point)
    let style = AnnotationStyle.iso

    func texture(
        lay: SurfaceLay? = nil, offset: Vector2? = nil, value: Double? = 1.6
    ) -> SurfaceTexture {
        SurfaceTexture(
            requirement: SurfaceRequirement(parameter: value == nil ? nil : .ra, value: value), lay: lay,
            feature: LeaderEnd(target: .point(Vector2(0, 0)), hint: Vector2(0, 0)), offset: offset)
    }

    @Test func standsOnAHorizontalLine() {
        let drawing = SurfaceLayout.draw(texture(), foot: Vector2(10, 20), along: Vector2(1, 0), h: h, format: format, style: style)
        #expect(drawing.fills.isEmpty)
        #expect(drawing.segments.contains(.line(Vector2(10, 20), Vector2(10 + 3 * h * k, 20 + 3 * h))))
    }

    @Test func takesALeaderOtherwise() {
        let offset = Vector2(8, 10)
        let drawing = SurfaceLayout.draw(
            texture(offset: offset), foot: Vector2(10, 20), along: Vector2(1, 0), h: h, format: format, style: style)
        #expect(drawing.fills.count == 1 && drawing.fills[0][0] == Vector2(10, 20))
        let apex = Vector2(18, 30)
        #expect(drawing.segments.contains(.line(Vector2(10, 20), apex)))
        #expect(drawing.segments.contains(.line(apex, Vector2(apex.x + 3 * h * k, apex.y + 3 * h))))
    }

    @Test func aStandingSymbolOnASlantedLineTakesTheDefaultLeader() {
        let drawing = SurfaceLayout.draw(
            texture(), foot: Vector2(0, 0), along: Vector2(1, 1), h: h, format: format, style: style)
        let apex = Vector2(2 * h, 4 * h)
        #expect(drawing.fills.count == 1)
        #expect(drawing.segments.contains(.line(Vector2(0, 0), apex)))
    }

    @Test func theValueSitsUnderTheExtension() {
        let drawing = SurfaceLayout.requirement(
            SurfaceRequirement(parameter: .ra, value: 1.6), apex: Vector2(0, 0), h: h, format: format)
        let text = drawing.texts[0]
        #expect(text.original == "Ra 1.6")
        #expect(abs(text.origin.x - (3 * h * k + 0.3 * h)) <= 1e-12)
        #expect(abs(text.origin.y - (3 * h - 1.3 * h)) <= 1e-12)
        let longTop = Vector2(3 * h * k, 3 * h)
        let end = Vector2(longTop.x + 0.3 * h + text.run.width + 0.3 * h, 3 * h)
        #expect(drawing.segments.contains(.line(longTop, end)))
    }

    @Test func layTextAndGlyph() {
        let x = SurfaceLayout.draw(
            texture(lay: .crossed, value: nil), foot: Vector2(0, 0), along: Vector2(1, 0), h: h, format: format, style: style)
        #expect(x.texts.count == 1 && x.texts[0].original == "X" && x.texts[0].origin == Vector2(h, 0.2 * h))
        let perpendicular = SurfaceLayout.draw(
            texture(lay: .perpendicular, value: nil), foot: Vector2(0, 0), along: Vector2(1, 0), h: h, format: format, style: style)
        #expect(perpendicular.texts.isEmpty)
        for segment in DrawingSymbols.layPerpendicular(origin: Vector2(h, 0.2 * h), h: h) {
            #expect(perpendicular.segments.contains(segment))
        }
    }
}
