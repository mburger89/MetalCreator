import CreatorGeometry
import CreatorKernel

@testable import CreatorDrawing

/// A part with a hole and a few edges seen from the top, and composing helpers for annotation tests (plan Task 8).
enum AnnotationFixtures {
    typealias Fixture = TopologyFixtures
    static let up = Vector3(0, 0, 1)
    static let holeCenter = Vector3(20, 10, 0)

    private static func v(_ x: Double, _ y: Double, _ z: Double) -> Vector3 { Vector3(x, y, z) }

    private static func face(_ id: Int, _ kind: SurfaceKind, normal: Vector3, z: Double, radius: Double? = nil) -> FaceInfo {
        FaceInfo(
            id: FaceID(id), kind: kind, normal: normal, area: 1, centroid: v(20, 10, z), tags: Fixture.tags(.side(segment: id)),
            radius: radius, axisPoint: radius == nil ? nil : holeCenter)
    }

    private static func ring(_ id: Int, z: Double, _ a: Int, _ b: Int) -> EdgeInfo {
        Fixture.circle(id, center: v(20, 10, z), axis: up, radius: 3, between: a, b)
    }

    /// The part: edges 102 (horizontal, 40), 100 and 103 (vertical, 20), 105 (diagonal), 104 (along the view direction), 101
    /// (a bottom line) and the through hole's rings 0 and 1. `removing` leaves edges out, `blind` makes the hole 10 deep.
    static func topology(removing: [Int] = [], blind: Bool = false) -> Topology {
        var faces = [
            face(0, .plane, normal: up, z: 0), face(1, .plane, normal: Vector3(0, 0, -1), z: -20),
            face(9, .plane, normal: Vector3(1, 0, 0), z: -10), face(8, .plane, normal: Vector3(0, -1, 0), z: -10),
            face(7, .plane, normal: Vector3(1, 0, 0), z: -10), face(6, .plane, normal: Vector3(1, -1, 0), z: -10),
        ]
        var edges = [
            Fixture.line(102, v(0, 0, 0), v(40, 0, 0), between: 0, 8),
            Fixture.line(100, v(20, 0, 0), v(20, 20, 0), between: 0, 9),
            Fixture.line(103, v(40, 0, 0), v(40, 20, 0), between: 0, 7),
            Fixture.line(105, v(0, 0, 0), v(15, 15, 0), between: 0, 6),
            Fixture.line(104, v(5, 5, 0), v(5, 5, -20), between: 8, 9),
            Fixture.line(101, v(20, 0, -20), v(20, 20, -20), between: 1, 9),
        ]
        if blind {
            faces += [face(2, .cylinder, normal: up, z: -5, radius: 3), face(3, .plane, normal: up, z: -10)]
            edges += [ring(0, z: 0, 2, 0), ring(1, z: -10, 2, 3)]
        } else {
            faces.append(face(2, .cylinder, normal: up, z: -10, radius: 3))
            edges += [ring(0, z: 0, 2, 0), ring(1, z: -20, 2, 1)]
        }
        return Topology(faces: faces, edges: edges.filter { !removing.contains($0.id.rawValue) })
    }

    static func line(_ curve: ProjectedCurve, edge: Int?, visibility: LineVisibility = .visible) -> ProjectedLine {
        ProjectedLine(visibility: visibility, lineClass: .sharp, curve: curve, source: edge.map { .edge(EdgeID($0)) })
    }

    static func projection() -> Projection2D {
        Projection2D(lines: [
            line(.line(Vector2(0, 0), Vector2(40, 0)), edge: 102),
            line(.line(Vector2(20, 0), Vector2(20, 20)), edge: 100),
            line(.line(Vector2(40, 0), Vector2(40, 20)), edge: 103),
            line(.line(Vector2(0, 0), Vector2(15, 15)), edge: 105),
            line(.arc(center: Vector2(20, 10), radius: 3, start: 0, sweep: 2 * .pi), edge: 0),
            line(.arc(center: Vector2(20, 10), radius: 3, start: 0, sweep: 2 * .pi), edge: 1, visibility: .hidden),
        ])
    }

    static func content(_ topology: Topology = topology(), pending: Bool = false, problem: String? = nil) -> ViewContent {
        ViewContent(projection: projection(), topology: topology, isPending: pending, problem: problem)
    }

    static func makeView(
        center: Vector2 = Vector2(150, 150), orientation: StandardOrientation = .top, showsCentreMarks: Bool = false
    ) -> DrawingView {
        DrawingView(
            kind: .base, source: NodeID(), orientation: .standard(orientation), center: center,
            showsCentreMarks: showsCentreMarks)
    }

    static func pick(_ topology: Topology, _ edge: Int) -> AnchorTarget { .edge(Fixture.pick(topology, [edge])) }

    static func dimension(
        _ view: ViewID, _ kind: DrawingDimensionKind, _ anchors: [AnchorTarget], offset: Double = 10, prefix: String = ""
    ) -> DrawingAnnotation {
        DrawingAnnotation(
            view: view,
            kind: .dimension(
                DrawingDimension(
                    kind: kind, anchors: anchors, placement: DimensionPlacement(offset: offset, angle: 0), prefix: prefix)))
    }

    static func note(_ view: ViewID?, _ text: String, at position: Vector2, leaders: [LeaderEnd] = []) -> DrawingAnnotation {
        DrawingAnnotation(view: view, kind: .note(DrawingNote(text: text, position: position, leaders: leaders)))
    }

    static func compose(
        _ view: DrawingView, _ annotations: [DrawingAnnotation], content: ViewContent, units: DocumentUnits = .millimetres,
        remembered: [AnnotationID: LastGood] = [:], standard: DrawingStandard = .iso
    ) -> SheetPicture {
        let sheet = DrawingSheet(name: "Sheet 1", views: [view], annotations: annotations)
        var settings = DrawingSettings()
        settings.standard = standard
        let document = DrawingDocument(settings: settings, sheets: [sheet])
        return SheetComposer.compose(
            sheet, in: document, contents: [view.id: content], facts: TitleBlockFacts(), units: units, remembered: remembered)
    }

    static func texts(_ picture: SheetPicture, of id: AnnotationID) -> [SheetText] { picture.texts.filter { $0.annotation == id } }
    static func strokes(_ picture: SheetPicture, of id: AnnotationID) -> [SheetStroke] { picture.strokes.filter { $0.annotation == id } }
}
