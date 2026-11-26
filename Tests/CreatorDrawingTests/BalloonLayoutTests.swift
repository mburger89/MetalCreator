import CreatorGeometry
import Foundation
import Testing

@testable import CreatorDrawing

/// A balloon's circle, number and leader (DR-5 R4), h = 2.5.
@Suite("Balloon layout")
struct BalloonLayoutTests {
    private let h = 2.5
    private let style = AnnotationStyle.iso
    private let center = Vector2(50, 40)

    private func close(_ a: Vector2, _ b: Vector2) -> Bool { LayoutSupport.close(a, b, 1e-9) }

    private func circle(_ drawing: AnnotationDrawing) -> (center: Vector2, radius: Double)? {
        for segment in drawing.segments {
            if case let .arc(c, r, _, sweep) = segment, abs(sweep - 2 * .pi) < 1e-9 { return (c, r) }
        }
        return nil
    }

    @Test func theCircleAndNumber() throws {
        let drawing = BalloonLayout.draw(number: "1", center: center, foot: nil, h: h, style: style)
        let ring = try #require(circle(drawing))
        #expect(close(ring.center, center) && abs(ring.radius - 5) < 1e-9)
        let text = try #require(drawing.texts.first)
        #expect(text.original == "1" && abs(text.height - 5) < 1e-9)
        #expect(abs(text.origin.x + text.run.width / 2 - center.x) < 1e-9)
        #expect(abs(text.origin.y + text.height / 2 - center.y) < 1e-9)
    }

    @Test func aWideNumberWidensTheCircle() throws {
        let drawing = BalloonLayout.draw(number: "123", center: center, foot: nil, h: h, style: style)
        let text = try #require(drawing.texts.first)
        let ring = try #require(circle(drawing))
        #expect(abs(ring.radius - (text.run.width / 2 + 0.5 * h)) < 1e-9)
        #expect(ring.radius > 5)
    }

    @Test func theLeaderStartsOnTheCircle() throws {
        let foot = Vector2(80, 80)
        let drawing = BalloonLayout.draw(number: "1", center: center, foot: foot, h: h, style: style)
        var start: Vector2?
        for segment in drawing.segments {
            if case let .line(a, _) = segment { start = a }
        }
        let unit = (foot - center) * (1 / (foot - center).length)
        let begin = try #require(start)
        #expect(close(begin, center + unit * 5))
        let arrow = try #require(drawing.fills.first)
        #expect(close(arrow[0], foot))
    }

    @Test func aFootInsideTheCircleDrawsNoLeader() {
        let drawing = BalloonLayout.draw(number: "1", center: center, foot: center + Vector2(2, 1), h: h, style: style)
        #expect(drawing.fills.isEmpty)
        #expect(!drawing.segments.contains { if case .line = $0 { true } else { false } })
    }

    @Test func everythingIsOnTheDimensionLayer() {
        let view = ViewID()
        let context = AnnotationContext(
            view: view, center: .zero, mapping: nil, viewFrame: Rect2D(min: .zero, max: .zero), projection: nil,
            state: .unlisted(.noPart), standard: .iso, style: style, drawingStyle: .of(.iso), height: h)
        let drawing = BalloonLayout.draw(number: "1", center: center, foot: Vector2(80, 80), h: h, style: style)
        let made = AnnotationComposer.tagged(drawing, annotation: AnnotationID(), context: context, isLost: false)
        #expect(!made.strokes.isEmpty && made.strokes.allSatisfy { $0.layer == .dimension })
        #expect(!made.texts.isEmpty && made.texts.allSatisfy { $0.layer == .dimension })
        #expect(!made.fills.isEmpty && made.fills.allSatisfy { $0.layer == .dimension })
    }
}
