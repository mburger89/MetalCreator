import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

@Suite("Picking anchors")
struct DrawingPickTests {
    private typealias Fixture = TopologyFixtures
    private let front = StandardOrientation.front.frame
    private let view = ViewID()
    private let mapping = ViewMapping(scale: 2, offset: Vector2(100, 50))

    private func v(_ x: Double, _ y: Double, _ z: Double) -> Vector3 { Vector3(x, y, z) }

    private func picture(_ strokes: [SheetStroke]) -> SheetPicture {
        SheetPicture(size: Vector2(420, 297), strokes: strokes)
    }

    private func stroke(_ segment: SheetSegment, _ source: ProjectionSource?, annotation: AnnotationID? = nil) -> SheetStroke {
        SheetStroke(segments: [segment], width: 0.5, layer: .visible, view: view, annotation: annotation, source: source)
    }

    private func sheetLine(_ a: Vector2, _ b: Vector2, _ source: ProjectionSource?) -> SheetStroke {
        stroke(.line(mapping.sheet(a), mapping.sheet(b)), source)
    }

    private func anchor(
        _ candidate: PickCandidate, _ topology: Topology, purpose: PickPurpose = .dimension, click: Vector2 = .zero,
        isometric: Bool = false, frame: ProjectionFrame? = nil
    ) -> Result<PickedAnchor, DrawingRefusal> {
        DrawingPick.anchor(
            for: candidate, click: click, purpose: purpose, topology: topology, frame: frame ?? front, mapping: mapping,
            isIsometric: isometric, parts: nil)
    }

    private func refused(_ result: Result<PickedAnchor, DrawingRefusal>) -> String? {
        if case .failure(let refusal) = result { refusal.sentence } else { nil }
    }

    private func picked(_ result: Result<PickedAnchor, DrawingRefusal>) -> PickedAnchor? {
        if case .success(let anchor) = result { anchor } else { nil }
    }

    /// A bottom edge along x (0), an upright at its left end (1) and a depth edge at the same end (2).
    private var corner: Topology {
        Fixture.plate(edges: [
            Fixture.line(0, v(0, 0, 0), v(10, 0, 0), between: 0, 1),
            Fixture.line(1, v(0, 0, 0), v(0, 0, 10), between: 0, 2),
            Fixture.line(2, v(0, 0, 0), v(0, 5, 0), between: 1, 3),
        ])
    }

    // MARK: Candidates

    @Test func aLineIsAnEdge() throws {
        let topology = corner
        let drawn = picture([sheetLine(Vector2(0, 0), Vector2(10, 0), .edge(EdgeID(0)))])
        let found = DrawingPick.candidate(at: mapping.sheet(Vector2(5, 0.2)), in: drawn, view: view, tolerance: 1)
        #expect(found == .edge(EdgeID(0), stroke: 0))
        let candidate = try #require(found)
        let result = try #require(picked(anchor(candidate, topology)))
        #expect(result.target == .edge(Fixture.pick(topology, [0])))
        #expect(result.shape == .line(Vector2(0, 0), Vector2(10, 0)))
    }

    @Test func nearAnEndIsACorner() throws {
        let topology = corner
        let drawn = picture([
            sheetLine(Vector2(0, 0), Vector2(10, 0), .edge(EdgeID(0))),
            sheetLine(Vector2(0, 0), Vector2(0, 10), .edge(EdgeID(1))),
        ])
        let end = mapping.sheet(Vector2(10, 0))
        let found = DrawingPick.candidate(at: end + Vector2(0.3, 0.2), in: drawn, view: view, tolerance: 1)
        #expect(found == .corner(EdgeID(0), at: end))
        // The right end of the bottom edge meets nothing: no neighbour.
        let rightEnd = try #require(found)
        #expect(refused(anchor(rightEnd, topology)) == DrawingPick.cornerSentence)
        let start = mapping.sheet(Vector2(0, 0))
        let left = try #require(DrawingPick.candidate(at: start, in: drawn, view: view, tolerance: 1))
        guard case .corner(let id, _) = left else { Issue.record("not a corner"); return }
        let clickedEdge = id
        let result = try #require(picked(anchor(left, topology)))
        // The neighbour is the lowest-ID edge at the end that isn't the clicked one: the upright, edge 1.
        let neighbour = clickedEdge == EdgeID(0) ? Fixture.pick(topology, [1]) : Fixture.pick(topology, [0])
        #expect(result.target == .corner(Fixture.pick(topology, [clickedEdge.rawValue]), neighbour))
        #expect(result.shape == .point(Vector2(0, 0)))
    }

