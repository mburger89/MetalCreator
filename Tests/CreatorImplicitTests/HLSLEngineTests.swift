import CreatorGeometry
import Synchronization
import Testing
@testable import CreatorImplicit

/// The HLSL engine's dispatching and pipeline cache (plan xp-c), the same code over every backend; skipped, by name, where there is none.
@Suite(.enabled(if: GPUEnginesUnderTest.hlsl != nil, "needs the HLSL engine: \(GPUEnginesUnderTest.unavailableReason)"))
struct HLSLEngineTests {
    /// Review Focus 3: one pipeline a shape, and a number edit compiles nothing.
    @Test func shapesShareOnePipelineAndANumberEditRecompilesNothing() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeHLSL())
        let first = try ImplicitCompiler.compileHLSL(.sphere(radius: 5))
        let second = try ImplicitCompiler.compileHLSL(.sphere(radius: 25))
        try await engine.prepare(first)
        try await engine.prepare(second)
        #expect(await engine.compileCount == 1)
        let values = try await GPUBatchEvaluator(engine: engine, program: second).evaluate([SIMD3(30, 0, 0)])
        #expect(abs(values[0] - 5) < 1e-5, "the numbers still differ")
        try await engine.prepare(try ImplicitCompiler.compileHLSL(.box(halfSize: Vector3(1, 1, 1), cornerRadius: 0)))
        #expect(await engine.compileCount == 2)
    }

    @Test func aBatchOfSeveralSmallDispatchesIsAnsweredInOrder() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeHLSL(dispatchSize: 1_000))
        let program = try await engine.compile(.sphere(radius: 5))
        let points = (0..<2_500).map { SIMD3<Float>(Float($0 % 100), 0, 0) }
        let values = try await engine.evaluate(program, at: points)
        #expect(values.count == points.count)
        for index in [0, 999, 1_000, 2_499] { #expect(abs(values[index] - Float(index % 100 - 5)) < 1e-5) }
    }

    @Test func anEmptyBatchAndACancelledOneAreHandled() async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let evaluator = GPUBatchEvaluator(engine: engine, program: try await engine.compile(.sphere(radius: 5)))
        #expect(try await evaluator.evaluate([]).isEmpty)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await evaluator.evaluate([SIMD3(1, 2, 3)])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancelEndsABatchAtItsNextDispatchAndNotTheOnesAfter() async throws {
        let engine = try #require(GPUEnginesUnderTest.makeHLSL(dispatchSize: 1_000))
        let program = try await engine.compile(.sphere(radius: 5))
        let points = (0..<3_500).map { SIMD3<Float>(Float($0 % 100), 0, 0) }
        let dispatches = Mutex(0)
        await engine.setAfterDispatch { count in
            dispatches.withLock { $0 = count }
            if count == 1 { await engine.cancel() }
        }
        await #expect(throws: CancellationError.self) { _ = try await engine.evaluate(program, at: points) }
        #expect(dispatches.withLock { $0 } == 1, "the second dispatch did not run")
        await engine.setAfterDispatch(nil)
        let whole = try await engine.evaluate(program, at: points)
        #expect(whole.count == points.count && abs(whole[3_499] - Float(3_499 % 100 - 5)) < 1e-5)
    }

    @Test func aMetalCompiledSolidIsNotThisEngines() async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        await #expect(throws: ImplicitCompileError.self) { try await engine.prepare(try ImplicitCompiler.compile(.sphere(radius: 1))) }
    }

    /// Review Focus 5: the angle exactly on a mapping's cut and at its axis.
    @Test(arguments: LatticeFixtures.mappedAll.map(\.name))
    func theAngleOnTheCutAndAtTheAxisAgreesWithTheCPU(_ name: String) async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let solid = try #require(LatticeFixtures.mappedAll.first { $0.name == name }?.solid)
        let centre = LatticeFixtures.crossing
        var points: [SIMD3<Float>] = []
        for step in 0..<40 {
            let along = Float(step) * 0.25 - 5
            points.append(SIMD3(Float(centre.x) + along, Float(centre.y), Float(step % 9) - 4))
            points.append(SIMD3(Float(centre.x), Float(centre.y), along))
        }
        let gpu = try await GPUBatchEvaluator(engine: engine, program: try await engine.compile(solid)).evaluate(points)
        let cpu = solid.signedDistances(at: points.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) })
        var worst = 0.0
        for index in cpu.indices { worst = max(worst, abs(Double(gpu[index]) - cpu[index])) }
        #expect(worst < GPUAgreementTests.tolerance, "\(name): the largest difference is \(worst) mm")
    }
}
