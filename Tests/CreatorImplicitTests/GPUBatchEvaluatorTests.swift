import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The code that depends on `ImplicitGPUEngine`, run against an engine that is the CPU underneath, so it is tested on every platform
/// (implicit spec Errata D11).
struct GPUBatchEvaluatorTests {
    @Test func aBatchGoesThroughTheEngineAndAnswersInOrder() async throws {
        let engine = StubGPUEngine()
        let program = try await engine.compile(.sphere(radius: 5))
        let evaluator = GPUBatchEvaluator(engine: engine, program: program)
        let values = try await evaluator.evaluate([SIMD3(7, 0, 0), SIMD3(0, 0, 0), SIMD3(0, 9, 0)])
        #expect(values == [2, -5, 4])
        #expect(evaluator.engineName == "Stub")
        let counts = await (engine.prepared, engine.evaluated)
        #expect(counts == (1, 1))
    }

    @Test func theDefaultCompileGeneratesAndPreparesTheProgram() async throws {
        let engine = StubGPUEngine()
        let program = try await engine.compile(.box(halfSize: Vector3(1, 1, 1), cornerRadius: 0))
        #expect(program.source.contains(CompiledImplicit.kernelName))
        let prepared = await engine.prepared
        #expect(prepared == 1)
    }

    @Test func aTreeTheGPUHasNoFormForIsReportedAsUnsupported() async {
        let profile = Profile2D.rectangle(width: 4, height: 4, plane: .xy)
        let graded = Grading(field: .distance(.profile(profile), signed: false), range: 0...10, slope: 1)
        let solid = ImplicitSolid.offset(.sphere(radius: 3), distance: graded)
        let engine = StubGPUEngine()
        await #expect(throws: ImplicitCompileError.self) { _ = try await engine.compile(solid) }
    }

    @Test func aCancelledTaskEndsTheBatch() async throws {
        let engine = StubGPUEngine()
        let program = try await engine.compile(.sphere(radius: 5))
        let evaluator = GPUBatchEvaluator(engine: engine, program: program)
        let task = Task { try await evaluator.evaluate([SIMD3(1, 2, 3)]) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func thePlatformEngineIsMetalOrNothing() async {
        // Where Metal exists and has a device this is the Metal engine; elsewhere it is nil and the CPU does everything.
        if let engine = ImplicitGPUEngines.platformDefault {
            #expect(engine.name == "Metal")
        } else {
            #expect(ImplicitGPUEngines.platformDefault == nil)
        }
    }
}
