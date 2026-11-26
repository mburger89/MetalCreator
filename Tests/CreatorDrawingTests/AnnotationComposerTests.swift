import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Annotation composer")
struct AnnotationComposerTests {
    private typealias Fixtures = AnnotationFixtures
    private let topology = Fixtures.topology()

    private func close(_ a: Vector2, _ b: Vector2, _ tolerance: Double = 1e-9) -> Bool { LayoutSupport.close(a, b, tolerance) }

    private func horizontal(_ view: DrawingView, offset: Double = 10, prefix: String = "") -> DrawingAnnotation {
        Fixtures.dimension(view.id, .linear(.horizontal), [Fixtures.pick(topology, 102)], offset: offset, prefix: prefix)
    }

    private let figure = AnnotationFigure.linear(points: [Vector2(0, 0), Vector2(40, 0)], direction: Vector2(1, 0))

    private func remembered(_ id: AnnotationID) -> [AnnotationID: LastGood] {
        [id: LastGood(values: [40], lines: ["40"], figure: figure)]
    }

    // MARK: Dimensions

    @Test func aHeldDimensionDrawsItsValue() throws {
        let view = Fixtures.makeView()
        let dimension = horizontal(view)
        let picture = Fixtures.compose(view, [dimension], content: Fixtures.content())
        let texts = Fixtures.texts(picture, of: dimension.id)
        #expect(texts.map(\.original) == ["40"])
        #expect(texts.allSatisfy { $0.layer == .dimension && $0.view == view.id && !$0.isLost })
        let strokes = Fixtures.strokes(picture, of: dimension.id)
        #expect(!strokes.isEmpty && strokes.allSatisfy { $0.layer == .dimension && $0.view == view.id && !$0.isLost })
        #expect(picture.fills.contains { $0.annotation == dimension.id && $0.view == view.id })
        #expect(picture.annotationReports[dimension.id]?.status == .held)
        #expect(picture.lostAnnotations.isEmpty)
    }

