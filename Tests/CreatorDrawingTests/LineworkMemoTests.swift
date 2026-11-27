import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

/// The linework memo (speed plan R1, R2): a compose through it maps only the views whose inputs changed, and its picture is the
/// picture a compose without one returns.
@Suite("Linework memo")
struct LineworkMemoTests {
    typealias Fixtures = AnnotationFixtures

    /// Three projected views and two dimensions, with what a compose reads.
    struct Scene {
        var document: DrawingDocument
        var contents: [ViewID: ViewContent]
        let views: [DrawingView]
        let dimensions: [DrawingAnnotation]

        var sheet: DrawingSheet { document.sheets[0] }

        init() {
            let topology = Fixtures.topology()
            views = [
                Fixtures.makeView(center: Vector2(80, 150)), Fixtures.makeView(center: Vector2(180, 150)),
                Fixtures.makeView(center: Vector2(280, 150)),
            ]
            let pair = [Fixtures.pick(topology, 100), Fixtures.pick(topology, 103)]
            dimensions = [
                Fixtures.dimension(views[0].id, .linear(.horizontal), pair),
                Fixtures.dimension(views[1].id, .linear(.horizontal), pair, offset: 6),
            ]
            let sheet = DrawingSheet(name: "Sheet 1", views: views, annotations: dimensions)
            document = DrawingDocument(sheets: [sheet])
            contents = Dictionary(uniqueKeysWithValues: views.map { ($0.id, Fixtures.content(topology)) })
        }

        mutating func editView(_ index: Int, _ change: (inout DrawingView) -> Void) {
            var view = views[index]
            change(&view)
            document.sheets[0].setView(view)
        }

        mutating func edit(_ change: (inout DrawingSheet) -> Void) {
            change(&document.sheets[0])
        }

        func compose(_ memo: inout LineworkMemo?) -> SheetPicture {
            let sheet = self.sheet
            guard var kept = memo else {
                return SheetComposer.compose(sheet, in: document, contents: contents, facts: TitleBlockFacts())
            }
            memo = nil
            defer { memo = kept }
            return SheetComposer.compose(
                sheet, in: document, contents: contents, facts: TitleBlockFacts(), linework: &kept)
        }
    }

    /// Composes `scene` through `memo` and asserts the picture is the memo-less one; returns the memo's counts.
    private func check(_ scene: Scene, _ memo: inout LineworkMemo?) -> (mapped: Int, reused: Int) {
        let picture = scene.compose(&memo)
        var none: LineworkMemo?
        #expect(picture == scene.compose(&none), "a memo changes nothing on paper")
        return (memo?.mapped ?? 0, memo?.reused ?? 0)
    }

    @Test func aSecondComposeMapsNothing() {
        let scene = Scene()
        var memo: LineworkMemo? = LineworkMemo()
        #expect(check(scene, &memo) == (3, 0))
        let counts = check(scene, &memo)
        #expect(counts.mapped == 0)
        #expect(counts.reused == 3)
    }

    @Test func movingADimensionMapsNothing() {
        var scene = Scene()
        var memo: LineworkMemo? = LineworkMemo()
        _ = check(scene, &memo)
        var moved = scene.dimensions[0]
        if case .dimension(var dimension) = moved.kind {
            dimension.placement.offset = 25
            moved.kind = .dimension(dimension)
        }
        scene.edit { $0.setAnnotation(moved) }
        let counts = check(scene, &memo)
        #expect(counts.mapped == 0)
        #expect(counts.reused == 3)
    }

    @Test func movingAViewMapsThatView() {
        var scene = Scene()
        var memo: LineworkMemo? = LineworkMemo()
        _ = check(scene, &memo)
        var view = scene.views[1]
        view.center = Vector2(190, 160)
        scene.edit { $0.setView(view) }
        let counts = check(scene, &memo)
        #expect(counts.mapped == 1)
        #expect(counts.reused == 2)
    }

    /// One input of a view's linework, changed.
    enum Change: CaseIterable, Sendable, CustomTestStringConvertible {
        case content, hatch, hatchClips, showsHidden, showsTangent, viewScale, sheetScale, standard, sheetSize