    @Test func theEndOfAStrokeThatStopsShortOfTheEdgeIsNoCorner() throws {
        // Edge 0 runs (0,0)-(10,0) but its visible stroke stops at x = 6 where it goes behind something.
        let topology = Fixture.plate(edges: [
            Fixture.line(0, v(0, 0, 0), v(10, 0, 0), between: 0, 1),
            Fixture.line(1, v(10, 0, 0), v(10, 0, 10), between: 0, 2),
        ])
        let drawn = picture([sheetLine(Vector2(0, 0), Vector2(6, 0), .edge(EdgeID(0)))])
        let stop = mapping.sheet(Vector2(6, 0))
        let found = try #require(DrawingPick.candidate(at: stop, in: drawn, view: view, tolerance: 1))
        guard case .corner = found else { Issue.record("not a corner"); return }
        #expect(refused(anchor(found, topology)) == DrawingPick.cornerSentence)
    }

    @Test func nearACircleCentreIsACentre() throws {
        let topology = Fixture.plate(edges: [Fixture.circle(3, center: v(5, 0, 5), axis: v(0, 1, 0), radius: 2, between: 0, 2)])
        let centre = mapping.sheet(Vector2(5, 5))
        let drawn = picture([stroke(.arc(center: centre, radius: 4, start: 0, sweep: 2 * .pi), .edge(EdgeID(3)))])
        let found = DrawingPick.candidate(at: centre + Vector2(0.2, 0), in: drawn, view: view, tolerance: 1)
        #expect(found == .centre(EdgeID(3), at: centre))
        let centreCandidate = try #require(found)
        let result = try #require(picked(anchor(centreCandidate, topology)))
        #expect(result.target == .centre(Fixture.pick(topology, [3])))
        #expect(result.shape == .point(Vector2(5, 5)))
        // On the circle itself it is the edge.
        let onEdge = DrawingPick.candidate(at: centre + Vector2(4, 0.1), in: drawn, view: view, tolerance: 1)
        #expect(onEdge == .edge(EdgeID(3), stroke: 0))
    }

    private var cylinderTopology: Topology {
        Fixture.plate(
            edges: [Fixture.line(0, v(0, 0, 0), v(10, 0, 0), between: 0, 1)],
            extraFaces: [Fixture.cylinder(4, .side(segment: 4), axisPoint: v(0, 0, 5), axis: v(1, 0, 0), radius: 5)])
    }

    @Test func aSilhouetteIsAnOutline() throws {
        let topology = cylinderTopology
        let drawn = picture([sheetLine(Vector2(0, 0), Vector2(10, 0), .face(FaceID(4)))])
        let found = try #require(DrawingPick.candidate(at: mapping.sheet(Vector2(5, 0)), in: drawn, view: view, tolerance: 1))
        #expect(found == .outline(FaceID(4), stroke: 0))
        // The click lies below the axis on the sheet, so the side points down.
        let result = try #require(picked(anchor(found, topology, click: mapping.sheet(Vector2(5, 0)))))
        guard case .outline(let pick, let side) = result.target else { Issue.record("not an outline"); return }
        #expect(topology.faces(matching: pick).map(\.id) == [FaceID(4)])
        #expect(abs(side.x) < 1e-12 && abs(side.y + 1) < 1e-12)
        #expect(result.shape == .cylinder(axisPoint: Vector2(0, 5), direction: Vector2(1, 0), radius: 5))
        let above = try #require(picked(anchor(found, topology, click: mapping.sheet(Vector2(5, 10)))))
        guard case .outline(_, let upSide) = above.target else { return }
        #expect(abs(upSide.y - 1) < 1e-12)
        // A centre line takes the axis.
        let line = try #require(picked(anchor(found, topology, purpose: .centreLine)))
        guard case .axis = line.target else { Issue.record("not an axis"); return }
    }

