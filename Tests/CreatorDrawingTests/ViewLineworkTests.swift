import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("View linework")
struct ViewLineworkTests {
    private let style = DrawingStyle.iso

    private func line(
        _ visibility: LineVisibility, _ cls: LineClass, _ curve: ProjectedCurve = .line(Vector2(0, 0), Vector2(10, 0))
    ) -> ProjectedLine {
        ProjectedLine(visibility: visibility, lineClass: cls, curve: curve, source: nil)
    }

    private func view(hidden: Bool = false, tangent: Bool = false) -> DrawingView {
        DrawingView(
            kind: .base, source: NodeID(), orientation: .standard(.front), center: .zero, showsHidden: hidden,
            showsTangent: tangent)
    }

    @Test func classesFollowISO128() {
        let lines = [
            line(.visible, .sharp), line(.hidden, .sharp), line(.visible, .smooth), line(.hidden, .smooth),
            line(.visible, .outline), line(.visible, .sheetBoundary), line(.visible, .curve), line(.hidden, .curve),
        ]
        let projection = Projection2D(lines: lines)
        let off = ViewLinework.strokes(for: projection, view: view(), center: .zero, scale: 1, style: style)
        #expect(off.count == 4)
        #expect(off.allSatisfy { $0.layer == .visible && $0.width == style.thick && $0.pattern == .solid })
        let on = ViewLinework.strokes(
            for: projection, view: view(hidden: true, tangent: true), center: .zero, scale: 1, style: style)
        #expect(on.count == 7)
        #expect(on.filter { $0.layer == .hidden }.allSatisfy { $0.width == style.thin && $0.pattern == .hidden })
        #expect(on.filter { $0.layer == .hidden }.count == 2)
        let tangent = on.filter { $0.layer == .tangent }
        #expect(tangent.count == 1 && tangent[0].width == style.thin && tangent[0].pattern == .solid)
    }

    @Test func theBoundsCentreLandsOnTheCentre() {
        let projection = Projection2D(lines: [
            line(.visible, .sharp, .line(Vector2(10, 10), Vector2(30, 20)))
        ])
        let strokes = ViewLinework.strokes(
            for: projection, view: view(), center: Vector2(100, 100), scale: 2, style: style)
        #expect(strokes[0].segments == [.line(Vector2(80, 90), Vector2(120, 110))])
        let frame = ViewLinework.frame(for: projection, center: Vector2(100, 100), scale: 2)
        #expect(frame == Rect2D(min: Vector2(80, 90), max: Vector2(120, 110)))
    }

    @Test func arcsStayArcs() {
        let projection = Projection2D(lines: [
            line(.visible, .sharp, .arc(center: Vector2(5, 5), radius: 5, start: 0, sweep: 2 * .pi))
        ])
        let strokes = ViewLinework.strokes(for: projection, view: view(), center: .zero, scale: 3, style: style)
        guard case .arc(_, let radius, _, _) = strokes[0].segments[0] else {
            Issue.record("not an arc")
            return
        }
        #expect(radius == 15)
    }

    @Test func aViewOverrideScalesOnlyThatView() {
        var other = view()
        var overridden = view()
        overridden.scale = DrawingScale(numerator: 2, denominator: 1)
        overridden.showsLabel = true
        other.center = Vector2(60, 60)
        overridden.center = Vector2(200, 100)
        let sheet = DrawingSheet(name: "Sheet 1", views: [other, overridden])
        let projection = Projection2D(lines: [line(.visible, .sharp)])
        let contents = [
            other.id: ViewContent(projection: projection), overridden.id: ViewContent(projection: projection),
        ]
        let picture = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]), contents: contents, facts: TitleBlockFacts())
        let mine = picture.strokes.filter { $0.view == overridden.id }
        let theirs = picture.strokes.filter { $0.view == other.id }
        #expect(mine[0].bounds.width == 20)
        #expect(theirs[0].bounds.width == 10)
        #expect(picture.texts.contains { $0.view == overridden.id && $0.original == "Front (2 : 1)" })
        #expect(ViewLabel.text(for: overridden, sheet: sheet, standard: .iso) == "Front (2 : 1)")
        #expect(ViewLabel.text(for: overridden, sheet: sheet, standard: .asme) == "FRONT (2:1)")
    }

    @Test func strokesCarryTheirSource() {
        let tagged = ProjectedLine(
            visibility: .visible, lineClass: .sharp, curve: .line(Vector2(0, 0), Vector2(10, 0)), source: .edge(EdgeID(4)))
        let projection = Projection2D(lines: [tagged, line(.visible, .sharp)])
        let strokes = ViewLinework.strokes(for: projection, view: view(), center: .zero, scale: 1, style: style)
        #expect(strokes[0].source == .edge(EdgeID(4)))
        #expect(strokes[1].source == nil)
    }
}
