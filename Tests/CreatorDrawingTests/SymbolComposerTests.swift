import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Symbol composer")
struct SymbolComposerTests {
    typealias Fixtures = AnnotationFixtures
    typealias Fixture = TopologyFixtures
    let part = Fixtures.topology()
    let style = AnnotationStyle.of(.iso)
    let h = DrawingStyle.of(.iso).notesHeight(for: .a3)

    func v(_ x: Double, _ y: Double, _ z: Double) -> Vector3 { Vector3(x, y, z) }
    func close(_ a: Vector2, _ b: Vector2, _ tolerance: Double = 1e-9) -> Bool { LayoutSupport.close(a, b, tolerance) }

    /// Where the fixture's model plane lands on the sheet.
    func mapping(_ view: DrawingView) throws -> ViewMapping {
        try #require(ViewMapping.of(content: Fixtures.content(), center: view.center, scale: 1))
    }

    func replacing(_ id: Int, with edge: EdgeInfo) -> Topology {
        Topology(faces: part.faces, edges: part.edges.map { $0.id.rawValue == id ? edge : $0 })
    }

    func end(_ edge: Int = 102, hint: Vector2 = Vector2(20, 0), topology: Topology? = nil) -> LeaderEnd {
        LeaderEnd(target: Fixtures.pick(topology ?? part, edge), hint: hint)
    }

    func datum(
        _ view: DrawingView, _ attachment: SymbolAttachment? = nil, letter: String = "A", distance: Double = 8, endIndex: Int = 0
    ) -> DrawingAnnotation {
        DrawingAnnotation(
            view: view.id,
            kind: .datumFeature(
                DatumFeature(letter: letter, attachment: attachment ?? .feature(end()), distance: distance, dimensionEnd: endIndex)))
    }

    func frame(
        _ view: DrawingView, _ attachment: SymbolAttachment? = nil, offset: Vector2 = Vector2(10, 15),
        datums: [DatumReference] = []
    ) -> DrawingAnnotation {
        DrawingAnnotation(
            view: view.id,
            kind: .featureControl(
                FeatureControlFrame(
                    characteristic: .flatness, rows: [ToleranceRow(value: 0.05, datums: datums)],
                    attachment: attachment ?? .feature(end()), offset: offset)))
    }

    func surface(_ view: DrawingView, offset: Vector2? = nil) -> DrawingAnnotation {
        DrawingAnnotation(
            view: view.id,
            kind: .surfaceTexture(
                SurfaceTexture(
                    requirement: SurfaceRequirement(process: .removalRequired, parameter: .ra, value: 1.6), feature: end(),
                    offset: offset)))
    }

    func linear(_ view: DrawingView, offset: Double = 10) -> DrawingAnnotation {
        Fixtures.dimension(view.id, .linear(.horizontal), [Fixtures.pick(part, 102)], offset: offset)
    }

    func points(_ strokes: [SheetStroke]) -> [Vector2] {
        strokes.flatMap(\.segments).flatMap { segment -> [Vector2] in
            switch segment {
            case .line(let a, let b): [a, b]
            case .polyline(let points): points
            default: []
            }
        }
    }

    func hasPoint(_ strokes: [SheetStroke], _ point: Vector2) -> Bool { points(strokes).contains { close($0, point) } }

    func isLostEverywhere(_ picture: SheetPicture, _ id: AnnotationID) -> Bool {
        let strokes = Fixtures.strokes(picture, of: id), texts = Fixtures.texts(picture, of: id)
        let fills = picture.fills.filter { $0.annotation == id }
        return !strokes.isEmpty && strokes.allSatisfy(\.isLost) && texts.allSatisfy(\.isLost) && fills.allSatisfy(\.isLost)
    }

    // MARK: On a line

    @Test func aDatumStandsOnItsLine() throws {
        let view = Fixtures.makeView()
        let symbol = datum(view)
        let picture = Fixtures.compose(view, [symbol], content: Fixtures.content())
        let map = try mapping(view)
        let lineY = map.sheet(Vector2(20, 0)).y
        let strokes = Fixtures.strokes(picture, of: symbol.id)
        #expect(!strokes.isEmpty && strokes.allSatisfy { $0.layer == .dimension && $0.view == view.id && !$0.isLost })
        #expect(Fixtures.texts(picture, of: symbol.id).map(\.original) == ["A"])
        let fill = try #require(picture.fills.first { $0.annotation == symbol.id })
        #expect(fill.layer == .dimension)
        #expect(abs(fill.points[0].y - lineY) < 1e-9 && abs(fill.points[1].y - lineY) < 1e-9)
        #expect(fill.points[2].y > lineY)
        let report = try #require(picture.annotationReports[symbol.id])
        #expect(report.status == .held && report.label == "Datum A")
        #expect(report.current?.figure == .attachment(foot: Vector2(20, 0), along: Vector2(1, 0)))
        #expect(report.current?.lines == ["Datum A"])
    }

    @Test func aDatumBeyondTheEdgeDrawsAnExtensionLine() throws {
        let view = Fixtures.makeView()
        let symbol = datum(view, .feature(end(hint: Vector2(50, 0))))
        let picture = Fixtures.compose(view, [symbol], content: Fixtures.content())
        let map = try mapping(view)
        let lineY = map.sheet(Vector2(0, 0)).y, edgeEnd = map.sheet(Vector2(40, 0)).x
        let extensionLine = Fixtures.strokes(picture, of: symbol.id).contains { stroke in
            stroke.segments.contains { segment in
                guard case .line(let a, let b) = segment else { return false }
                return abs(a.y - lineY) < 1e-9 && abs(b.y - lineY) < 1e-9 && min(a.x, b.x) >= edgeEnd - 1e-9 && max(a.x, b.x) > edgeEnd + 5
            }
        }
        #expect(extensionLine)
    }