        var testDescription: String { String(describing: self) }

        /// The views re-mapped: the one edited, or all three for a sheet-wide input.
        var mapped: Int {
            switch self {
            case .sheetScale, .standard, .sheetSize: 3
            default: 1
            }
        }

        func apply(to scene: inout Scene) {
            let id = scene.views[1].id
            switch self {
            case .content:
                var content = scene.contents[id] ?? ViewContent()
                content.projection = Projection2D(lines: [Fixtures.line(.line(Vector2(0, 0), Vector2(5, 5)), edge: 102)])
                scene.contents[id] = content
            case .hatch:
                scene.contents[id]?.hatch = [HatchRegion(part: 0, edges: [[Vector2(0, 0), Vector2(20, 0), Vector2(20, 10)]])]
            case .hatchClips:
                scene.contents[id]?.hatch = [HatchRegion(part: 0, edges: [[Vector2(0, 0), Vector2(20, 0), Vector2(20, 10)]])]
                scene.contents[id]?.hatchClips = [HatchClip(center: Vector2(10, 5), radius: 4)]
            case .showsHidden:
                scene.editView(1) { $0.showsHidden = true }
            case .showsTangent:
                scene.editView(1) { $0.showsTangent = false }
            case .viewScale:
                scene.editView(1) { $0.scale = DrawingScale(numerator: 2, denominator: 1) }
            case .sheetScale:
                scene.edit { $0.scale = DrawingScale(numerator: 1, denominator: 2) }
            case .standard:
                scene.document.settings.standard = .asme
            case .sheetSize:
                scene.edit { $0.size = .a2 }
            }
        }
    }

    @Test(arguments: Change.allCases) func eachViewInputMisses(_ change: Change) {
        var scene = Scene()
        // The hatch inputs only show on a view that already has hatch, so give the middle view some first.
        if change == .hatchClips {
            scene.contents[scene.views[1].id]?.hatch = [HatchRegion(part: 0, edges: [[Vector2(0, 0), Vector2(20, 0)]])]
        }
        var memo: LineworkMemo? = LineworkMemo()
        _ = check(scene, &memo)
        change.apply(to: &scene)
        let counts = check(scene, &memo)
        #expect(counts.mapped == change.mapped)
        #expect(counts.mapped + counts.reused == 3)
    }

    @Test func aRemovedViewLeavesTheMemo() {
        var scene = Scene()
        var memo: LineworkMemo? = LineworkMemo()
        _ = check(scene, &memo)
        let gone = scene.views[2]
        scene.edit { $0.removeView(gone.id) }
        var counts = check(scene, &memo)
        #expect(counts.mapped == 0)
        #expect(counts.reused == 2)
        // A new view under the same id, with other content, must not find the old entry.
        let again = DrawingView(
            id: gone.id, kind: .base, source: gone.source, orientation: gone.orientation, center: gone.center)
        scene.edit { $0.setView(again) }
        scene.contents[gone.id] = ViewContent(
            projection: Projection2D(lines: [Fixtures.line(.line(Vector2(0, 0), Vector2(7, 3)), edge: nil)]))
        counts = check(scene, &memo)
        #expect(counts.mapped == 1)
        #expect(counts.reused == 2)
    }

    @Test func anotherSheetDoesNotReuse() {
        let first = Scene()
        var memo: LineworkMemo? = LineworkMemo()
        _ = check(first, &memo)
        // Sheet 2 holds the same view ids, showing other content.
        var second = first
        second.document.sheets[0] = DrawingSheet(name: "Sheet 2", views: first.views)
        let other = ViewContent(projection: Projection2D(lines: [Fixtures.line(.line(Vector2(0, 0), Vector2(9, 9)), edge: nil)]))
        second.contents = Dictionary(uniqueKeysWithValues: first.views.map { ($0.id, other) })
        let counts = check(second, &memo)
        #expect(counts.mapped == 3, "other content under the same ids is mapped again")
    }
}
