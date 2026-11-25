import CreatorGeometry
import CreatorKernel
import MetalUI
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The annotation tools: picking on a view's lines, placing, refusals, the draft that follows the pointer and the keys.
@MainActor
@Suite("Annotation tools")
struct AnnotationToolTests {
    typealias Fixtures = AnnotationEditorFixtures
    private typealias Opened = OpenedView

    private func open(
        _ content: ViewContent, orientation: StandardOrientation, zoom: Double = 1,
        annotations: (ViewID) -> [DrawingAnnotation] = { _ in [] }, units: DocumentUnits = .millimetres
    ) -> Opened {
        Opened.make(content, orientation: orientation, zoom: zoom, annotations: annotations, units: units)
    }

    private func at(_ o: Opened, _ x: Double, _ y: Double) -> Vector2 { o.at(x, y) }

    private func click(_ o: Opened, _ point: Vector2, _ modifiers: SheetModifiers = []) { o.click(point, modifiers) }

    private func dimension(_ h: EditorHarness) throws -> DrawingDimension {
        let annotation = try #require(h.model.document.sheets[0].annotations.first)
        guard case .dimension(let dimension) = annotation.kind else {
            Issue.record("not a dimension: \(annotation.kind)")
            throw CancellationError()
        }
        return dimension
    }

    // MARK: Dimensions

    @Test func oneLineThenEmptySpacePlacesItsLength() async throws {
        let o = open(try await Fixtures.plate(.front), orientation: .front)
        let bounds = try #require(o.content.projection?.bounds)
        o.h.model.press(.dimension)
        let bottom = at(o, bounds.center.x, bounds.min.y)
        click(o, bottom)
        #expect(o.h.model.picks.count == 1)
        #expect(o.h.log.commits.isEmpty, "a pick is not an edit")
        click(o, bottom - Vector2(0, 8))
        #expect(o.h.log.commits.map(\.name) == ["Add Dimension"])
        let made = try dimension(o.h)
        #expect(made.kind == .linear(.horizontal))
        #expect(made.anchors.count == 1)
        guard case .edge = made.anchors[0] else {
            Issue.record("expected an edge anchor: \(made.anchors)")
            return
        }
        #expect(abs(made.placement.offset - (-8)) < 1e-6)
        #expect(o.h.model.picks.isEmpty)
        let id = try #require(o.h.model.document.sheets[0].annotations.first?.id)
        #expect(o.h.model.selectedAnnotations == [id])
        #expect(o.h.model.picture?.annotationReports[id]?.status == .held)
    }

    @Test func twoCornersByPlacement() async throws {
        let o = open(try await Fixtures.plate(.front), orientation: .front)
        let bounds = try #require(o.content.projection?.bounds)
        o.h.model.press(.dimension)
        click(o, at(o, bounds.min.x, bounds.min.y) + Vector2(0.3, 0.2))
        click(o, at(o, bounds.max.x, bounds.min.y) + Vector2(-0.3, 0.2))
        #expect(o.h.model.picks.count == 2)
        click(o, at(o, bounds.center.x, bounds.max.y + 8))
        #expect(o.h.log.commits.map(\.name) == ["Add Dimension"])
        let made = try dimension(o.h)
        #expect(made.kind == .linear(.horizontal))
        #expect(made.anchors.count == 2)
        for anchor in made.anchors {
            guard case .corner = anchor else {
                Issue.record("expected corners: \(made.anchors)")
                return
            }
        }
    }

    @Test func shiftMakesItAligned() async throws {
        let o = open(try await Fixtures.plate(.front), orientation: .front)
        let bounds = try #require(o.content.projection?.bounds)
        o.h.model.press(.dimension)
        click(o, at(o, bounds.min.x, bounds.min.y) + Vector2(0.3, 0.2))
        click(o, at(o, bounds.max.x, bounds.max.y) + Vector2(-0.3, -0.2))
        click(o, at(o, bounds.center.x, bounds.max.y + 8), [.shift])
        #expect(try dimension(o.h).kind == .linear(.aligned))
    }

    @Test func aCircleIsADiameterAtOnce() throws {
        let o = open(Fixtures.top(), orientation: .top, zoom: 4)
        o.h.model.press(.dimension)
        click(o, at(o, 23, 10))
        #expect(o.h.model.picks.count == 1, "\(o.h.model.refusal ?? "")")
        click(o, at(o, 26, 14))
        #expect(o.h.log.commits.map(\.name) == ["Add Dimension"])
        #expect(try dimension(o.h).kind == .diameter)
    }

