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

    /// The points Review Focus 5 samples: along the cut (y = the centre's) and across the axis (x = the centre's). `offset` moves the
    /// ones along the cut to one side or the other, as `GPUAgreementTests` does with 1e-3 (spec D15, D17: "either side of the cut").
    private static func cutAndAxisPoints(offset: Float) -> [SIMD3<Float>] {
        let centre = LatticeFixtures.crossing
        var points: [SIMD3<Float>] = []
        for step in 0..<40 {
            let along = Float(step) * 0.25 - 5
            let side: Float = step % 2 == 0 ? offset : -offset
            points.append(SIMD3(Float(centre.x) + along, Float(centre.y) + side, Float(step % 9) - 4))
            points.append(SIMD3(Float(centre.x), Float(centre.y), along))
        }
        return points
    }

    /// Review Focus 5: the angle just either side of a mapping's cut and at its axis agrees with the CPU within the spec's 1e-4 mm.
    /// Ruling: exactly on the cut (y = centre.y) the angle is the branch of `atan2` at its discontinuity, which Float and Double
    /// resolve differently (5.7e-4 mm on the Neovius sphere, and `MetalImplicitEngine` differs by the same), so that line is sampled
    /// at y = centre.y +- 1e-3 here and compared exactly, to the Metal engine, in the next test.
    @Test(arguments: LatticeFixtures.mappedAll.map(\.name))
    func theAngleOnTheCutAndAtTheAxisAgreesWithTheCPU(_ name: String) async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let solid = try #require(LatticeFixtures.mappedAll.first { $0.name == name }?.solid)
        let points = Self.cutAndAxisPoints(offset: 1e-3)
        let gpu = try await GPUBatchEvaluator(engine: engine, program: try await engine.compile(solid)).evaluate(points)
        let cpu = solid.signedDistances(at: points.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) })
        var worst = 0.0
        for index in cpu.indices { worst = max(worst, abs(Double(gpu[index]) - cpu[index])) }
        #expect(worst < GPUAgreementTests.tolerance, "\(name): the largest difference is \(worst) mm")
    }

    #if canImport(Metal)
    /// The property that holds exactly on the cut: the HLSL engine (here over the MSL) and `MetalImplicitEngine` run the same Float
    /// arithmetic, so they agree to Float rounding (measured 1.07e-6 mm, one ulp of a value near 10 mm; allowed 5e-6) where both differ from
    /// the CPU's Double by 5.7e-4 mm.
    @Test(arguments: LatticeFixtures.mappedAll.map(\.name))
    func onTheCutTheHLSLEngineAgreesWithTheMetalEngine(_ name: String) async throws {
        let engine = try #require(GPUEnginesUnderTest.hlsl)
        let metal = try #require(MetalImplicitEngine.shared)
        let solid = try #require(LatticeFixtures.mappedAll.first { $0.name == name }?.solid)
        var points = Self.cutAndAxisPoints(offset: 0)
        // The Neovius fixture has a noisy wall (`ImplicitFixtures.noisy`, 2 octaves), and the point (10, 4, -3) puts the second octave (size 3)
        // exactly on a simplex boundary: x/3 and y/3 are both 1/3 after skewing, a tie that Float breaks by one ulp, and which side it
        // breaks to decides the simplex. The kernel's radius is the standard 0.6 (Gustavson), not the 0.5 that makes the noise continuous
        // across a boundary, so the two simplexes differ by a fixed 1.95e-4 mm of wall (9.7e-5 mm in the distance, for every z on the
        // line). The HLSL engine's tie falls as the CPU's Double does, the Metal engine's the other way, and the engines then differ
        // by 9.66e-5 mm (measured). That is the noise's seam, not a disagreement, so this case is sampled 1e-3 mm off it in x and 3.7e-3 in z (y stays
        // on the cut; a move of 1e-4 already gives 0 to 2e-6, and z keeps the other points off x0 = z0 and y0 = z0 ties) and, like every
        // other case, held to 5e-6 (measured worst there: 4.6e-6, the mapped coordinates' own Float rounding).
        if name.hasPrefix("neovius") { points = points.map { SIMD3($0.x + 1e-3, $0.y, $0.z + 3.7e-3) } }
        let hlsl = try await GPUBatchEvaluator(engine: engine, program: try await engine.compile(solid)).evaluate(points)
        let reference = try await GPUBatchEvaluator(engine: metal, program: try await metal.compile(solid)).evaluate(points)
        var worst: Float = 0
        for index in hlsl.indices { worst = max(worst, abs(hlsl[index] - reference[index])) }
        #expect(worst < 5e-6, "\(name): the largest difference from the Metal engine is \(worst) mm")
    }
    #endif
}
