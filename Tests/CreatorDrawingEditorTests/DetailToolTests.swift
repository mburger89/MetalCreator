import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The Detail tool: press for the centre, drag for the radius, release, then a click places the view (plan R8, R13).
@MainActor
@Suite("Detail tool")
struct DetailToolTests {
    typealias Fixtures = AnnotationEditorFixtures

    private func open(scale: DrawingScale? = nil, units: DocumentUnits = .millimetres) -> OpenedView {
        let view = EditorDocuments.view(at: Fixtures.centre, orientation: .top)
        var sheet = DrawingSheet(name: "Sheet 1", views: [view])
        if let scale { sheet.scale = scale }
        let content = Fixtures.top()
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id, units: units, contents: [view.id: content])
        h.model.transform = SheetTransform(offset: Vector2(0, 297), zoom: 1)
        let mapping = ViewMapping.of(content: content, center: Fixtures.centre, scale: sheet.scale.value)!
        return OpenedView(h: h, view: view, mapping: mapping, content: content)
    }

    private func drag(_ o: OpenedView, from a: Vector2, to b: Vector2) {
        o.h.model.pointerDown(at: o.h.canvas(a.x, a.y), modifiers: [])
        let mid = (a + b) * 0.5
        o.h.model.pointerDragged(to: o.h.canvas(mid.x, mid.y))
        o.h.model.pointerDragged(to: o.h.canvas(b.x, b.y))
        o.h.model.pointerUp(at: o.h.canvas(b.x, b.y))
    }

    private func detail(_ o: OpenedView) -> DrawingView? { o.h.model.document.sheets[0].views.first { $0.kind == .detail } }

    private func circled(_ o: OpenedView) {
        o.h.model.press(.detail)
        let centre = o.at(30, 10)
        drag(o, from: centre, to: centre + Vector2(6, 0))
    }

    @Test func pressDragReleaseThenClick() throws {
        let o = open()
        circled(o)
        let draft = try #require(o.h.model.detailDraft)
        #expect(draft.isFinished)
        #expect(draft.parent == o.view.id)
        #expect(abs(draft.radius - 6) < 1e-6)
        #expect(o.h.log.commits.isEmpty)
        o.click(Vector2(250, 100))
        #expect(o.h.log.commits.map(\.name) == ["Add View"])
        let made = try #require(detail(o))
        #expect(made.scale == DrawingScale(numerator: 2, denominator: 1))
        #expect(made.letter == "A")
        #expect(made.showsLabel)
        #expect(made.alignment == nil)
        #expect(made.orientation == o.view.orientation)
        #expect(made.source == o.view.source)
        #expect(abs(made.center.x - 250) < 1e-9 && abs(made.center.y - 100) < 1e-9)
        guard case .detail(let circle)? = made.derivation else {
            Issue.record("no derivation")
            return
        }
        #expect(circle.parent == o.view.id)
        #expect(abs(circle.radius - 6) < 1e-6)
        #expect(abs(circle.center.x - 30) < 1e-6 && abs(circle.center.y - 10) < 1e-6)
        #expect(o.h.model.selection == [made.id])
        #expect(o.h.model.detailDraft == nil)
    }

    @Test func theDefaultScaleIsTwiceTheParents() throws {
        for (parent, expected) in [((2, 1), (5, 1)), ((50, 1), (50, 1))] {
            let o = open(scale: DrawingScale(numerator: parent.0, denominator: parent.1))
            circled(o)
            o.click(Vector2(250, 100))
            let made = try #require(detail(o))
            #expect(made.scale == DrawingScale(numerator: expected.0, denominator: expected.1))
        }
    }

    @Test func aTinyCircleIsRefused() throws {
        let o = open()
        o.h.model.press(.detail)
        let centre = o.at(30, 10)
        drag(o, from: centre, to: centre + Vector2(1, 0))
        #expect(o.h.model.refusal == "Drag out the detail's circle from its centre.")
        #expect(o.h.model.detailDraft == nil)
        #expect(o.h.log.commits.isEmpty)
    }

    private func placed(_ o: OpenedView) throws -> DrawingView {
        circled(o)
        o.click(Vector2(250, 100))
        o.h.log.commits.removeAll()
        o.h.model.press(.select)
        o.h.model.selection = []
        return try #require(detail(o))
    }

    @Test func radiusIsChangeDetailCircle() throws {
        let o = open(units: DocumentUnits(length: .inches))
        let made = try placed(o)
        o.h.model.setDetailRadius(0.5, of: made.id)
        #expect(o.h.log.commits.map(\.name) == ["Change Detail Circle"])
        guard case .detail(let circle)? = o.h.model.document.sheets[0].view(made.id)?.derivation else {
            Issue.record("no derivation")
            return
        }
        #expect(abs(circle.radius - 12.7) < 1e-9)
        for bad in [0.0, -1.0] {
            o.h.model.setDetailRadius(bad, of: made.id)
            #expect(o.h.model.refusal == "A detail's radius is a length greater than 0.")
        }
        #expect(o.h.log.commits.count == 1)
    }

    @Test func draggingTheCircleMovesIt() throws {
        let o = open()
        let made = try placed(o)
        let on = o.at(36, 10)
        o.h.model.pointerDown(at: o.h.canvas(on.x, on.y), modifiers: [])
        #expect(o.h.model.selection == [made.id])
        o.h.model.pointerDragged(to: o.h.canvas(on.x - 2, on.y + 1))
        o.h.model.pointerDragged(to: o.h.canvas(on.x - 4, on.y + 2))
        o.h.model.pointerUp(at: o.h.canvas(on.x - 4, on.y + 2))
        #expect(Set(o.h.log.commits.map(\.name)) == ["Move Detail Circle"])
        #expect(Set(o.h.log.commits.compactMap(\.coalescingKey)).count == 1)
        guard case .detail(let circle)? = o.h.model.document.sheets[0].view(made.id)?.derivation else {
            Issue.record("no derivation")
            return
        }
        #expect(abs(circle.center.x - 26) < 1e-6 && abs(circle.center.y - 12) < 1e-6)
        #expect(abs(circle.radius - 6) < 1e-6)
    }

    @Test func dragsDivideByTheParentsScale() throws {
        let o = open(scale: DrawingScale(numerator: 2, denominator: 1))
        circled(o)
        let draft = try #require(o.h.model.detailDraft)
        #expect(abs(draft.radius - 3) < 1e-6)
    }

    @Test func theEKeyChoosesTheTool() throws {
        #expect(SheetCanvasInput.key("e", modifiers: []) == .tool(.detail))
    }

    @Test func parentEditsCarryToDetails() throws {
        // base <- detail <- detail of that detail; base <- section (frame stored); base <- auxiliary (frame stored);
        // section <- detail of the section.
        let base = EditorDocuments.view(at: Vector2(100, 150))
        func derived(_ kind: ViewKind, _ derivation: ViewDerivation, letter: String, orientation: ViewOrientation) -> DrawingView {
            DrawingView(
                kind: kind, source: base.source, orientation: orientation, center: Vector2(200, 150), derivation: derivation,
                letter: letter)
        }
        let first = derived(
            .detail, .detail(DetailCircle(parent: base.id, center: .zero, radius: 5)), letter: "A", orientation: base.orientation)
        let second = derived(
            .detail, .detail(DetailCircle(parent: first.id, center: .zero, radius: 2)), letter: "B", orientation: base.orientation)
        let cutter = SectionCutter(
            frame: base.orientation.frame, points: [Vector2(0, 0), Vector2(10, 0)], viewing: Vector2(0, -1))
        let section = derived(
            .section, .section(SectionLine(parent: base.id, cutter: cutter)), letter: "C",
            orientation: .custom(SectionFrame.frame(for: cutter)))
        let ofSection = derived(
            .detail, .detail(DetailCircle(parent: section.id, center: .zero, radius: 2)), letter: "D",
            orientation: section.orientation)
        let aux = derived(
            .auxiliary,
            .auxiliary(AuxiliaryArrow(parent: base.id, parentFrame: base.orientation.frame, at: .zero, viewing: Vector2(0, 1))),
            letter: "E", orientation: .custom(SectionFrame.frame(for: cutter)))
        let sheet = DrawingSheet(name: "Sheet 1", views: [base, first, second, section, ofSection, aux])
        let sources = EditorHarness.sources()
        let h = EditorHarness(document: EditorDocuments.document([sheet]), sheet: sheet.id, sources: sources)

        h.model.setOrientation(.top, of: base.id)
        #expect(h.log.commits.map(\.name) == ["Change View"])
        var now = h.model.document.sheets[0]
        #expect(now.view(base.id)?.orientation == .standard(.top))
        #expect(now.view(first.id)?.orientation == .standard(.top))
        #expect(now.view(second.id)?.orientation == .standard(.top))
        #expect(now.view(section.id)?.orientation == section.orientation)
        #expect(now.view(ofSection.id)?.orientation == section.orientation)
        #expect(now.view(aux.id)?.orientation == aux.orientation)

        h.model.setSource(sources[1].id, of: base.id)
        #expect(h.log.commits.map(\.name) == ["Change View", "Change View"])
        now = h.model.document.sheets[0]
        for id in [base.id, first.id, second.id, section.id, ofSection.id, aux.id] {
            #expect(now.view(id)?.source == sources[1].id)
        }
        // One undo restores every one: the step before this one holds the old sources.
        let before = h.log.commits[0].document.sheets[0]
        for id in [base.id, first.id, second.id, section.id, ofSection.id, aux.id] {
            #expect(before.view(id)?.source == base.source)
        }
    }
}