    @Test func annotationStrokesAreNotPicked() {
        let drawn = picture([
            stroke(.line(Vector2(100, 50), Vector2(120, 50)), nil, annotation: AnnotationID()),
            SheetStroke(
                segments: [.line(Vector2(100, 50), Vector2(120, 50))], width: 0.25, layer: .center, view: view,
                source: .edge(EdgeID(0))),
        ])
        #expect(DrawingPick.candidate(at: Vector2(110, 50), in: drawn, view: view, tolerance: 2) == nil)
        #expect(DrawingPick.candidate(at: Vector2(100, 50), in: drawn, view: view, tolerance: 2) == nil)
    }

    @Test func aFreeCurveIsRefused() {
        let drawn = picture([stroke(.polyline([Vector2(100, 50), Vector2(120, 60)]), .curve(index: 0, piece: 0))])
        #expect(DrawingPick.candidate(at: Vector2(110, 55), in: drawn, view: view, tolerance: 2) == nil)
        #expect(
            DrawingPick.refusal(at: Vector2(110, 55), in: drawn, view: view, tolerance: 2)?.sentence
                == "This line is a free curve; dimensions attach to a part's edges.")
        #expect(DrawingPick.refusal(at: Vector2(300, 55), in: drawn, view: view, tolerance: 2) == nil)
    }

    @Test func aFreeCurveRefusalSaysSymbolForASymbolTool() {
        let drawn = picture([stroke(.polyline([Vector2(100, 50), Vector2(120, 60)]), .curve(index: 0, piece: 0))])
        #expect(
            DrawingPick.refusal(at: Vector2(110, 55), in: drawn, view: view, tolerance: 2, purpose: PickPurpose(symbol: .datum))?
                .sentence == "This line is a free curve; symbols attach to a part's edges.")
    }

    // MARK: Naming (R3)

    @Test func anUnnamedEdgeIsRefused() {
        let unnamed = FaceInfo(
            id: FaceID(5), kind: .plane, normal: v(0, 0, 1), area: 1, centroid: v(0, 0, 0),
            tags: Fixture.tags(.unnamed(face: 7)))
        let topology = Fixture.plate(
            edges: [Fixture.line(0, v(0, 0, 0), v(10, 0, 0), between: 0, 5)], extraFaces: [unnamed])
        #expect(
            refused(anchor(.edge(EdgeID(0), stroke: 0), topology))
                == "This edge has no lasting name, so a dimension can't hold on to it.")
        // An unnamed key side: a face with no tags at all.
        let bare = FaceInfo(id: FaceID(6), kind: .plane, normal: v(0, 0, 1), area: 1, centroid: v(0, 0, 0), tags: [])
        let other = Fixture.plate(edges: [Fixture.line(0, v(0, 0, 0), v(10, 0, 0), between: 0, 6)], extraFaces: [bare])
        #expect(refused(anchor(.edge(EdgeID(0), stroke: 0), other)) == DrawingPick.noEdgeNameSentence)
    }

    @Test func anUnnamedKeySideIsRefused() {
        // A key whose one side holds an unnamed tag among named ones.
        let mixed = FaceInfo(
            id: FaceID(5), kind: .plane, normal: v(0, 0, 1), area: 1, centroid: v(0, 0, 0),
            tags: Fixture.tags(.side(segment: 9)).union(Fixture.tags(.unnamed(face: 3), of: Fixture.other)))
        let topology = Fixture.plate(edges: [Fixture.line(0, v(0, 0, 0), v(10, 0, 0), between: 0, 5)], extraFaces: [mixed])
        #expect(refused(anchor(.edge(EdgeID(0), stroke: 0), topology)) == DrawingPick.noEdgeNameSentence)
    }

    @Test func aSharedKeyIsRefused() {
        // Two separate edges between the same two faces: one key, two runs.
        let topology = Fixture.plate(edges: [
            Fixture.line(0, v(0, 0, 0), v(10, 0, 0), between: 0, 1),
            Fixture.line(1, v(0, 0, 20), v(10, 0, 20), between: 0, 1),
        ])
        #expect(
            refused(anchor(.edge(EdgeID(0), stroke: 0), topology))
                == "This line's edge shares its name with other edges, so a dimension can't hold on to it.")
    }

    @Test func aSplitEdgeIsAccepted() throws {
        let topology = Fixture.plate(edges: [
            Fixture.line(0, v(0, 0, 0), v(4, 0, 0), between: 0, 1),
            Fixture.line(1, v(4, 0, 0), v(10, 0, 0), between: 0, 1),
        ])
        let result = try #require(picked(anchor(.edge(EdgeID(1), stroke: 0), topology)))
        guard case .edge(let pick) = result.target else { Issue.record("not an edge"); return }
        #expect(pick.matchCount == 2 && pick.runCount == 1)
        // The shape is the whole run.
        #expect(result.shape == .line(Vector2(0, 0), Vector2(10, 0)))
    }

    @Test func aCornerAtASplitNamesATrueNeighbour() throws {
        // Edges 4 and 1 are one split run along x; edge 0 is collinear with a lower ID but another key, edge 2 crosses.
        let topology = Fixture.plate(edges: [
            Fixture.line(0, v(0, 0, 0), v(-6, 0, 0), between: 2, 3),
            Fixture.line(1, v(5, 0, 0), v(10, 0, 0), between: 0, 1),
            Fixture.line(2, v(0, 0, 0), v(0, 0, 8), between: 0, 2),
            Fixture.line(4, v(0, 0, 0), v(5, 0, 0), between: 0, 1),
        ])
        let result = try #require(picked(anchor(.corner(EdgeID(4), at: mapping.sheet(Vector2(0, 0))), topology)))
        #expect(result.target == .corner(Fixture.pick(topology, [4]), Fixture.pick(topology, [2])))
    }

    @Test func aJointInsideARunIsNotACorner() {
        let topology = Fixture.plate(edges: [
            Fixture.line(0, v(0, 0, 0), v(5, 0, 0), between: 0, 1),
            Fixture.line(1, v(5, 0, 0), v(10, 0, 0), between: 0, 1),
            Fixture.line(2, v(5, 0, 0), v(5, 0, 8), between: 0, 2),
        ])
        #expect(
            refused(anchor(.corner(EdgeID(0), at: mapping.sheet(Vector2(5, 0))), topology))
                == "This corner can't be named; dimension the edge instead.")
    }

    @Test func aDepthNeighbourStillNamesACorner() throws {
        // Edge 0 is a depth edge (along the view direction), the lowest ID at the corner: it names the point all the same.
        let topology = Fixture.plate(edges: [
            Fixture.line(0, v(0, 0, 0), v(0, 5, 0), between: 1, 3),
            Fixture.line(1, v(0, 0, 0), v(10, 0, 0), between: 0, 1),
        ])
        let result = try #require(picked(anchor(.corner(EdgeID(1), at: mapping.sheet(Vector2(0, 0))), topology)))
        #expect(result.target == .corner(Fixture.pick(topology, [1]), Fixture.pick(topology, [0])))
        #expect(result.shape == .point(Vector2(0, 0)))
    }

    @Test func anUnnamedCylinderIsRefused() {
        let unnamed = Fixture.cylinder(4, .unnamed(face: 4), axisPoint: v(0, 0, 5), axis: v(1, 0, 0))
        let topology = Fixture.plate(edges: [], extraFaces: [unnamed])
        #expect(
            refused(anchor(.outline(FaceID(4), stroke: 0), topology))
                == "This cylinder has no lasting name, so a dimension can't hold on to it.")
    }

    @Test func aCylinderWhoseNameIsSharedIsRefused() {
        let topology = Fixture.plate(
            edges: [],
            extraFaces: [
                Fixture.cylinder(4, .side(segment: 4), axisPoint: v(0, 0, 5), axis: v(1, 0, 0)),
                Fixture.cylinder(5, .side(segment: 4), axisPoint: v(0, 0, 5), axis: v(1, 0, 0)),
            ])
        #expect(
            refused(anchor(.outline(FaceID(4), stroke: 0), topology))
                == "This cylinder shares its name with other faces, so a dimension can't hold on to it.")
    }
}
