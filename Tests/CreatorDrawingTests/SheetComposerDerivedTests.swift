import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

/// Sections, details and auxiliary views on the composed sheet (DR-3 Task 6).
@Suite("Sheet composer, derived views")
struct SheetComposerDerivedTests {
    private let node = NodeID()
    private let frame = StandardOrientation.front.frame
    private let projection = Projection2D(lines: [
        ProjectedLine(visibility: .visible, lineClass: .sharp, curve: .line(Vector2(0, 0), Vector2(40, 0)), source: nil),
        ProjectedLine(visibility: .visible, lineClass: .sharp, curve: .line(Vector2(0, 0), Vector2(0, 20)), source: nil),
    ])

    private var cutter: SectionCutter {
        SectionCutter(frame: frame, points: [Vector2(5, 10), Vector2(35, 10)], viewing: Vector2(0, 1))
    }

    private struct Fixture {
        var parent: DrawingView
        var section: DrawingView
        var sheet: DrawingSheet
        var document: DrawingDocument
    }

    private func fixture(parentOrientation: ViewOrientation = .standard(.front), withParent: Bool = true) -> Fixture {
        let parent = DrawingView(kind: .base, source: node, orientation: parentOrientation, center: Vector2(100, 150))
        let section = DrawingView(
            kind: .section, source: node, orientation: .custom(SectionFrame.frame(for: cutter)), center: Vector2(100, 80),
            showsLabel: true, derivation: .section(SectionLine(parent: parent.id, cutter: cutter)), letter: "A")
        let sheet = DrawingSheet(name: "S", views: withParent ? [parent, section] : [section])
        return Fixture(parent: parent, section: section, sheet: sheet, document: DrawingDocument(sheets: [sheet]))
    }

    private func hatchContent() -> ViewContent {
        let region = HatchRegion(part: 0, edges: [[Vector2(0, 0), Vector2(40, 0), Vector2(40, 20), Vector2(0, 20)]])
        return ViewContent(projection: projection, hatch: [region])
    }

    private func compose(_ f: Fixture, notices: Bool = true) -> SheetPicture {
        var contents = [f.section.id: hatchContent()]
        if f.sheet.view(f.parent.id) != nil { contents[f.parent.id] = ViewContent(projection: projection) }
        return SheetComposer.compose(f.sheet, in: f.document, contents: contents, facts: TitleBlockFacts(), notices: notices)
    }

    @Test func aSectionDrawsItsHatch() {
        let f = fixture()
        let picture = compose(f)
        let hatch = picture.strokes.filter { $0.layer == .hatch }
        #expect(!hatch.isEmpty)
        #expect(hatch.allSatisfy { $0.view == f.section.id && $0.mark == nil })
    }

    @Test func theCuttingLineIsOnTheParent() {
        let f = fixture()
        let picture = compose(f)
        let marks = picture.strokes.filter { $0.mark == f.section.id }
        #expect(!marks.isEmpty)
        #expect(marks.allSatisfy { $0.view == f.parent.id })
        #expect(picture.texts.contains { $0.mark == f.section.id && $0.original == "A" && $0.view == f.parent.id })
        #expect(picture.fills.contains { $0.mark == f.section.id })
    }

    @Test func aTurnedParentHidesTheCuttingLine() {
        let f = fixture(parentOrientation: .standard(.top))
        let picture = compose(f)
        #expect(!picture.strokes.contains { $0.mark != nil })
        #expect(!picture.texts.contains { $0.mark != nil })
        let notice = "The view this section was cut from now looks another way, so its cutting line isn't shown."
        #expect(picture.texts.filter(\.isNotice).map(\.original) == [notice])
        #expect(picture.texts.first { $0.original == notice }?.view == f.section.id)
        let file = compose(f, notices: false)
        #expect(!file.texts.contains { $0.original == notice })
    }

