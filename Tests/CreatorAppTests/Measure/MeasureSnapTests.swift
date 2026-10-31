import CreatorGeometry
import CreatorKernel
import CreatorViewport
import Testing

@testable import CreatorApp

struct MeasureSnapTests {
    private let project: (Vector3) -> ScreenPoint? = { ScreenPoint($0.x, $0.y) }

    private func snap(_ target: PickTarget?, at point: ScreenPoint, edges: [EdgeInfo] = [], mesh: DisplayMesh? = nil) -> MeasurePick? {
        MeasureSnap.pick(for: target, at: point, topology: Topology(faces: [], edges: edges), mesh: mesh, screenPoint: project)
    }

    private let edge = PickTarget.edge(solid: 0, EdgeID(0))

    @Test func nearAnEndSnapsToTheCorner() {
        let line = MeasureFixtures.line(0, from: .zero, to: Vector3(100, 0, 0))
        #expect(snap(edge, at: ScreenPoint(4, 0), edges: [line]) == .corner(solid: 0, EdgeID(0), .start, at: .zero))
        #expect(snap(edge, at: ScreenPoint(30, 0), edges: [line]) == .edge(solid: 0, EdgeID(0)))
        #expect(snap(edge, at: ScreenPoint(97, 0), edges: [line]) == .corner(solid: 0, EdgeID(0), .end, at: Vector3(100, 0, 0)))
    }

    @Test func aFullCircleOffersItsCentre() {
        let circle = MeasureFixtures.circle(0, centre: Vector3(50, 50, 0), radius: 20, sweep: 2 * .pi)
        #expect(snap(edge, at: ScreenPoint(52, 49), edges: [circle]) == .corner(solid: 0, EdgeID(0), .centre, at: Vector3(50, 50, 0)))
        #expect(snap(edge, at: ScreenPoint(70, 50), edges: [circle]) == .edge(solid: 0, EdgeID(0)))
    }

    @Test func facesAndNothing() {
        #expect(snap(.face(solid: 0, FaceID(2)), at: .init(0, 0)) == .face(solid: 0, FaceID(2)))
        #expect(snap(nil, at: .init(0, 0)) == nil)
    }

    @Test func aCurvelessEdgeUsesItsPolyline() {
        let mesh = DisplayMesh(positions: [], normals: [], indices: [], triangleFaces: [],
                               edgePolylines: [EdgeID(0): [Vector3(0, 0, 0), Vector3(50, 0, 0), Vector3(100, 0, 0)]])
        #expect(snap(edge, at: ScreenPoint(99, 3), mesh: mesh) == .corner(solid: 0, EdgeID(0), .end, at: Vector3(100, 0, 0)))
    }
}
