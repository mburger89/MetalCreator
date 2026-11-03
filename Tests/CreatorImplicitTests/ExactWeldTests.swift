import Testing
@testable import CreatorImplicit

@Suite struct ExactWeldTests {
    @Test func minusZeroWeldsWithZero() {
        let corners: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0],
                                       [-0.0, -0.0, 0], [0, 0, 1], [1, 0, 0],
                                       ]
        let result = ExactWeld.weld(corners: corners)
        #expect(result.positions.count == 4)
        #expect(result.triangles == [0, 1, 2, 0, 3, 1])
        #expect(result.dropped == 0)
    }

    @Test func nearlyEqualIsNotWelded() {
        let corners: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0],
                                       [Float(1).nextUp, 0, 0], [0, 1, 0], [0, 0, 1],
                                       ]
        #expect(ExactWeld.weld(corners: corners).positions.count == 5)
    }

    @Test func aZeroAreaTriangleIsDroppedAndCounted() {
        let corners: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0],
                                       [0, 0, 0], [1, 0, 0], [0, 0, 0],
                                       ]
        let result = ExactWeld.weld(corners: corners)
        #expect(result.dropped == 1)
        #expect(result.triangles == [0, 1, 2])
    }
}