    @Test func aDeletedParentLeavesANotice() {
        let f = fixture(withParent: false)
        let picture = compose(f)
        #expect(!picture.strokes.contains { $0.mark != nil })
        let notice = "The view this section was cut from was deleted, so its cutting line isn't shown."
        #expect(picture.texts.filter(\.isNotice).map(\.original) == [notice])
    }

    @Test func labelsCarryTheScale() {
        let parent = DrawingView(kind: .base, source: node, orientation: .standard(.front), center: .zero)
        let arrow = AuxiliaryArrow(parent: parent.id, parentFrame: frame, at: .zero, viewing: Vector2(0, 1))
        let circle = DetailCircle(parent: parent.id, center: .zero, radius: 3)
        let section = DrawingView(
            kind: .section, source: node, orientation: .custom(SectionFrame.frame(for: cutter)), center: .zero,
            derivation: .section(SectionLine(parent: parent.id, cutter: cutter)), letter: "A")
        let detail = DrawingView(
            kind: .detail, source: node, orientation: .standard(.front), scale: DrawingScale(numerator: 5, denominator: 1),
            center: .zero, derivation: .detail(circle), letter: "B")
        let auxiliary = DrawingView(
            kind: .auxiliary, source: node, orientation: .custom(frame), center: .zero, derivation: .auxiliary(arrow),
            letter: "C")
        let sheet = DrawingSheet(name: "S", views: [parent, section, detail, auxiliary])
        #expect(ViewLabel.text(for: section, sheet: sheet, standard: .iso) == "SECTION A-A (1 : 1)")
        #expect(ViewLabel.text(for: detail, sheet: sheet, standard: .iso) == "DETAIL B (5 : 1)")
        #expect(ViewLabel.text(for: auxiliary, sheet: sheet, standard: .iso) == "VIEW C (1 : 1)")
        #expect(ViewLabel.text(for: section, sheet: sheet, standard: .asme) == "SECTION A-A (1:1)")
        #expect(ViewLabel.text(for: parent, sheet: sheet, standard: .iso) == "Front")
    }

    @Test func aDetailDrawsItsBoundary() throws {
        let parent = DrawingView(kind: .base, source: node, orientation: .standard(.front), center: Vector2(100, 150))
        let circle = DetailCircle(parent: parent.id, center: Vector2(20, 10), radius: 6)
        let detail = DrawingView(
            kind: .detail, source: node, orientation: .standard(.front), scale: DrawingScale(numerator: 5, denominator: 1),
            center: Vector2(250, 150), derivation: .detail(circle), letter: "B")
        let sheet = DrawingSheet(name: "S", views: [parent, detail])
        let content = ViewContent(
            projection: projection, framing: Rect2D(min: Vector2(14, 4), max: Vector2(26, 16)))
        let picture = SheetComposer.compose(
            sheet, in: DrawingDocument(sheets: [sheet]),
            contents: [parent.id: ViewContent(projection: projection), detail.id: content], facts: TitleBlockFacts())
        let boundary = try #require(picture.strokes.first { $0.mark == detail.id && $0.view == detail.id })
        #expect(boundary.segments == [.arc(center: Vector2(250, 150), radius: 30, start: 0, sweep: 2 * .pi)])
        let ring = try #require(picture.strokes.first { $0.mark == detail.id && $0.view == parent.id })
        #expect(ring.layer == .dimension)
        #expect(picture.texts.contains { $0.mark == detail.id && $0.original == "B" })
    }

    @Test func extentsCoverTheMarks() throws {
        let f = fixture()
        let picture = compose(f)
        let extents = try #require(picture.viewExtents[f.parent.id])
        let frameBox = try #require(picture.viewFrames[f.parent.id])
        for stroke in picture.strokes where stroke.mark == f.section.id && stroke.view == f.parent.id {
            #expect(extents.union(stroke.bounds) == extents)
        }
        for text in picture.texts where text.mark == f.section.id {
            #expect(extents.contains(text.origin))
        }
        #expect(extents.height > frameBox.height, "the arrows reach past the view")
    }
}
