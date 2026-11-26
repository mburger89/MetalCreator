import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Annotation refresh")
struct AnnotationRefreshTests {
    private typealias Fixtures = AnnotationFixtures
    private let topology = Fixtures.topology()

    private func pick(_ edge: Int) -> AnchorTarget { Fixtures.pick(topology, edge) }

    private func annotations(_ view: ViewID) -> [DrawingAnnotation] {
        let placement = DimensionPlacement(offset: 10, angle: 0.4)
        func dimension(_ kind: DrawingDimensionKind, _ anchors: [AnchorTarget]) -> DrawingAnnotation {
            DrawingAnnotation(
                view: view,
                kind: .dimension(DrawingDimension(kind: kind, anchors: anchors, placement: placement)))
        }
        return [
            dimension(.linear(.horizontal), [pick(102)]), dimension(.linear(.vertical), [pick(100)]),
            dimension(.linear(.aligned), [pick(105)]), dimension(.linear(.horizontal), [pick(100), pick(103)]),
            dimension(.baseline(.horizontal), [pick(100), pick(103), pick(102)]),
            dimension(.chain(.horizontal), [pick(100), pick(103), pick(102)]), dimension(.ordinate(.horizontal), [pick(100), pick(103)]),
            dimension(.radius, [pick(0)]), dimension(.diameter, [pick(0)]), dimension(.angle, [pick(102), pick(105)]),
            dimension(.chamfer, [pick(105), pick(102)]),
            DrawingAnnotation(view: view, kind: .holeCallout(HoleCallout(anchor: pick(0), placement: placement))),
            DrawingAnnotation(view: view, kind: .centreMark(CentreMark(anchor: pick(0)))),
        ]
    }

    private func format() -> NumberFormat { NumberFormat(units: .millimetres, standard: .iso, decimalSign: .point) }

    @Test func theRefreshMatchesTheCompose() throws {
        let view = Fixtures.makeView()
        let all = annotations(view.id)
        let picture = Fixtures.compose(view, all, content: Fixtures.content())
        for annotation in all {
            let report = try #require(picture.annotationReports[annotation.id])
            let refreshed = AnnotationRefresh.lastGood(
                for: annotation, topology: topology, frame: StandardOrientation.top.frame, format: format(),
                standard: .iso, parts: [], isPictorial: false)
            #expect(report.current != nil, "\(annotation.kind) holds")
            #expect(refreshed == report.current)
        }
    }

    @Test func aCentreLineRefreshesLikeItsCompose() throws {
        let view = Fixtures.makeView(orientation: .front)
        let face = try #require(topology.facePick(for: FaceID(2)))
        let line = DrawingAnnotation(view: view.id, kind: .centreLine(CentreLine(anchor: .axis(face))))
        let picture = Fixtures.compose(view, [line], content: Fixtures.content())
        let refreshed = AnnotationRefresh.lastGood(
            for: line, topology: topology, frame: StandardOrientation.front.frame, format: format(),
                standard: .iso, parts: [], isPictorial: false)
        #expect(refreshed != nil && refreshed == picture.annotationReports[line.id]?.current)
    }

