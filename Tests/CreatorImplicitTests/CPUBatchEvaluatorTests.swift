import CreatorGeometry
import Testing
@testable import CreatorImplicit

struct CPUBatchEvaluatorTests {
    @Test func theBatchAgreesWithTheReferenceToFloatPrecision() async throws {
        let solid = ImplicitFixtures.all[5].solid
        let random = SeededRandom(seed: 2, stream: 1)
        // More than one chunk, so the work is split across tasks.
        let points = (0..<9000).map { SIMD3<Float>(Float(random.unit(at: 3 * $0) * 30 - 15), Float(random.unit(at: 3 * $0 + 1) * 30 - 15),
                                                   Float(random.unit(at: 3 * $0 + 2) * 30 - 15)) }
        let values = try await CPUBatchEvaluator(solid).evaluate(points)
        #expect(values.count == points.count)
        for (point, value) in zip(points, values) {
            let reference = solid.signedDistance(at: Vector3(Double(point.x), Double(point.y), Double(point.z)))
            #expect(abs(Double(value) - reference) < 1e-5)
        }
        #expect(CPUBatchEvaluator(solid).engineName == "CPU")
    }

    @Test func anEmptyBatchIsEmpty() async throws {
        #expect(try await CPUBatchEvaluator(ImplicitFixtures.sphere).evaluate([]).isEmpty)
    }

    @Test func cancellingStopsTheBatch() async {
        let evaluator = CPUBatchEvaluator(ImplicitFixtures.all[5].solid)
        let points = [SIMD3<Float>](repeating: SIMD3(1, 2, 3), count: 50_000)
        let task = Task { try await evaluator.evaluate(points) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
