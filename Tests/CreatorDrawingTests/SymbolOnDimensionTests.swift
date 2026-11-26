import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

extension SymbolComposerTests {
    // MARK: On a dimension

    @Test func aFrameFollowsItsDimension() throws {
        let view = Fixtures.makeView()
        let dimension = linear(view)
        let symbol = frame(view, .dimension(dimension.id), offset: Vector2(1, -2))
        let picture = Fixtures.compose(view, [dimension, symbol], content: Fixtures.content())
        let rect = try #require(picture.annotationReports[dimension.id]?.labelRect)
        let topLeft = Vector2(rect.min.x, rect.min.y - style.textGap) + Vector2(1, -2)
        #expect(hasPoint(Fixtures.strokes(picture, of: symbol.id), topLeft))
        #expect(picture.annotationReports[symbol.id]?.status == .held)
        let moved = linear(view, offset: 15)
        var again = symbol
        again.id = symbol.id
        let swapped = DrawingAnnotation(id: dimension.id, view: view.id, kind: moved.kind)
        let second = Fixtures.compose(view, [swapped, again], content: Fixtures.content())
        let movedRect = try #require(second.annotationReports[dimension.id]?.labelRect)
        #expect(movedRect != rect)
        #expect(
            hasPoint(
                Fixtures.strokes(second, of: symbol.id),
                Vector2(movedRect.min.x, movedRect.min.y - style.textGap) + Vector2(1, -2)))
    }

    @Test func framesStackUnderOneDimension() throws {
        let view = Fixtures.makeView()
        let dimension = linear(view)
        let made = [frame(view, .dimension(dimension.id), offset: .zero), frame(view, .dimension(dimension.id), offset: .zero)]
        // They stack in id order.
        let (first, second) = made[0].id < made[1].id ? (made[0], made[1]) : (made[1], made[0])
        let picture = Fixtures.compose(view, [dimension, first, second], content: Fixtures.content())
        let one = Fixtures.strokes(picture, of: first.id), two = Fixtures.strokes(picture, of: second.id)
        let bottom = try #require(points(one).map(\.y).min())
        let top = try #require(points(two).map(\.y).max())
        #expect(abs((bottom - style.textGap) - top) < 1e-9)
    }

    @Test func aDatumOnADimensionLineEnd() throws {
        let view = Fixtures.makeView()
        let dimension = linear(view)
        let symbol = datum(view, .dimension(dimension.id), endIndex: 1)
        let picture = Fixtures.compose(view, [dimension, symbol], content: Fixtures.content())
        let tips = try #require(picture.annotationReports[dimension.id]?.dimensionLine)
        #expect(tips.count == 2)
        let fill = try #require(picture.fills.first { $0.annotation == symbol.id })
        let middle = (fill.points[0] + fill.points[1]) * 0.5
        #expect(close(middle, tips[1], 1e-6))
        #expect(picture.annotationReports[symbol.id]?.status == .held)
    }

    @Test func aDatumHangsWhenTheDimensionLineGoes() throws {
        let view = Fixtures.makeView()
        let ring = Fixtures.dimension(view.id, .diameter, [Fixtures.pick(part, 0)])
        let symbol = datum(view, .dimension(ring.id))
        let picture = Fixtures.compose(view, [ring, symbol], content: Fixtures.content(), standard: .asme)
        let report = try #require(picture.annotationReports[ring.id])
        #expect(report.dimensionLine == nil)
        let rect = try #require(report.labelRect)
        let fill = try #require(picture.fills.first { $0.annotation == symbol.id })
        let middle = (fill.points[0] + fill.points[1]) * 0.5
        #expect(close(middle, Vector2((rect.min.x + rect.max.x) / 2, rect.min.y), 1e-6))
        #expect(fill.points[2].y < middle.y)
        #expect(picture.annotationReports[symbol.id]?.status == .held)
    }

    @Test func anIsoDiameterAcrossItsCircleHasADimensionLine() throws {
        let figure = AnnotationFigure.radial(center: Vector2(10, 10), radius: 30, isDiameter: true)
        let drawing = SheetDimensionLayout.draw(
            figure, kind: .diameter, labels: [LayoutSupport.label("Ø60")], placement: DimensionPlacement(offset: 5, angle: 0),
            mapping: ViewMapping(scale: 1, offset: .zero), standard: .iso, height: h)
        let tips = try #require(drawing.dimensionLine)
        #expect(tips.count == 2 && close(tips[0], Vector2(40, 10)) && close(tips[1], Vector2(-20, 10)))
        let rect = try #require(drawing.labelRect)
        #expect(rect.max.x - rect.min.x > 0 && rect.max.y > rect.min.y)
    }

    @Test func aHangingDatumSitsBelowTheFrames() throws {
        let view = Fixtures.makeView()
        let ring = Fixtures.dimension(view.id, .diameter, [Fixtures.pick(part, 0)])
        let tolerance = frame(view, .dimension(ring.id), offset: .zero)
        let symbol = datum(view, .dimension(ring.id))
        let picture = Fixtures.compose(view, [ring, tolerance, symbol], content: Fixtures.content(), standard: .asme)
        let frameBottom = try #require(points(Fixtures.strokes(picture, of: tolerance.id)).map(\.y).min())
        let fill = try #require(picture.fills.first { $0.annotation == symbol.id })
        #expect(max(fill.points[0].y, fill.points[1].y) <= frameBottom + 1e-9)
    }

    @Test func aSymbolOnALostDimensionIsLost() throws {
        let view = Fixtures.makeView()
        let dimension = linear(view)
        let symbol = datum(view, .dimension(dimension.id))
        let last = LastGood(
            values: [40], lines: ["40"],
            figure: .linear(points: [Vector2(0, 0), Vector2(40, 0)], direction: Vector2(1, 0)))
        let picture = Fixtures.compose(
            view, [dimension, symbol], content: Fixtures.content(Fixtures.topology(removing: [102])), remembered: [dimension.id: last])
        #expect(picture.annotationReports[symbol.id]?.status == .lost(.missing))
        #expect(isLostEverywhere(picture, symbol.id))
        #expect(picture.lostAnnotations.contains(symbol.id))
    }

    @Test func aSymbolOnADimensionThatDrewNothingIsListed() {
        let view = Fixtures.makeView()
        let dimension = linear(view)
        let symbol = datum(view, .dimension(dimension.id))
        let picture = Fixtures.compose(
            view, [dimension, symbol], content: ViewContent(problem: DrawingProjector.removedSentence))
        #expect(picture.annotationReports[symbol.id]?.status == .lost(.sourceRemoved))
        #expect(Fixtures.strokes(picture, of: symbol.id).isEmpty && Fixtures.texts(picture, of: symbol.id).isEmpty)
        #expect(picture.lostAnnotations.contains(symbol.id))
    }

    // MARK: Reports

    @Test func warningsReachTheReport() throws {
        let view = Fixtures.makeView()
        let symbol = frame(view, datums: [DatumReference(letter: "A")])
        let picture = Fixtures.compose(view, [symbol], content: Fixtures.content())
        let report = try #require(picture.annotationReports[symbol.id])
        #expect(report.warnings == [GDTRules.formWithDatum(.flatness), GDTRules.undefined("A")])
        #expect(picture.checkedAnnotations == [symbol.id])
        let plain = Fixtures.compose(view, [datum(view)], content: Fixtures.content())
        #expect(plain.checkedAnnotations.isEmpty)
    }

    @Test func lostSymbolsReportTheirPlainText() {
        let view = Fixtures.makeView()
        let symbol = datum(view)
        let picture = Fixtures.compose(view, [symbol], content: ViewContent(problem: DrawingProjector.removedSentence))
        #expect(picture.annotationReports[symbol.id]?.label == "Datum A")
        #expect(
            AnnotationComposer.symbolOnDimensionSentence
                == "This symbol hangs on a dimension; reattach the dimension and the symbol follows it.")
    }
}
