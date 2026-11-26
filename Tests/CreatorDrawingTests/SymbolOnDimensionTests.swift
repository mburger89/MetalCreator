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

extension SymbolComposerTests {
    // MARK: On a hole callout and on a cylinder's outline

    @Test func symbolsHangOnAHoleCallout() throws {
        let view = Fixtures.makeView()
        let callout = DrawingAnnotation(
            view: view.id,
            kind: .holeCallout(HoleCallout(anchor: Fixtures.pick(part, 0), placement: DimensionPlacement(offset: 10, angle: 0.7))))
        let boxed = frame(view, .dimension(callout.id), offset: .zero)
        let marked = datum(view, .dimension(callout.id))
        let picture = Fixtures.compose(view, [callout, boxed, marked], content: Fixtures.content())
        let rect = try #require(picture.annotationReports[callout.id]?.labelRect)
        #expect(picture.annotationReports[boxed.id]?.status == .held)
        #expect(picture.annotationReports[marked.id]?.status == .held)
        // The frame stacks a text gap under the callout's text; the datum hangs below the frame, never over the callout.
        #expect(hasPoint(Fixtures.strokes(picture, of: boxed.id), Vector2(rect.min.x, rect.min.y - style.textGap)))
        let fill = try #require(picture.fills.first { $0.annotation == marked.id })
        #expect(fill.points.allSatisfy { $0.y < rect.min.y })
        // The callout moving takes both symbols along.
        let moved = DrawingAnnotation(
            id: callout.id, view: view.id,
            kind: .holeCallout(HoleCallout(anchor: Fixtures.pick(part, 0), placement: DimensionPlacement(offset: 20, angle: 0.7))))
        let again = Fixtures.compose(view, [moved, boxed, marked], content: Fixtures.content())
        let movedRect = try #require(again.annotationReports[callout.id]?.labelRect)
        #expect(movedRect != rect)
        #expect(hasPoint(Fixtures.strokes(again, of: boxed.id), Vector2(movedRect.min.x, movedRect.min.y - style.textGap)))
    }

    @Test func aFrameStandsOnACylindersOutline() throws {
        let view = Fixtures.makeView(orientation: .front)
        let facePick = try #require(part.facePick(for: FaceID(2)))
        let outline = LeaderEnd(target: .outline(facePick, side: Vector2(1, 0)), hint: Vector2(23, -5))
        let symbol = frame(view, .feature(outline))
        let picture = Fixtures.compose(view, [symbol], content: Fixtures.content())
        let report = try #require(picture.annotationReports[symbol.id])
        #expect(report.status == .held, "\(report.status)")
        guard case .attachment(let foot, let along, let ends)? = report.current?.figure else {
            Issue.record("the outline is remembered as an attachment: \(String(describing: report.current?.figure))")
            return
        }
        #expect(abs(abs(foot.x - 20) - 3) < 1e-9, "the foot is on a side of the cylinder, 3 mm from its axis: \(foot)")
        #expect(abs(along.x) < 1e-9 && abs(abs(along.y) - 1) < 1e-9, "the outline runs along the axis")
        #expect(ends.isEmpty, "an outline has no ends")
    }
}
