import CreatorGeometry
import Foundation
@testable import CreatorImplicit

/// A GPU engine that is the CPU underneath, so the code that depends on `ImplicitGPUEngine` is tested on every platform.
actor StubGPUEngine: ImplicitGPUEngine {
    /// What `prepare` throws, when set.
    private let failure: ImplicitCompileError?
    private(set) var prepared = 0
    private(set) var evaluated = 0
    private(set) var cancels = 0
    private var solids: [UUID: ImplicitSolid] = [:]

    nonisolated let name = "Stub"
    var deviceName: String { "stub device" }

    init(failure: ImplicitCompileError? = nil) {
        self.failure = failure
    }

    /// Remembers which solid a program came from, so `evaluate` can answer with the CPU.
    func compile(_ solid: ImplicitSolid) async throws(ImplicitCompileError) -> CompiledImplicit {
        let program = try ImplicitCompiler.compile(solid)
        solids[program.id] = solid
        try await prepare(program)
        return program
    }

    func prepare(_ program: CompiledImplicit) async throws(ImplicitCompileError) {
        prepared += 1
        if let failure { throw failure }
    }

    func evaluate(_ program: CompiledImplicit, at points: [SIMD3<Float>]) async throws -> [Float] {
        try Task.checkCancellation()
        evaluated += 1
        guard let solid = solids[program.id] else { return points.map { _ in 0 } }
        return try await CPUBatchEvaluator(solid).evaluate(points)
    }

    func cancel() async {
        cancels += 1
    }
}