    @Test func aFrameLeadsToItsLine() throws {
        let view = Fixtures.makeView()
        let symbol = frame(view)
        let picture = Fixtures.compose(view, [symbol], content: Fixtures.content())
        let tip = try mapping(view).sheet(Vector2(20, 0))
        #expect(picture.fills.contains { $0.annotation == symbol.id && $0.points.contains { close($0, tip) } })
        #expect(Fixtures.texts(picture, of: symbol.id).map(\.original).contains("0.05"))
        #expect(picture.annotationReports[symbol.id]?.label == "Flatness 0.05")
        #expect(picture.annotationReports[symbol.id]?.status == .held)
    }

    @Test func aSurfaceSymbolStands() throws {
        let view = Fixtures.makeView()
        let symbol = surface(view)
        let picture = Fixtures.compose(view, [symbol], content: Fixtures.content())
        let foot = try mapping(view).sheet(Vector2(20, 0))
        #expect(hasPoint(Fixtures.strokes(picture, of: symbol.id), foot))
        #expect(Fixtures.texts(picture, of: symbol.id).map(\.original) == ["Ra 1.6"])
        #expect(picture.annotationReports[symbol.id]?.label == "Surface texture Ra 1.6")
    }

    @Test func aSymbolFollowsItsLineThroughAWidthChange() throws {
        let view = Fixtures.makeView()
        let symbol = datum(view)
        let wide = replacing(102, with: Fixture.line(102, v(0, 0, 0), v(60, 0, 0), between: 0, 8))
        let narrow = Fixtures.compose(view, [symbol], content: Fixtures.content())
        let grown = Fixtures.compose(view, [symbol], content: Fixtures.content(wide))
        #expect(grown.annotationReports[symbol.id]?.status == .held)
        let a = try #require(narrow.fills.first { $0.annotation == symbol.id })
        let b = try #require(grown.fills.first { $0.annotation == symbol.id })
        for (p, q) in zip(a.points, b.points) { #expect(close(p, q)) }
    }

    @Test func aLostSymbolKeepsItsLastPlaceWithAQuestionMark() throws {
        let view = Fixtures.makeView()
        let symbol = datum(view)
        let last = LastGood(values: [], lines: ["Datum A"], figure: .attachment(foot: Vector2(20, 0), along: Vector2(1, 0)))
        let gone = Fixtures.topology(removing: [102])
        let picture = Fixtures.compose(view, [symbol], content: Fixtures.content(gone), remembered: [symbol.id: last])
        #expect(isLostEverywhere(picture, symbol.id))
        #expect(Fixtures.texts(picture, of: symbol.id).map(\.original).contains("?"))
        #expect(picture.lostAnnotations == [symbol.id])
        #expect(picture.annotationReports[symbol.id]?.status == .lost(.missing))
        #expect(picture.annotationReports[symbol.id]?.label == "Datum A")
    }

    @Test func aLostSymbolWithNoLastFigureIsALoneQuestionMark() {
        let view = Fixtures.makeView()
        let symbol = datum(view)
        let picture = Fixtures.compose(view, [symbol], content: Fixtures.content(Fixtures.topology(removing: [102])))
        #expect(Fixtures.texts(picture, of: symbol.id).map(\.original) == ["?"])
        #expect(picture.lostAnnotations == [symbol.id])
    }

    @Test func aSlantedEdgeTurnedCurvedIsNotStraight() {
        let view = Fixtures.makeView()
        let circle = replacing(102, with: Fixture.circle(102, center: v(20, 0, 0), axis: v(0, 0, 1), radius: 20, between: 0, 8))
        let content = Fixtures.content(circle)
        let datumSymbol = datum(view), frameSymbol = frame(view)
        let picture = Fixtures.compose(view, [datumSymbol, frameSymbol], content: content)
        #expect(picture.annotationReports[datumSymbol.id]?.status == .lost(.notStraight))
        #expect(picture.annotationReports[frameSymbol.id]?.status == .held)
        #expect(
            LostReason.notStraight.sentence == "What it stands on is no longer a straight line.")
    }

    @Test func aLineTurnedEndOnIsTurnedAway() {
        let view = Fixtures.makeView()
        let endOn = replacing(102, with: Fixture.line(102, v(0, 0, 0), v(0, 0, -10), between: 0, 8))
        let symbol = datum(view)
        let picture = Fixtures.compose(view, [symbol], content: Fixtures.content(endOn))
        #expect(picture.annotationReports[symbol.id]?.status == .lost(.turnedAway))
        #expect(
            LostReason.turnedAway.sentence
                == "What it stands on has turned, so this view no longer shows it the way the symbol needs.")
    }

    @Test func aSlantedLineStaysHeld() throws {
        let view = Fixtures.makeView()
        let slanted = replacing(102, with: Fixture.line(102, v(0, 0, 0), v(40, 0, 10), between: 0, 8))
        let symbol = datum(view)
        let picture = Fixtures.compose(view, [symbol], content: Fixtures.content(slanted))
        let report = try #require(picture.annotationReports[symbol.id])
        #expect(report.status == .held)
        #expect(report.current?.figure == .attachment(foot: Vector2(20, 0), along: Vector2(1, 0)))
    }

    @Test func aSymbolOnALineIsLostInAnIsometricView() {
        let view = Fixtures.makeView(orientation: .isometricFrontRight)
        let symbol = datum(view)
        let picture = Fixtures.compose(view, [symbol], content: Fixtures.content())
        #expect(picture.annotationReports[symbol.id]?.status == .lost(.refused(DrawingPick.symbolIsometricSentence)))
        #expect(picture.lostAnnotations == [symbol.id])
    }
}
