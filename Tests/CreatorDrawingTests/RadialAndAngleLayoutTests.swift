import CreatorGeometry
import Foundation
import Testing

@testable import CreatorDrawing

@Suite("Radial and angle layout")
struct RadialAndAngleLayoutTests {
    private let h = LayoutSupport.h

    private func radial(
        radius: Double, isDiameter: Bool, label: String, angle: Double = 0, offset: Double = 10, standard: DrawingStandard = .iso
    ) -> AnnotationDrawing {
        SheetDimensionLayout.draw(
            .radial(center: Vector2(50, 50), radius: radius, isDiameter: isDiameter), kind: isDiameter ? .diameter : .radius,
            labels: [LayoutSupport.label(label)], placement: DimensionPlacement(offset: offset, angle: angle),
            mapping: LayoutSupport.identity, standard: standard, height: h)
    }

    @Test func aRadiusArrowPointsAtTheArc() {
        let drawing = radial(radius: 10, isDiameter: false, label: "R10")
        #expect(drawing.fills.count == 1)
        let head = drawing.fills[0]
        #expect(LayoutSupport.close(head[0], Vector2(60, 50)))
        let base = Vector2((head[1].x + head[2].x) / 2, (head[1].y + head[2].y) / 2)
        #expect(LayoutSupport.close(base, Vector2(57.5, 50)))
        #expect(LayoutSupport.hasLine(drawing, Vector2(50, 50), lineEnd(drawing)))
        #expect(drawing.texts[0].angle == 0)
        #expect(drawing.texts[0].origin.x >= 60 + 10 - 1e-9)
    }

    private func lineEnd(_ drawing: AnnotationDrawing) -> Vector2 {
        LayoutSupport.lines(drawing).first { LayoutSupport.close($0.0, Vector2(50, 50)) }?.1 ?? .zero
    }

    @Test func aDiameterInside() {
        let drawing = radial(radius: 20, isDiameter: true, label: "Ø40")
        #expect(LayoutSupport.hasLine(drawing, Vector2(30, 50), Vector2(70, 50)))
        #expect(drawing.fills.count == 2)
        let tips = drawing.fills.map { $0[0] }
        #expect(tips.contains { LayoutSupport.close($0, Vector2(30, 50)) })
        #expect(tips.contains { LayoutSupport.close($0, Vector2(70, 50)) })
        for head in drawing.fills {
            let base = Vector2((head[1].x + head[2].x) / 2, (head[1].y + head[2].y) / 2)
            #expect(abs(base.x - 50) < abs(head[0].x - 50))
        }
    }

    @Test func aSmallCircleTakesALeader() {
        let small = radial(radius: 1.5, isDiameter: true, label: "Ø3")
        #expect(small.fills.count == 1)
        #expect(LayoutSupport.close(small.fills[0][0], Vector2(51.5, 50)))
        #expect(LayoutSupport.hasLine(small, Vector2(61.5, 50), Vector2(64.5, 50)))
        // ASME leads every diameter.
        let asme = radial(radius: 20, isDiameter: true, label: "Ø40", standard: .asme)
        #expect(asme.fills.count == 1)
        #expect(LayoutSupport.close(asme.fills[0][0], Vector2(70, 50)))
        #expect(asme.texts[0].angle == 0)
        #expect(asme.texts[0].origin.x > 80)
    }

    private func angled(radius: Double, standard: DrawingStandard = .iso) -> AnnotationDrawing {
        SheetDimensionLayout.draw(
            .angle(vertex: .zero, first: [.zero, Vector2(40, 0)], second: [.zero, Vector2(0, 40)]), kind: .angle,
            labels: [LayoutSupport.label("90°")], placement: DimensionPlacement(offset: radius, angle: .pi / 4),
            mapping: LayoutSupport.identity, standard: standard, height: h)
    }

    @Test func anAngleArcSpansTheSector() {
        let drawing = angled(radius: 20)
        let arcs = drawing.segments.compactMap { segment -> (Vector2, Double, Double, Double)? in
            if case let .arc(center, radius, start, sweep) = segment { return (center, radius, start, sweep) }
            return nil
        }
        #expect(arcs.count == 1)
        #expect(arcs[0].0 == .zero && arcs[0].1 == 20 && arcs[0].2 == 0 && LayoutSupport.close(arcs[0].3, .pi / 2))
        #expect(drawing.fills.count == 2)
        // Both rays end at 40 mm, beyond the 20 mm arc: no extension lines.
        #expect(!LayoutSupport.hasLine(drawing, Vector2(20, 0), Vector2(22, 0)))
    }

    @Test func anArcBeyondTheLinesGetsExtensionLines() {
        let drawing = angled(radius: 50)
        #expect(LayoutSupport.hasLine(drawing, Vector2(40, 0), Vector2(52, 0)))
        #expect(LayoutSupport.hasLine(drawing, Vector2(0, 40), Vector2(0, 52)))
    }

    @Test func aShortArcFlipsItsArrows() {
        let drawing = angled(radius: 3)
        #expect(drawing.fills.count == 2)
        let start = drawing.fills.first { LayoutSupport.close($0[0], Vector2(3, 0)) }
        #expect(start != nil)
        let head = start ?? []
        let base = Vector2((head[1].x + head[2].x) / 2, (head[1].y + head[2].y) / 2)
        #expect(base.y < 0)
    }

    @Test func asmeAngleTextHorizontal() {
        let iso = angled(radius: 20)
        let asme = angled(radius: 20, standard: .asme)
        #expect(iso.texts[0].angle != 0)
        #expect(asme.texts[0].angle == 0)
        let middle = Vector2(20 * cos(Double.pi / 4), 20 * sin(Double.pi / 4))
        #expect(LayoutSupport.close(asme.textCenter ?? .zero, middle))
        // The arc is broken for the text: two arcs.
        let arcs = asme.segments.filter { if case .arc = $0 { true } else { false } }
        #expect(arcs.count == 2)
    }
}
