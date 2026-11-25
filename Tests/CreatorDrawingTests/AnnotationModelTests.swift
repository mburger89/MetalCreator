import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

@Suite("Annotation model")
struct AnnotationModelTests {
    private let node = NodeID()

    private func edgePick(_ item: Int) -> EdgePick {
        let tag = TopoTag(node: node, item: item, role: .startCap)
        let other = TopoTag(node: node, item: item, role: .endCap)
        return EdgePick(key: EdgeKey([tag], [other]), matchCount: 1)
    }

    private func facePick(_ item: Int) -> FacePick {
        FacePick(tags: [TopoTag(node: node, item: item, role: .side(segment: 1))])
    }

    private func view(_ id: ViewID = ViewID()) -> DrawingView {
        DrawingView(id: id, kind: .base, source: node, orientation: .standard(.front), center: Vector2(100, 100))
    }

    private let placement = DimensionPlacement(offset: 8, angle: 0.5, textShift: nil)

    private func dimension(
        _ kind: DrawingDimensionKind, _ anchors: [AnchorTarget], tolerance: DimensionTolerance = .general
    ) -> DrawingDimension {
        DrawingDimension(kind: kind, anchors: anchors, placement: placement, tolerance: tolerance)
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: try JSONEncoder().encode(value))
    }

    @Test func annotationsStaySortedById() {
        let a = DrawingAnnotation(id: AnnotationID(), view: nil, kind: .centreMark(CentreMark(anchor: .point(Vector2(1, 2)))))
        let b = DrawingAnnotation(id: AnnotationID(), view: nil, kind: .centreMark(CentreMark(anchor: .point(Vector2(3, 4)))))
        let c = DrawingAnnotation(id: AnnotationID(), view: nil, kind: .centreMark(CentreMark(anchor: .point(Vector2(5, 6)))))
        var sheet = DrawingSheet(name: "S")
        for annotation in [c, a, b] { sheet.setAnnotation(annotation) }
        #expect(sheet.annotations.map(\.id) == [a.id, b.id, c.id].sorted())
        #expect(sheet.annotation(a.id) == a)
        var replaced = a
        replaced.last = LastGood(values: [1], lines: ["1"], figure: .leaders([]))
        sheet.setAnnotation(replaced)
        #expect(sheet.annotations.count == 3)
        #expect(sheet.annotation(a.id)?.last != nil)
        sheet.removeAnnotation(a.id)
        #expect(sheet.annotation(a.id) == nil)
        #expect(sheet.annotations.count == 2)
    }

    @Test func everyKindRoundTrips() throws {
        let anchors: [AnchorTarget] = [
            .edge(edgePick(1)), .corner(edgePick(2), edgePick(3)), .centre(edgePick(4)),
            .outline(facePick(5), side: Vector2(0, 1)), .axis(facePick(6)), .point(Vector2(1.5, -2)),
        ]
        let tolerances: [DimensionTolerance] = [
            .general, .symmetric(0.1), .deviation(upper: 0.1, lower: -0.2), .limits(upper: 0.1, lower: -0.1), .reference, .basic,
            .fit(.hole(.H, grade: 7), showsDeviations: true), .fit(.shaft(.js, grade: 6), showsDeviations: false),
        ]
        let kinds: [DrawingDimensionKind] = [
            .linear(.horizontal), .linear(.vertical), .linear(.aligned), .baseline(.horizontal), .chain(.vertical),
            .ordinate(.horizontal), .ordinate(.vertical), .radius, .diameter, .angle, .chamfer,
        ]
        var all: [DrawingAnnotation] = []
        for kind in kinds {
            all.append(DrawingAnnotation(id: AnnotationID(), view: nil, kind: .dimension(dimension(kind, anchors, tolerance: .reference))))
        }
        for tolerance in tolerances {
            all.append(
                DrawingAnnotation(
                    id: AnnotationID(), view: nil,
                    kind: .dimension(
                        DrawingDimension(
                            kind: .diameter, anchors: anchors, placement: DimensionPlacement(offset: 1, angle: 2, textShift: 3),
                            tolerance: tolerance, precision: 3, prefix: "2X ", suffix: " THRU"))))
        }
        for anchor in anchors {
            all.append(
                DrawingAnnotation(
                    id: AnnotationID(), view: ViewID(),
                    kind: .holeCallout(HoleCallout(anchor: anchor, placement: placement, prefix: "A", suffix: "B"))))
            all.append(DrawingAnnotation(id: AnnotationID(), view: nil, kind: .centreMark(CentreMark(anchor: anchor))))
            all.append(DrawingAnnotation(id: AnnotationID(), view: nil, kind: .centreLine(CentreLine(anchor: anchor))))
            all.append(
                DrawingAnnotation(
                    id: AnnotationID(), view: nil,
                    kind: .note(
                        DrawingNote(text: "Note", position: Vector2(5, 6), leaders: [LeaderEnd(target: anchor, hint: Vector2(1, 1))]))))
        }
        for figure in Self.figures {
            all.append(
                DrawingAnnotation(
                    id: AnnotationID(), view: nil, kind: .centreMark(CentreMark(anchor: .point(Vector2(0, 0)))),
                    last: LastGood(values: [25, 0.5], lines: ["25", "±0.1"], figure: figure)))
        }
        for annotation in all { #expect(try roundTrip(annotation) == annotation) }
        #expect(try roundTrip(all) == all)
    }

    private static let figures: [AnnotationFigure] = [
            .linear(points: [Vector2(0, 0), Vector2(1, 0)], direction: Vector2(1, 0)),
            .ordinate(origin: Vector2(0, 0), points: [Vector2(1, 1)], direction: Vector2(0, 1)),
            .radial(center: Vector2(1, 1), radius: 3, isDiameter: true),
            .angle(vertex: Vector2(0, 0), first: [Vector2(1, 0)], second: [Vector2(0, 1)]),
            .chamfer(start: Vector2(0, 0), end: Vector2(1, 1)), .hole(center: Vector2(2, 2), radius: 1),
            .centreMark(center: Vector2(2, 2), radius: 1), .centreLine(start: Vector2(0, 0), end: Vector2(0, 5)),
            .leaders([Vector2(0, 0), Vector2(2, 2)]),
    ]

    @Test func kindsAreCodedByType() throws {
        let annotation = DrawingAnnotation(
            id: AnnotationID(), view: nil, kind: .dimension(dimension(.linear(.horizontal), [.edge(edgePick(1))])))
        let data = try JSONEncoder().encode(annotation)
        let text = String(bytes: data, encoding: .utf8) ?? ""
        #expect(!text.contains("\"_0\""))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let kind = try #require(object["kind"] as? [String: Any])
        #expect(kind["type"] as? String == "dimension")
        let body = try #require(kind["dimension"] as? [String: Any])
        let anchors = try #require(body["anchors"] as? [[String: Any]])
        #expect(anchors.first?["type"] as? String == "edge")
    }

    @Test func aFitGradeOutOfRangeReadsGeneral() throws {
        for grade in [4, 12, 0, -1] {
            let json = #"{"type":"fit","designation":{"type":"hole","letter":"H","grade":\#(grade)},"showsDeviations":true}"#
            let tolerance = try JSONDecoder().decode(DimensionTolerance.self, from: Data(json.utf8))
            #expect(tolerance == .general)
        }
        let json = #"{"type":"fit","designation":{"type":"shaft","letter":"js","grade":6},"showsDeviations":false}"#
        let ok = try JSONDecoder().decode(DimensionTolerance.self, from: Data(json.utf8))
        #expect(ok == .fit(.shaft(.js, grade: 6), showsDeviations: false))
        #expect(FitDesignation.hole(.H, grade: 7).text == "H7")
        #expect(FitDesignation.shaft(.js, grade: 6).text == "js6")
    }

    @Test func anAnnotationOfAMissingViewIsDropped() throws {
        let kept = view()
        let annotations = [
            DrawingAnnotation(id: AnnotationID(), view: kept.id, kind: .centreMark(CentreMark(anchor: .point(Vector2(0, 0))))),
            DrawingAnnotation(id: AnnotationID(), view: ViewID(), kind: .centreMark(CentreMark(anchor: .point(Vector2(0, 0))))),
            DrawingAnnotation(id: AnnotationID(), view: nil, kind: .centreMark(CentreMark(anchor: .point(Vector2(0, 0))))),
        ]
        let sheet = DrawingSheet(name: "S", views: [kept], annotations: annotations)
        let back = try roundTrip(sheet)
        #expect(back.annotations.count == 2)
        #expect(Set(back.annotations.map(\.id)) == [annotations[0].id, annotations[2].id])
    }

    private func sheetWithAnnotations() -> (DrawingSheet, ViewID, ViewID) {
        let a = view(), b = view()
        let on = { (v: ViewID?) in
            DrawingAnnotation(id: AnnotationID(), view: v, kind: .centreMark(CentreMark(anchor: .point(Vector2(0, 0)))))
        }
        let sheet = DrawingSheet(name: "S", views: [a, b], annotations: [on(a.id), on(a.id), on(b.id), on(nil)])
        return (sheet, a.id, b.id)
    }

    @Test func removingAViewRemovesItsAnnotations() {
        let (sheet, a, b) = sheetWithAnnotations()
        let result = ViewPlacement.removing(a, from: sheet)
        #expect(result.annotations(of: a).isEmpty)
        #expect(result.annotations(of: b).count == 1)
        #expect(result.annotations.count == 2)
    }

    @Test func removeViewDropsItsAnnotations() {
        var (sheet, a, _) = sheetWithAnnotations()
        sheet.removeView(a)
        #expect(sheet.annotations.allSatisfy { $0.view != a })
        #expect(sheet.annotations.count == 2)
    }

    @Test func freeAnnotationsSurviveViewRemoval() {
        var (sheet, a, b) = sheetWithAnnotations()
        sheet.removeView(a)
        sheet.removeView(b)
        #expect(sheet.annotations.count == 1)
        #expect(sheet.annotations[0].view == nil)
    }

    @Test func centreMarksDefaultOnForOldViews() throws {
        #expect(view().showsCentreMarks)
        var changed = view()
        changed.showsCentreMarks = false
        #expect(try roundTrip(changed).showsCentreMarks == false)
        let data = try JSONEncoder().encode(view())
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["showsCentreMarks"] = nil
        let old = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(DrawingView.self, from: old).showsCentreMarks)
    }

    @Test func noAnnotationsKeyWhenEmpty() throws {
        let data = try JSONEncoder().encode(DrawingSheet(name: "S"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["annotations"] == nil)
        let (sheet, _, _) = sheetWithAnnotations()
        let full = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(sheet)) as? [String: Any])
        #expect(full["annotations"] != nil)
    }
}
