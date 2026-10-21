#if canImport(Metal)
import CreatorGeometry
import Synchronization
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

    /// The mapped lattices where the mapping is hardest: next to the singular set (the exclusion and its fade) and on both sides of
    /// the cut of the angle.
    @Test(arguments: LatticeFixtures.mappedAll.map(\.name))
    func mappedLatticesAgreeNextToTheSingularSetAndTheCut(_ name: String) async throws {
        let solid = try #require(LatticeFixtures.mappedAll.first { $0.name == name }?.solid)
        let engine = try #require(MetalImplicitEngine.shared)
        let centre = LatticeFixtures.crossing
        let random = SeededRandom(seed: 17, stream: 6)
        var points: [SIMD3<Float>] = (0..<400).map { index in
            SIMD3(Float(centre.x + 6 * random.unit(at: 3 * index) - 3), Float(centre.y + 6 * random.unit(at: 3 * index + 1) - 3),
                  Float(28 * random.unit(at: 3 * index + 2) - 14))
        }
        points += (0..<200).map { index in
            SIMD3(Float(centre.x) - 0.5 - Float(index) * 0.05, Float(centre.y) + (index % 2 == 0 ? 1e-3 : -1e-3), Float(index % 20) - 10)
        }
        let evaluator = GPUBatchEvaluator(engine: engine, program: try ImplicitCompiler.compile(solid))
        let gpu = try await evaluator.evaluate(points)
        let cpu = solid.signedDistances(at: points.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) })
        var worst = 0.0
        for index in cpu.indices { worst = max(worst, abs(Double(gpu[index]) - cpu[index])) }
        #expect(worst < Self.tolerance, "\(name): the largest difference is \(worst) mm")
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
        // The task cancels itself before it asks, so the answer cannot depend on timing.
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await evaluator.evaluate([SIMD3(1, 2, 3)])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancelEndsABatchAtItsNextDispatchAndNotTheOnesAfter() async throws {
        let engine = try #require(MetalImplicitEngine(dispatchSize: 1_000))
        let program = try ImplicitCompiler.compile(.sphere(radius: 5))
        let points = (0..<3_500).map { SIMD3<Float>(Float($0 % 100), 0, 0) }
        let dispatches = Mutex(0)
        // Cancel after the first dispatch, from the hook, so the second must not run.
        await engine.setAfterDispatch { count in
            dispatches.withLock { $0 = count }
            if count == 1 { await engine.cancel() }
        }
        await #expect(throws: CancellationError.self) { _ = try await engine.evaluate(program, at: points) }
        #expect(dispatches.withLock { $0 } == 1, "the second dispatch did not run")
        await engine.setAfterDispatch(nil)
        let whole = try await engine.evaluate(program, at: points)
        #expect(whole.count == points.count && abs(whole[3_499] - Float(3_499 % 100 - 5)) < 1e-5, "a later batch runs whole")
        let after = try await engine.evaluate(program, at: [SIMD3(7, 0, 0)])
        #expect(after.count == 1 && abs(after[0] - 2) < 1e-5)
    }

    @Test func aBatchOfSeveralSmallDispatchesIsAnsweredInOrder() async throws {
        let engine = try #require(MetalImplicitEngine(dispatchSize: 1_000))
        let program = try ImplicitCompiler.compile(.sphere(radius: 5))
        let points = (0..<2_500).map { SIMD3<Float>(Float($0 % 100), 0, 0) }
        let values = try await engine.evaluate(program, at: points)
        #expect(values.count == points.count)
        for index in [0, 999, 1_000, 2_499] { #expect(abs(values[index] - Float(index % 100 - 5)) < 1e-5) }
    }
}
#endif