    @Test func itMovesWithItsView() throws {
        let first = Fixtures.makeView(center: Vector2(150, 150))
        var second = first
        second.center = Vector2(160, 150)
        let dimension = horizontal(first)
        let a = Fixtures.compose(first, [dimension], content: Fixtures.content())
        let b = Fixtures.compose(second, [dimension], content: Fixtures.content())
        let textsA = Fixtures.texts(a, of: dimension.id), textsB = Fixtures.texts(b, of: dimension.id)
        #expect(textsA.count == textsB.count && !textsA.isEmpty)
        for (p, q) in zip(textsA, textsB) { #expect(close(q.origin, p.origin + Vector2(10, 0))) }
        let fillsA = a.fills.filter { $0.annotation == dimension.id }, fillsB = b.fills.filter { $0.annotation == dimension.id }
        #expect(fillsA.count == fillsB.count && !fillsA.isEmpty)
        for (p, q) in zip(fillsA, fillsB) {
            for (x, y) in zip(p.points, q.points) { #expect(close(y, x + Vector2(10, 0))) }
        }
        let linesA = Fixtures.strokes(a, of: dimension.id).flatMap(\.segments)
        let linesB = Fixtures.strokes(b, of: dimension.id).flatMap(\.segments)
        #expect(linesA.count == linesB.count)
        for (p, q) in zip(linesA, linesB) {
            guard case let .line(p0, p1) = p, case let .line(q0, q1) = q else { continue }
            #expect(close(q0, p0 + Vector2(10, 0)) && close(q1, p1 + Vector2(10, 0)))
        }
    }

    @Test func aLostDimensionShowsItsLastValueWithAQuestionMark() throws {
        let view = Fixtures.makeView()
        let dimension = horizontal(view)
        let gone = Fixtures.topology(removing: [102])
        let picture = Fixtures.compose(view, [dimension], content: Fixtures.content(gone), remembered: remembered(dimension.id))
        let texts = Fixtures.texts(picture, of: dimension.id)
        #expect(texts.map(\.original) == ["40?"])
        #expect(texts.allSatisfy { $0.isLost })
        #expect(Fixtures.strokes(picture, of: dimension.id).allSatisfy { $0.isLost })
        #expect(picture.lostAnnotations == [dimension.id])
        let report = try #require(picture.annotationReports[dimension.id])
        #expect(report.status == .lost(.missing))
        #expect(report.label == "40?")
        #expect(report.current == nil)
        #expect(report.anchors == [.lost(.missing)] && report.firstLostAnchor == 0)
    }

    @Test func aLostDimensionFallsBackToItsSavedLastValue() {
        let view = Fixtures.makeView()
        var dimension = horizontal(view)
        dimension.last = LastGood(values: [40], lines: ["40"], figure: figure)
        let picture = Fixtures.compose(view, [dimension], content: Fixtures.content(Fixtures.topology(removing: [102])))
        #expect(Fixtures.texts(picture, of: dimension.id).map(\.original) == ["40?"])
    }

    @Test func withoutAnyLastValueItIsALoneQuestionMark() throws {
        let view = Fixtures.makeView()
        let dimension = horizontal(view)
        let picture = Fixtures.compose(view, [dimension], content: Fixtures.content(Fixtures.topology(removing: [102])))
        let texts = Fixtures.texts(picture, of: dimension.id)
        #expect(texts.map(\.original) == ["?"])
        let frame = try #require(picture.viewFrames[view.id])
        #expect(close(texts[0].origin, frame.min))
        #expect(picture.annotationReports[dimension.id]?.label == "?")
        #expect(picture.lostAnnotations == [dimension.id])
    }

    @Test func aLostOrdinateNamesItsValueNotItsOrigin() throws {
        let view = Fixtures.makeView()
        let dimension = Fixtures.dimension(view.id, .ordinate(.horizontal), [Fixtures.pick(topology, 102)])
        let last = LastGood(values: [25], lines: ["0", "25"], figure: figure)
        let drawn = Fixtures.compose(
            view, [dimension], content: Fixtures.content(Fixtures.topology(removing: [102])), remembered: [dimension.id: last])
        #expect(drawn.annotationReports[dimension.id]?.label == "25?")
        let unlisted = Fixtures.compose(
            view, [dimension], content: ViewContent(problem: DrawingProjector.removedSentence), remembered: [dimension.id: last])
        #expect(unlisted.annotationReports[dimension.id]?.label == "25?")
    }

    @Test func aRemovedSourceListsButDrawsNothing() {
        let view = Fixtures.makeView()
        let dimension = horizontal(view)
        let picture = Fixtures.compose(
            view, [dimension], content: ViewContent(problem: DrawingProjector.removedSentence),
            remembered: remembered(dimension.id))
        #expect(picture.annotationReports[dimension.id]?.status == .lost(.sourceRemoved))
        #expect(picture.annotationReports[dimension.id]?.label == "40?")
        #expect(picture.annotationReports[dimension.id]?.anchors == [])
        #expect(picture.lostAnnotations == [dimension.id])
        #expect(Fixtures.texts(picture, of: dimension.id).isEmpty)
        #expect(Fixtures.strokes(picture, of: dimension.id).isEmpty)
        #expect(picture.fills.allSatisfy { $0.annotation != dimension.id })
    }

    @Test func theReportCarriesTheCurrentFigure() throws {
        let view = Fixtures.makeView()
        let dimension = horizontal(view)
        let picture = Fixtures.compose(view, [dimension], content: Fixtures.content())
        let report = try #require(picture.annotationReports[dimension.id])
        #expect(report.current == LastGood(values: [40], lines: ["40"], figure: figure))
        #expect(report.label == "40")
        #expect(report.anchors == [.held])
        #expect(report.textCenter != nil)
        #expect(!Fixtures.texts(picture, of: dimension.id).isEmpty && report.frame.width > 0)
    }

    @Test func generalToleranceWritesNothing() {
        let view = Fixtures.makeView()
        let dimension = horizontal(view)
        let picture = Fixtures.compose(view, [dimension], content: Fixtures.content())
        #expect(Fixtures.texts(picture, of: dimension.id).count == 1)
    }

    @Test func inchesFlowThrough() {
        let view = Fixtures.makeView()
        let dimension = horizontal(view)
        let picture = Fixtures.compose(
            view, [dimension], content: Fixtures.content(), units: DocumentUnits(length: .inches, precision: 3))
        #expect(Fixtures.texts(picture, of: dimension.id).map(\.original) == ["1.575"])
    }

    @Test func viewExtentsCoverAnnotations() throws {
        let view = Fixtures.makeView()
        let dimension = horizontal(view, offset: 30)
        let picture = Fixtures.compose(view, [dimension], content: Fixtures.content())
        let frame = try #require(picture.viewFrames[view.id])
        let extent = try #require(picture.viewExtents[view.id])
        let report = try #require(picture.annotationReports[dimension.id])
        #expect(extent.max.y > frame.max.y)
        #expect(extent.min.x <= report.frame.min.x && extent.max.x >= report.frame.max.x)
        #expect(extent.min.y <= report.frame.min.y && extent.max.y >= report.frame.max.y)
        #expect(extent.min.x <= frame.min.x && extent.max.y >= frame.max.y)
    }

    // MARK: R25

    @Test func anEvaluatingViewKeepsItsDimensionsHeld() {
        let view = Fixtures.makeView()
        let dimension = horizontal(view)
        let picture = Fixtures.compose(view, [dimension], content: Fixtures.content(pending: true))
        #expect(Fixtures.texts(picture, of: dimension.id).map(\.original) == ["40"])
        #expect(Fixtures.texts(picture, of: dimension.id).allSatisfy { !$0.isLost })
        #expect(picture.lostAnnotations.isEmpty)
        #expect(picture.annotationReports[dimension.id]?.status == .held)
    }

    @Test func aFailedViewLosesItsDimensionsWithItsSentence() throws {
        let view = Fixtures.makeView()
        let dimension = horizontal(view)
        let picture = Fixtures.compose(
            view, [dimension], content: Fixtures.content(problem: "The fillet failed."), remembered: remembered(dimension.id))
        let report = try #require(picture.annotationReports[dimension.id])
        #expect(report.status == .lost(.viewFailed("The fillet failed.")))
        #expect(report.anchors.isEmpty)
        let texts = Fixtures.texts(picture, of: dimension.id)
        #expect(texts.map(\.original) == ["40?"] && texts.allSatisfy { $0.isLost })
        #expect(picture.lostAnnotations == [dimension.id])
    }

    @Test func aViewOfOnlyMeshesHasNoPart() {
        let view = Fixtures.makeView()
        let dimension = horizontal(view)
        let picture = Fixtures.compose(view, [dimension], content: ViewContent(problem: DrawingProjector.onlyMeshesSentence))
        #expect(picture.annotationReports[dimension.id]?.status == .lost(.noPart))
        #expect(picture.lostAnnotations == [dimension.id])
        #expect(Fixtures.texts(picture, of: dimension.id).isEmpty)
    }

    @Test func aViewOfCurvesOnlyHasNoPart() throws {
        let view = Fixtures.makeView()
        let dimension = horizontal(view)
        let content = ViewContent(projection: Fixtures.projection(), topology: nil)
        let picture = Fixtures.compose(view, [dimension], content: content, remembered: remembered(dimension.id))
        let report = try #require(picture.annotationReports[dimension.id])
        #expect(report.status == .lost(.noPart) && report.anchors.isEmpty)
        #expect(Fixtures.texts(picture, of: dimension.id).map(\.original) == ["40?"])
    }

    // MARK: R15

    @Test func anchorStatusesSayWhichIsLost() throws {
        let view = Fixtures.makeView()
        let dimension = Fixtures.dimension(
            view.id, .linear(.horizontal), [Fixtures.pick(topology, 100), Fixtures.pick(topology, 103)])
        let picture = Fixtures.compose(view, [dimension], content: Fixtures.content(Fixtures.topology(removing: [103])))
        let report = try #require(picture.annotationReports[dimension.id])
        #expect(report.anchors == [.held, .lost(.missing)])
        #expect(report.firstLostAnchor == 1)
        #expect(report.status == .lost(.missing))
    }

    @Test func aForeshortenedDimensionHasEveryAnchorHeld() throws {
        let view = Fixtures.makeView()
        let dimension = Fixtures.dimension(view.id, .linear(.aligned), [Fixtures.pick(topology, 104)])
        let picture = Fixtures.compose(view, [dimension], content: Fixtures.content())
        let report = try #require(picture.annotationReports[dimension.id])
        #expect(report.status == .lost(.foreshortened))
        #expect(report.anchors == [.held] && report.firstLostAnchor == nil)
    }

    @Test func aSeriesLosesAsOne() throws {
        let view = Fixtures.makeView()
        let picks = [100, 103, 102].map { Fixtures.pick(topology, $0) }
        let dimension = Fixtures.dimension(view.id, .chain(.horizontal), picks)
        let picture = Fixtures.compose(view, [dimension], content: Fixtures.content(Fixtures.topology(removing: [103])))
        #expect(picture.annotationReports[dimension.id]?.anchors == [.held, .lost(.missing), .held])
        #expect(picture.annotationReports[dimension.id]?.status == .lost(.missing))
    }

    @Test func aPrefixOutsideWinAnsiIsReplaced() {
        let view = Fixtures.makeView()
        let dimension = horizontal(view, prefix: "→")
        let picture = Fixtures.compose(view, [dimension], content: Fixtures.content())
        let texts = Fixtures.texts(picture, of: dimension.id)
        #expect(texts.map(\.run.shown) == ["? 40"])
        #expect(ReplacedTexts.collect(texts) == ["→ 40"])
    }

    @Test func aFitTheRangeRefusesIsLostWithItsSentence() throws {
        let view = Fixtures.makeView()
        let radius = DrawingAnnotation(
            view: view.id,
            kind: .dimension(
                DrawingDimension(
                    kind: .radius, anchors: [Fixtures.pick(topology, 0)], placement: DimensionPlacement(offset: 10, angle: 0),
                    tolerance: .fit(.hole(.H, grade: 7), showsDeviations: true))))
        let picture = Fixtures.compose(view, [radius], content: Fixtures.content())
        let report = try #require(picture.annotationReports[radius.id])
        #expect(report.status == .lost(.refused(DimensionLabel.fitsOnSizesOnly)))
        #expect(report.anchors == [.held])
    }
}
