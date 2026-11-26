import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

@MainActor
@Suite("View tools")
struct ViewToolTests {
    private func harness(
        views: [DrawingView] = [], settings: DrawingSettings = DrawingSettings(), sources: [DrawingSourceOption]? = nil
    ) -> (EditorHarness, DrawingSheet) {
        let sheet = DrawingSheet(name: "Sheet 1", views: views)
        let h = EditorHarness(
            document: EditorDocuments.document([sheet], settings: settings), sheet: sheet.id,
            sources: sources ?? EditorHarness.sources())
        return (h, sheet)
    }

    @Test func aBaseViewIsPlacedAtTheClick() throws {
        let (h, _) = harness()
        h.model.press(.baseView)
        h.click(150, 150)
        #expect(h.log.commits.map(\.name) == ["Add View"])
        let view = try #require(h.model.document.sheets[0].views.first)
        #expect(view.kind == .base)
        #expect(view.source == h.sources[0].id)
        #expect(view.orientation == .standard(.front))
        #expect(abs(view.center.x - 150) < 1e-9 && abs(view.center.y - 150) < 1e-9)
        #expect(h.model.selection == [view.id])
    }

    @Test func theFirstViewSetsTheSheetScale() throws {
        let big = DrawingSourceOption(
            id: NodeID(), name: "Big", bounds: BoundingBox(min: Vector3(0, 0, 0), max: Vector3(400, 100, 200)))
        let (h, sheet) = harness(sources: [big])
        h.model.press(.baseView)
        h.click(150, 150)
        #expect(h.log.commits.count == 1)
        let extents = ViewExtents.of(try #require(big.bounds), frame: StandardOrientation.front.frame)
        let area = DrawingArea.rect(for: sheet, standard: .iso)
        let expected = ScaleChooser.firstScale(extents: extents, area: area)
        #expect(h.model.document.sheets[0].scale == expected)
        #expect(expected != DrawingScale(numerator: 1, denominator: 1))
    }

    @Test func aSecondViewKeepsTheScale() throws {
        let existing = EditorDocuments.view(at: Vector2(100, 150))
        var sheet = DrawingSheet(name: "Sheet 1", views: [existing])
        sheet.scale = DrawingScale(numerator: 1, denominator: 5)
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id)
        h.model.press(.baseView)
        h.click(250, 150)
        #expect(h.model.document.sheets[0].scale == DrawingScale(numerator: 1, denominator: 5))
        #expect(h.model.document.sheets[0].views.count == 2)
    }

    @Test func noSourceRefuses() throws {
        let (h, _) = harness(sources: [])
        h.model.press(.baseView)
        h.click(150, 150)
        #expect(h.model.refusal == "Add an Output node and wire the part into it first.")
        #expect(h.log.commits.isEmpty)
    }

    private func drop(
        _ h: EditorHarness, parent: DrawingView, by offset: Vector2
    ) {
        let start = parent.center
        h.model.press(.projectedView)
        h.model.pointerDown(at: h.canvas(start.x, start.y), modifiers: [])
        h.model.pointerDragged(to: h.canvas(start.x + offset.x / 2, start.y + offset.y / 2))
        h.model.pointerDragged(to: h.canvas(start.x + offset.x, start.y + offset.y))
        h.model.pointerUp(at: h.canvas(start.x + offset.x, start.y + offset.y))
    }

    @Test func aProjectedViewIsPlacedByDragging() throws {
        let parent = EditorDocuments.view(at: Vector2(150, 150))
        let (h, _) = harness(views: [parent])
        drop(h, parent: parent, by: Vector2(100, 10))
        #expect(h.log.commits.map(\.name) == ["Add View"])
        let made = try #require(h.model.document.sheets[0].views.first { $0.kind == .projected })
        #expect(made.orientation.frame.direction == Vector3(1, 0, 0))
        #expect(made.alignment == ViewAlignment(parent: parent.id, axis: .horizontal))
        #expect(abs(made.center.y - 150) < 1e-9)
        #expect(abs(made.center.x - 250) < 1e-9)
        #expect(made.source == parent.source)
    }

    @Test func thirdAngleDropAbove() throws {
        let parent = EditorDocuments.view(at: Vector2(150, 150))
        let (h, _) = harness(views: [parent], settings: DrawingSettings(standard: .asme))
        drop(h, parent: parent, by: Vector2(5, 90))
        let made = try #require(h.model.document.sheets[0].views.first { $0.kind == .projected })
        #expect(made.orientation.frame == StandardOrientation.top.frame)
        #expect(made.alignment == ViewAlignment(parent: parent.id, axis: .vertical))
        #expect(abs(made.center.x - 150) < 1e-9)
    }

