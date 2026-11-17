import Testing
@testable import CreatorGeometry

struct CurvePieceTests {
    let plane = Plane(origin: Vector3(0, 0, 5), normal: .unitZ, xAxis: .unitX)

    @Test func segmentsLandOnThePlane() {
        let spline = SplineCurve2D(poles: (0..<6).map { Vector2(Double($0), Double($0 * $0)) }, knots: [0, 1],
                                   multiplicities: [6, 6])
        let pieces = CurvePiece.pieces(of: [
            .line(Vector2(0, 0), Vector2(2, 0)),
            .arc(center: Vector2(2, 1), radius: 1, start: Angle(radians: -.pi / 2), end: Angle(radians: .pi / 2)),
            .spline(spline),
        ], on: plane)
        #expect(pieces.count == 3)
        for piece in pieces {
            #expect(abs(piece.start.z - 5) < 1e-12 && abs(piece.end.z - 5) < 1e-12)
        }
        #expect((pieces[0].end - Vector3(2, 0, 5)).length < 1e-12)
        #expect((pieces[1].start - Vector3(2, 0, 5)).length < 1e-12)
        #expect((pieces[1].end - Vector3(2, 2, 5)).length < 1e-12)
        guard case .spline(let curve) = pieces[2] else { Issue.record("not a spline"); return }
        #expect(curve.degree == 5 && curve.poles.count == 6 && curve.poles.allSatisfy { abs($0.z - 5) < 1e-12 })
    }

    @Test func aClockwiseArcSweepsNegatively() {
        let pieces = CurvePiece.pieces(of: [
            .arc(center: Vector2(0, 0), radius: 2, start: Angle(radians: .pi / 2), end: Angle(radians: 0))
        ], on: plane)
        guard case .arc(_, _, _, _, let sweep) = pieces[0] else { Issue.record("not an arc"); return }
        #expect(sweep < 0 && abs(sweep + .pi / 2) < 1e-12)
        #expect((pieces[0].end - Vector3(2, 0, 5)).length < 1e-12)
    }
}
