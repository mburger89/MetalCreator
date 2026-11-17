import CreatorGeometry
import Testing
@testable import CreatorKernel

struct FakeCurveTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    @Test func aClosedTriangle() async throws {
        let a = Vector3(0, 0, 0), b = Vector3(3, 0, 0), c = Vector3(0, 4, 0)
        let curve = try await FakeKernel().makeCurve([.line(a, b), .line(b, c), .line(c, a)], tag: tag)
        #expect(curve.isClosed && curve.pieceCount == 3)
        #expect(abs(curve.length - 12) < 1e-9)
        #expect(curve.plane != nil)
    }

    @Test func piecesThatDontJoinAreRefused() async {
        let pieces: [CurvePiece] = [.line(.zero, Vector3(1, 0, 0)), .line(Vector3(2, 0, 0), Vector3(3, 0, 0))]
        await #expect(throws: KernelError.invalidInput("The curve's pieces don't join end to end.")) {
            try await FakeKernel().makeCurve(pieces, tag: tag)
        }
    }

    @Test func aSplinePieceIsItsControlPolygon() async throws {
        let poles = (0..<6).map { Vector3(Double($0), 0, 0) }
        let spline = BSplineCurve3D(degree: 5, poles: poles, knots: [0, 1], multiplicities: [6, 6])
        let curve = try await FakeKernel().makeCurve([.spline(spline)], tag: tag)
        #expect(curve.polyline == poles && !curve.isClosed && abs(curve.length - 5) < 1e-9)
    }
}