    @Test func anIsometricParentRefuses() throws {
        let parent = EditorDocuments.view(at: Vector2(150, 150), orientation: .isometricFrontRight)
        let (h, _) = harness(views: [parent])
        drop(h, parent: parent, by: Vector2(100, 0))
        #expect(h.model.refusal == "A projected view comes from a front, side, top or bottom view, not an isometric one.")
        #expect(h.log.commits.isEmpty)
    }

    @Test func escapeCancelsTheTool() throws {
        let (h, _) = harness()
        h.model.press(.baseView)
        #expect(h.model.keyPressed(.escape))
        #expect(h.model.tool == .select)
        #expect(!h.model.keyPressed(.escape))
    }

    // MARK: Projected views of derived views (plan R11)

    private func derivedParent(_ kind: ViewKind, _ derivation: (ViewID) -> ViewDerivation, orientation: ViewOrientation) -> (
        EditorHarness, DrawingView
    ) {
        let base = EditorDocuments.view(at: Vector2(60, 150))
        let parent = DrawingView(
            kind: kind, source: base.source, orientation: orientation, center: Vector2(150, 150), derivation: derivation(base.id),
            letter: "A")
        let sheet = DrawingSheet(name: "Sheet 1", views: [base, parent])
        return (EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id), parent)
    }

    @Test func aProjectedViewOfADetailIsRefused() throws {
        let (h, parent) = derivedParent(
            .detail, { .detail(DetailCircle(parent: $0, center: .zero, radius: 5)) }, orientation: .standard(.front))
        drop(h, parent: parent, by: Vector2(100, 0))
        #expect(h.model.refusal == "A projected view comes from a whole view, not a detail.")
        #expect(h.log.commits.isEmpty)
    }

    @Test func aProjectedViewOfAnAuxiliaryViewIsRefused() throws {
        let frame = ProjectionFrame.make(direction: Vector3(0.6, 0.8, 0), up: Vector3(0, 0, 1))!
        let (h, parent) = derivedParent(
            .auxiliary,
            { .auxiliary(AuxiliaryArrow(parent: $0, parentFrame: StandardOrientation.top.frame, at: .zero, viewing: Vector2(0.6, 0.8))) },
            orientation: .custom(frame))
        drop(h, parent: parent, by: Vector2(100, 0))
        #expect(
            h.model.refusal
                == "A projected view comes from a view that looks along an axis, not from an auxiliary view or a slanted section.")
        #expect(h.log.commits.isEmpty)
    }

    private func section(slanted: Bool) -> (EditorHarness, DrawingView) {
        let base = EditorDocuments.view(at: Vector2(60, 150), orientation: .top)
        let end = slanted ? Vector2(10, 5) : Vector2(10, 0)
        let t = end * (1 / end.length)
        let cutter = SectionCutter(
            frame: base.orientation.frame, points: [.zero, end], viewing: Vector2(-t.y, t.x))
        let parent = DrawingView(
            kind: .section, source: base.source, orientation: .custom(SectionFrame.frame(for: cutter)), center: Vector2(150, 150),
            derivation: .section(SectionLine(parent: base.id, cutter: cutter)), letter: "A")
        let sheet = DrawingSheet(name: "Sheet 1", views: [base, parent])
        return (EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id), parent)
    }

    @Test func aProjectedViewOfASlantedSectionIsRefused() throws {
        let (h, parent) = section(slanted: true)
        drop(h, parent: parent, by: Vector2(100, 0))
        #expect(
            h.model.refusal
                == "A projected view comes from a view that looks along an axis, not from an auxiliary view or a slanted section.")
        #expect(h.log.commits.isEmpty)
    }

    @Test func aProjectedViewOfAStraightSectionIsAllowed() throws {
        let (h, parent) = section(slanted: false)
        drop(h, parent: parent, by: Vector2(100, 0))
        #expect(h.log.commits.map(\.name) == ["Add View"])
        let made = try #require(h.model.document.sheets[0].views.first { $0.kind == .projected })
        #expect(made.alignment?.parent == parent.id)
        #expect(!h.model.document.sheets[0].isPictorial(made))
    }
}
