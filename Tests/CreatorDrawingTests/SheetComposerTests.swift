import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Sheet composer")
struct SheetComposerTests {
    private func makeView(_ x: Double) -> DrawingView {
        DrawingView(kind: .base, source: NodeID(), orientation: .standard(.front), center: Vector2(x, 150))
    }

    private let projection = Projection2D(lines: [
        ProjectedLine(visibility: .visible, lineClass: .sharp, curve: .line(Vector2(0, 0), Vector2(10, 0)), source: nil)
    ])

    @Test func aComposedSheetHasFrameTitleBlockAndViews() {
        let view = makeView(150)
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        let picture = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]), contents: [view.id: ViewContent(projection: projection)],
            facts: TitleBlockFacts())
        #expect(picture.strokes.contains { $0.layer == .frame })
        #expect(picture.strokes.contains { $0.view == view.id && $0.layer == .visible })
        #expect(picture.viewFrames[view.id] != nil)
        #expect(picture.texts.contains { $0.original == "Title" })
    }

    @Test func aViewWithoutProjectionDrawsItsFrameAndProblem() throws {
        let view = makeView(150)
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        let problem = "The Output this view showed was removed."
        let picture = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]),
            contents: [view.id: ViewContent(problem: problem)], facts: TitleBlockFacts())
        let frame = try #require(picture.viewFrames[view.id])
        let text = try #require(picture.texts.first { $0.original == problem })
        #expect(frame.min.x <= text.origin.x && text.origin.x + text.run.width <= frame.max.x)
        #expect(abs((frame.min.x + frame.max.x) / 2 - 150) < 1e-9)
        #expect(abs((frame.min.y + frame.max.y) / 2 - 150) < 1e-9)
        #expect(text.height == DrawingStyle.iso.notesHeight(for: .a3))
        #expect(abs((text.origin.x + text.run.width / 2) - 150) < 1e-9)
        #expect(frame.min.y < text.origin.y && text.origin.y < frame.max.y)
    }

    @Test func aKeptProjectionShowsItsProblemAndWarningsUnderTheFrame() throws {
        let view = makeView(150)
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        let warning = DrawingProjector.meshesSentence(count: 2)
        let content = ViewContent(projection: projection, problem: "The fillet failed.", warnings: [warning])
        let picture = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]), contents: [view.id: content], facts: TitleBlockFacts())
        let frame = try #require(picture.viewFrames[view.id])
        let problem = try #require(picture.texts.first { $0.original == "The fillet failed." })
        let warned = try #require(picture.texts.first { $0.original == warning })
        #expect(problem.isNotice && warned.isNotice)
        #expect(problem.origin.y + problem.height < frame.min.y, "under the frame")
        #expect(warned.origin.y < problem.origin.y, "the warning follows the problem")
        let file = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]), contents: [view.id: content], facts: TitleBlockFacts(), notices: false)
        #expect(!file.texts.contains { $0.isNotice }, "a file carries no notices")
        #expect(file.strokes == picture.strokes)
    }

    @Test func anEmptyViewsProblemIsANoticeAndLeavesTheFile() {
        let view = makeView(150)
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        let content = ViewContent(problem: DrawingProjector.removedSentence)
        let screen = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]), contents: [view.id: content], facts: TitleBlockFacts())
        #expect(screen.texts.filter(\.isNotice).map(\.original) == [DrawingProjector.removedSentence])
        let file = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]), contents: [view.id: content], facts: TitleBlockFacts(), notices: false)
        #expect(!file.texts.contains { $0.original == DrawingProjector.removedSentence })
    }

    @Test func aSmallLastSizeStillHoldsTheProblem() throws {
        let view = makeView(150)
        let sheet = DrawingSheet(name: "Sheet 1", views: [view])
        let problem = "The Output this view showed was removed."
        let picture = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]),
            contents: [view.id: ViewContent(problem: problem, lastSize: Vector2(10, 10))], facts: TitleBlockFacts())
        let frame = try #require(picture.viewFrames[view.id])
        let text = try #require(picture.texts.first { $0.original == problem })
        #expect(frame.min.x <= text.origin.x && text.origin.x + text.run.width <= frame.max.x)
        #expect(frame.min.y <= text.origin.y && text.origin.y + text.height <= frame.max.y)
    }

    @Test func composingIsDeterministic() {
        let views = [makeView(100), makeView(200), makeView(300)]
        let sheet = DrawingSheet(name: "Sheet 1", views: views)
        let contents = Dictionary(uniqueKeysWithValues: views.map { ($0.id, ViewContent(projection: projection)) })
        let document = DrawingDocument(sheets: [sheet])
        let first = SheetComposer.compose(sheet, in: document, contents: contents, facts: TitleBlockFacts())
        let second = SheetComposer.compose(sheet, in: document, contents: contents, facts: TitleBlockFacts())
        #expect(first == second)
        let order = first.strokes.compactMap(\.view).reduce(into: [ViewID]()) { if $0.last != $1 { $0.append($1) } }
        #expect(order == sheet.views.map(\.id))
    }

    @Test func facts() {
        let sheet = DrawingSheet(name: "Sheet 1", scale: DrawingScale(numerator: 1, denominator: 2))
        let picture = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]), contents: [:], facts: TitleBlockFacts(massText: "84 g"))
        #expect(picture.texts.contains { $0.original == "84 g" })
        #expect(picture.texts.contains { $0.original == "1 : 2" })
    }
}