    @Test func aLostAnnotationRefreshesToNil() {
        let view = Fixtures.makeView()
        let dimension = annotations(view.id)[0]
        let gone = Fixtures.topology(removing: [102])
        #expect(
            AnnotationRefresh.lastGood(
                for: dimension, topology: gone, frame: StandardOrientation.top.frame, format: format(),
                standard: .iso, parts: [], isPictorial: false) == nil)
    }

    @Test func notesAreNotRefreshed() {
        let note = Fixtures.note(nil, "Note", at: .zero)
        #expect(
            AnnotationRefresh.lastGood(
                for: note, topology: topology, frame: StandardOrientation.top.frame, format: format(),
                standard: .iso, parts: [], isPictorial: false) == nil)
    }

    // MARK: Symbols (DR-4)

    @Test func aSymbolOnALineRefreshes() {
        let view = Fixtures.makeView()
        let symbol = DrawingAnnotation(
            view: view.id,
            kind: .datumFeature(
                DatumFeature(letter: "A", attachment: .feature(LeaderEnd(target: pick(102), hint: Vector2(20, 0))), distance: 8)))
        let refreshed = AnnotationRefresh.lastGood(
            for: symbol, topology: topology, frame: StandardOrientation.top.frame, format: format(),
                standard: .iso, parts: [], isPictorial: false)
        expectAttachment(refreshed?.figure, foot: Vector2(20, 0), along: Vector2(1, 0))
        #expect(refreshed?.lines == ["Datum A"])
        let picture = Fixtures.compose(view, [symbol], content: Fixtures.content())
        #expect(picture.annotationReports[symbol.id]?.current == refreshed)
    }

    @Test func aSymbolOnADimensionIsSkipped() {
        let view = Fixtures.makeView()
        let host = Fixtures.dimension(view.id, .linear(.horizontal), [pick(102)])
        let symbol = DrawingAnnotation(
            view: view.id, kind: .datumFeature(DatumFeature(letter: "A", attachment: .dimension(host.id), distance: 8)))
        #expect(
            AnnotationRefresh.lastGood(
                for: symbol, topology: topology, frame: StandardOrientation.top.frame, format: format(),
                standard: .iso, parts: [], isPictorial: false) == nil)
        #expect(
            AnnotationRefresh.lostReason(
                of: symbol, topology: topology, frame: StandardOrientation.top.frame, format: format(),
                standard: .iso, parts: [], isPictorial: false) == nil)
    }

    // MARK: Assemblies and pictorial views (DR-5)

    @Test func pictorialViewsRefreshNoDimensionsOrSymbols() {
        let view = Fixtures.makeView()
        let dimension = Fixtures.dimension(view.id, .linear(.horizontal), [pick(102)])
        let datum = DrawingAnnotation(
            view: view.id,
            kind: .datumFeature(
                DatumFeature(letter: "A", attachment: .feature(LeaderEnd(target: pick(102), hint: Vector2(20, 0))), distance: 8)))
        let frame = StandardOrientation.top.frame
        for annotation in [dimension, datum] {
            #expect(
                AnnotationRefresh.lastGood(
                    for: annotation, topology: topology, frame: frame, format: format(),
                standard: .iso, parts: [], isPictorial: false)
                    != nil)
            #expect(
                AnnotationRefresh.lastGood(
                    for: annotation, topology: topology, frame: frame, format: format(),
                standard: .iso, parts: [], isPictorial: true)
                    == nil)
            #expect(
                AnnotationRefresh.lostReason(
                    of: annotation, topology: Fixtures.topology(removing: [102]), frame: frame, format: format(), standard: .iso,
                    parts: [], isPictorial: true) == nil)
        }
    }

    @Test func aPartAnchorRefreshes() throws {
        let part = NodeID()
        let count = topology.faces.count
        let spans = [PartSpan(output: part, faces: 0..<count, curves: 0..<0)]
        let view = Fixtures.makeView()
        let wrapped = Fixtures.dimension(view.id, .linear(.horizontal), [.onPart(part, pick(102))])
        let bare = Fixtures.dimension(view.id, .linear(.horizontal), [pick(102)])
        let frame = StandardOrientation.top.frame
        let refreshed = try #require(
            AnnotationRefresh.lastGood(
                for: wrapped, topology: topology, frame: frame, format: format(), standard: .iso, parts: spans, isPictorial: false))
        let expected = AnnotationRefresh.lastGood(
            for: bare, topology: topology, frame: frame, format: format(),
                standard: .iso, parts: [], isPictorial: false)
        #expect(refreshed == expected)
        #expect(
            AnnotationRefresh.lostReason(
                of: wrapped, topology: topology, frame: frame, format: format(),
                standard: .iso, parts: [], isPictorial: false)
                == .partNotShown)
    }
}