    @Test func aBaselineCollectsUntilPlaced() throws {
        let o = open(Fixtures.top(), orientation: .top, zoom: 4)
        o.h.model.press(.baselineDimension)
        click(o, at(o, 0.2, 0.2))
        click(o, at(o, 20, 15))
        let early = at(o, 20, 28)
        click(o, early)
        #expect(o.h.model.refusal == DimensionInference.seriesNeedsSentence)
        #expect(o.h.log.commits.isEmpty)
        #expect(o.h.model.picks.count == 2, "the picks stay for the next click")
        click(o, at(o, 30, 5))
        click(o, at(o, 40, 10))
        #expect(o.h.model.picks.count == 4)
        click(o, early)
        #expect(o.h.log.commits.map(\.name) == ["Add Dimension"])
        let made = try dimension(o.h)
        #expect(made.kind == .baseline(.horizontal))
        #expect(made.anchors.count == 4)
    }

    @Test func anOrdinateTakesAnOrigin() throws {
        let o = open(Fixtures.top(), orientation: .top, zoom: 4)
        o.h.model.press(.ordinateDimension)
        click(o, at(o, 0.2, 0.2))
        click(o, at(o, 20, -8))
        #expect(o.h.model.refusal == DimensionInference.ordinateNeedsSentence)
        click(o, at(o, 40, 10))
        click(o, at(o, 20, -8))
        #expect(o.h.log.commits.map(\.name) == ["Add Dimension"])
        let made = try dimension(o.h)
        #expect(made.kind == .ordinate(.horizontal))
        #expect(made.anchors.count == 2)
    }

    @Test func aChamferNeedsTwoLines() throws {
        let o = open(Fixtures.top(), orientation: .top, zoom: 4)
        o.h.model.press(.chamferDimension)
        click(o, at(o, 7.5, 7.5))
        click(o, at(o, 26, 17))
        #expect(o.h.model.refusal == DimensionInference.chamferSentence)
        #expect(o.h.log.commits.isEmpty)
        click(o, at(o, 10, 0))
        click(o, at(o, 26, 17))
        #expect(o.h.log.commits.map(\.name) == ["Add Dimension"])
        #expect(try dimension(o.h).kind == .chamfer)
    }

    @Test func aHoleCalloutReadsTheHole() throws {
        let o = open(Fixtures.top(), orientation: .top, zoom: 4)
        o.h.model.press(.holeCallout)
        click(o, at(o, 23, 10))
        #expect(o.h.model.picks.count == 1, "\(o.h.model.refusal ?? "")")
        click(o, at(o, 26, 14))
        #expect(o.h.log.commits.map(\.name) == ["Add Hole Callout"])
        let annotation = try #require(o.h.model.document.sheets[0].annotations.first)
        guard case .holeCallout = annotation.kind else {
            Issue.record("expected a hole callout: \(annotation.kind)")
            return
        }
        let report = try #require(o.h.model.picture?.annotationReports[annotation.id])
        #expect(report.status == .held)
        #expect(report.label.contains("THRU"))
    }

    @Test func aCentreMarkCommitsOnOnePick() throws {
        let o = open(Fixtures.top(), orientation: .top, zoom: 4)
        o.h.model.press(.centreMark)
        click(o, at(o, 23, 10))
        #expect(o.h.log.commits.map(\.name) == ["Add Centre Mark"])
        let annotation = try #require(o.h.model.document.sheets[0].annotations.first)
        guard case .centreMark = annotation.kind else {
            Issue.record("expected a centre mark: \(annotation.kind)")
            return
        }
        #expect(o.h.model.picks.isEmpty)
    }

    @Test func aCentreLineOnAnOutline() throws {
        let o = open(Fixtures.front(), orientation: .front, zoom: 4)
        o.h.model.press(.centreLine)
        click(o, at(o, 23, -10))
        #expect(o.h.log.commits.map(\.name) == ["Add Centre Line"], "\(o.h.model.refusal ?? "")")
        let annotation = try #require(o.h.model.document.sheets[0].annotations.first)
        guard case .centreLine(let line) = annotation.kind, case .axis = line.anchor else {
            Issue.record("expected a centre line on an axis: \(annotation.kind)")
            return
        }
    }

    // MARK: Refusals

