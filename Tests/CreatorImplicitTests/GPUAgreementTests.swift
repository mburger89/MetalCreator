#if canImport(Metal)
import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The GPU against the CPU reference (implicit spec §4.1, §7): every node and every field kind on a fixed point set, within 1e-4 mm.
/// Compiled only where Metal exists, and skipped on a machine without a Metal device.
@Suite(.enabled(if: MetalImplicitEngine.shared != nil, "needs a Metal device"))
struct GPUAgreementTests {
    static let tolerance = 1e-4

    @Test(arguments: GPUFixtures.all.map(\.name))
    func theGPUAgreesWithTheCPU(_ name: String) async throws {
        let solid = try #require(GPUFixtures.all.first { $0.name == name }?.solid)
        let engine = try #require(MetalImplicitEngine.shared)
        let evaluator = GPUBatchEvaluator(engine: engine, program: try ImplicitCompiler.compile(solid))
        let gpu = try await evaluator.evaluate(GPUFixtures.points)
        let cpu = solid.signedDistances(at: GPUFixtures.points.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) })
        #expect(gpu.count == cpu.count)
        var worst = 0.0
        for index in cpu.indices { worst = max(worst, abs(Double(gpu[index]) - cpu[index])) }
        #expect(worst < Self.tolerance, "\(name): the largest difference is \(worst) mm")
        #expect(evaluator.engineName == "Metal")
    }

    @Test func shapesShareOnePipeline() async throws {
        let engine = try #require(MetalImplicitEngine())
        let first = try ImplicitCompiler.compile(.sphere(radius: 5))
        let second = try ImplicitCompiler.compile(.sphere(radius: 25))
        try await engine.prepare(first)
        try await engine.prepare(second)
        #expect(await engine.compileCount == 1)
        let values = try await GPUBatchEvaluator(engine: engine, program: second).evaluate([SIMD3(30, 0, 0)])
        #expect(abs(values[0] - 5) < 1e-5, "the numbers still differ")
        try await engine.prepare(try ImplicitCompiler.compile(.box(halfSize: Vector3(1, 1, 1), cornerRadius: 0)))
        #expect(await engine.compileCount == 2)
    }

    @Test func aBatchLargerThanOneDispatchIsAnswered() async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let evaluator = GPUBatchEvaluator(engine: engine, program: try ImplicitCompiler.compile(.sphere(radius: 5)))
        let points = (0..<(MetalImplicitEngine.pointsPerDispatch + 10)).map { SIMD3<Float>(Float($0 % 100), 0, 0) }
        let values = try await evaluator.evaluate(points)
        let last = points.count - 1
        #expect(values.count == points.count && abs(values[7] - 2) < 1e-5)
        #expect(abs(values[last] - Float(last % 100 - 5)) < 1e-5)
    }

    @Test func anEmptyBatchAndACancelledOneAreHandled() async throws {
        let engine = try #require(MetalImplicitEngine.shared)
        let evaluator = GPUBatchEvaluator(engine: engine, program: try ImplicitCompiler.compile(.sphere(radius: 5)))
        #expect(try await evaluator.evaluate([]).isEmpty)
        let task = Task { try await evaluator.evaluate([SIMD3(1, 2, 3)]) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancelEndsTheBatchesInFlightAndNotTheOnesAfter() async throws {
        let engine = try #require(MetalImplicitEngine())
        let program = try ImplicitCompiler.compile(.sphere(radius: 5))
        let points = (0..<(MetalImplicitEngine.pointsPerDispatch * 3)).map { SIMD3<Float>(Float($0 % 100), 0, 0) }
        let running = Task { try await engine.evaluate(program, at: points) }
        await engine.cancel()
        // Either the cancel came before the batch started (it ran whole) or after its first dispatch (it ended): never a wrong answer.
        do {
            let values = try await running.value
            #expect(values.count == points.count)
        } catch {
            #expect(error is CancellationError)
        }
        let after = try await engine.evaluate(program, at: [SIMD3(7, 0, 0)])
        #expect(after.count == 1 && abs(after[0] - 2) < 1e-5)
    }
}
#endif
