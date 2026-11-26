import CreatorGeometry
import CreatorKernel

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// Two copies of the part with a hole, 100 mm apart, as one assembly view with its spans (DR-5 R2, R3): copy n's ids are shifted by
/// 1000 n. Seen from the top at 4 points per millimetre.
@MainActor
struct AssemblyScene {
    typealias Fixtures = AnnotationEditorFixtures

    let h: EditorHarness
    let view: DrawingView
    let mapping: ViewMapping
    let first: NodeID
    let second: NodeID
    let spans: [PartSpan]
    let topology: Topology

    static let shift = 1000

    static func copy(_ n: Int, removing: [Int] = []) -> Topology {
        let part = Fixtures.topology()
        let offset = Vector3(100 * Double(n), 0, 0)
        let faces = part.faces.map { face -> FaceInfo in
            var moved = face
            moved.id = FaceID(face.id.rawValue + shift * n)
            moved.centroid = face.centroid + offset
            if let axisPoint = face.axisPoint { moved.axisPoint = axisPoint + offset }
            return moved
        }
        let edges = part.edges.filter { !removing.contains($0.id.rawValue) }.map { edge -> EdgeInfo in
            var moved = edge
            moved.id = EdgeID(edge.id.rawValue + shift * n)
            moved.faces = edge.faces.map { FaceID($0.rawValue + shift * n) }
            moved.midpoint = edge.midpoint + offset
            switch edge.curve {
            case .line(let a, let b)?: moved.curve = .line(start: a + offset, end: b + offset)
            case .circle(let center, let axis, let radius, let start, let sweep)?:
                moved.curve = .circle(center: center + offset, axis: axis, radius: radius, start: start + offset, sweep: sweep)
            case nil: break
            }
            return moved
        }
        return Topology(faces: faces, edges: edges)
    }

    private static func line(_ a: Vector2, _ b: Vector2, _ source: ProjectionSource?) -> ProjectedLine {
        ProjectedLine(visibility: .visible, lineClass: .sharp, curve: .line(a, b), source: source)
    }

    /// `missing` edge ids (of the second copy, unshifted) are left out of the topology but stay drawn: a balloon on one is lost.
    static func make(
        annotations: [(NodeID, NodeID) -> DrawingAnnotation] = [], missingInSecond: [Int] = [], curve: Bool = false,
        orientation: StandardOrientation = .top
    ) -> AssemblyScene {
        let first = NodeID(), second = NodeID()
        let one = copy(0), two = copy(1, removing: missingInSecond)
        let topology = Topology(faces: one.faces + two.faces, edges: one.edges + two.edges)
        let spans = [
            PartSpan(output: first, faces: 0..<one.faces.count, curves: 0..<0),
            PartSpan(output: second, faces: one.faces.count..<(one.faces.count + two.faces.count), curves: 0..<0),
        ]
        var lines: [ProjectedLine] = []
        for n in 0...1 {
            let x = 100.0 * Double(n), id = shift * n
            lines.append(line(Vector2(x, 0), Vector2(x + 40, 0), .edge(EdgeID(102 + id))))
            lines.append(line(Vector2(x + 20, 0), Vector2(x + 20, 20), .edge(EdgeID(100 + id))))
        }
        if curve { lines.append(line(Vector2(0, 60), Vector2(40, 60), .curve(index: 0, piece: 0))) }
        let content = ViewContent(projection: Projection2D(lines: lines), topology: topology, parts: spans)
        let view = DrawingView(
            kind: .base, source: first, orientation: .standard(orientation), center: Fixtures.centre, showsCentreMarks: false,
            assembly: [first, second])
        let made = annotations.map { $0(first, second) }.map { annotation -> DrawingAnnotation in
            var placed = annotation
            placed.view = view.id
            return placed
        }
        let sheet = DrawingSheet(name: "Sheet 1", views: [view], annotations: made)
        let h = EditorHarness(
            document: EditorDocuments.document([sheet]), sheet: sheet.id,
            sources: [
                DrawingSourceOption(id: first, name: "Left", bounds: nil), DrawingSourceOption(id: second, name: "Right", bounds: nil),
            ],
            contents: [view.id: content])
        h.model.facts = TitleBlockFacts(parts: [
            first: PartFacts(name: "Left", quantity: 1, isRemoved: false),
            second: PartFacts(name: "Right", quantity: 1, isRemoved: false),
        ])
        h.model.transform = SheetTransform(offset: Vector2(0, 297 * 4), zoom: 4)
        let mapping = ViewMapping.of(content: content, center: Fixtures.centre, scale: 1)!
        return AssemblyScene(h: h, view: view, mapping: mapping, first: first, second: second, spans: spans, topology: topology)
    }

    /// Where model point (x, y) is on the sheet.
    func at(_ x: Double, _ y: Double) -> Vector2 { mapping.sheet(Vector2(x, y)) }

    /// The pick that names edge `id` (already shifted) of copy `n`, wrapped with its part.
    func pick(_ id: Int, copy n: Int) -> AnchorTarget {
        let scoped = topology.restricted(toFaces: spans[n].faces)
        let key = scoped.key(of: scoped.edge(EdgeID(id))!)!
        let edge = EdgePick(key: key, matchCount: scoped.edges(matching: key).count)
        return .onPart(n == 0 ? first : second, .edge(edge))
    }

    func click(_ point: Vector2, _ modifiers: SheetModifiers = []) { h.click(point.x, point.y, modifiers) }

    var annotations: [DrawingAnnotation] { h.model.document.sheets[0].annotations }

    /// A balloon on edge `edge` (unshifted) of copy `n`, naming its part; its view is set by `make`.
    static func balloonAnnotation(on part: NodeID, edge: Int, copy n: Int, offset: Vector2) -> DrawingAnnotation {
        let one = copy(0), two = copy(1)
        let topology = Topology(faces: one.faces + two.faces, edges: one.edges + two.edges)
        let count = one.faces.count
        let scoped = topology.restricted(toFaces: n == 0 ? 0..<count : count..<(2 * count))
        let key = scoped.key(of: scoped.edge(EdgeID(edge + shift * n))!)!
        let pick = EdgePick(key: key, matchCount: scoped.edges(matching: key).count)
        let leader = LeaderEnd(target: .onPart(part, .edge(pick)), hint: Vector2(20 + 100 * Double(n), -3))
        return DrawingAnnotation(view: nil, kind: .balloon(Balloon(leader: leader, offset: offset)))
    }
}