    @Test func isometricRefusesTheDimensionTool() async throws {
        let o = open(try await Fixtures.plate(.front), orientation: .isometricFrontRight)
        let bounds = try #require(o.content.projection?.bounds)
        o.h.model.press(.dimension)
        click(o, at(o, bounds.center.x, bounds.min.y))
        #expect(o.h.model.refusal == "Isometric views take notes and leaders, not dimensions.")
        #expect(o.h.log.commits.isEmpty)
        #expect(o.h.model.picks.isEmpty)
    }

    @Test func foreshortenedRefuses() throws {
        let o = open(Fixtures.front(), orientation: .front, zoom: 4)
        o.h.model.press(.dimension)
        click(o, at(o, 7.5, 0))
        #expect(o.h.model.refusal == DrawingPick.lineSentence)
        #expect(o.h.model.picks.isEmpty)
        #expect(o.h.log.commits.isEmpty)
    }

    // MARK: Escape, the draft and the keys

    @Test func escapeDropsPicksThenTheTool() async throws {
        let o = open(try await Fixtures.plate(.front), orientation: .front)
        let bounds = try #require(o.content.projection?.bounds)
        o.h.model.press(.dimension)
        click(o, at(o, bounds.center.x, bounds.min.y))
        #expect(o.h.model.picks.count == 1)
        #expect(o.h.model.keyPressed(.escape))
        #expect(o.h.model.picks.isEmpty)
        #expect(o.h.model.draftPicture == nil)
        #expect(o.h.model.tool == .dimension)
        #expect(o.h.model.keyPressed(.escape))
        #expect(o.h.model.tool == .select)
        #expect(!o.h.model.keyPressed(.escape))
    }

    @Test func theDraftFollowsThePointer() async throws {
        let o = open(try await Fixtures.plate(.front), orientation: .front)
        let bounds = try #require(o.content.projection?.bounds)
        o.h.model.press(.dimension)
        #expect(o.h.model.draftPicture == nil)
        let bottom = at(o, bounds.center.x, bounds.min.y)
        click(o, bottom)
        let first = try #require(o.h.model.draftPicture)
        o.h.model.pointerMoved(to: o.h.canvas(bottom.x, bottom.y - 12))
        let second = try #require(o.h.model.draftPicture)
        #expect(first != second)
        #expect(o.h.log.commits.isEmpty, "a draft is never committed")
        #expect(o.h.model.document.sheets[0].annotations.isEmpty)
    }

    @Test func theDraftNeverFeedsRemembered() async throws {
        let o = open(try await Fixtures.plate(.front), orientation: .front)
        let bounds = try #require(o.content.projection?.bounds)
        o.h.model.press(.dimension)
        let bottom = at(o, bounds.center.x, bounds.min.y)
        click(o, bottom)
        o.h.model.pointerMoved(to: o.h.canvas(bottom.x, bottom.y - 12))
        #expect(o.h.model.draftPicture != nil)
        #expect(o.h.model.remembered.isEmpty)
    }

    @Test func toolKeys() {
        let expected: [(KeyEquivalent, DrawingTool)] = [
            ("d", .dimension), ("h", .holeCallout), ("m", .centreMark), ("l", .centreLine), ("n", .note),
        ]
        for (key, tool) in expected {
            #expect(SheetCanvasInput.key(key, modifiers: []) == .tool(tool))
        }
        #expect(SheetCanvasInput.key("D", modifiers: []) == .tool(.dimension))
        #expect(SheetCanvasInput.key("f", modifiers: []) == .fit)
        #expect(SheetCanvasInput.key("d", modifiers: .primary) == nil)
        let h = EditorHarness(document: EditorDocuments.document([DrawingSheet(name: "Sheet 1")]), sheet: nil)
        #expect(h.model.keyPressed(.tool(.note)))
        #expect(h.model.tool == .note)
    }

    @Test func hoverFindsCornersAndCentres() throws {
        let o = open(Fixtures.top(), orientation: .top, zoom: 4)
        o.h.model.press(.dimension)
        let corner = at(o, 0.2, 0.2)
        o.h.model.pointerMoved(to: o.h.canvas(corner.x, corner.y))
        guard case .corner? = o.h.model.hoverCandidate else {
            Issue.record("expected a corner: \(String(describing: o.h.model.hoverCandidate))")
            return
        }
        let centre = at(o, 20.3, 10.2)
        o.h.model.pointerMoved(to: o.h.canvas(centre.x, centre.y))
        guard case .centre? = o.h.model.hoverCandidate else {
            Issue.record("expected a centre: \(String(describing: o.h.model.hoverCandidate))")
            return
        }
        o.h.model.pointerLeft()
        #expect(o.h.model.hoverCandidate == nil)
    }
}
