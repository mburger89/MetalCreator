import CreatorGeometry
import Foundation
@testable import CreatorImplicit

/// A GPU engine that is the CPU underneath, so the code that depends on `ImplicitGPUEngine` is tested on every platform.
actor StubGPUEngine: ImplicitGPUEngine {
    /// What `meshBricks` does.
    enum Meshing: Sendable {
        /// The protocol's default: this engine does not mesh.
        case unsupported
        /// Reports halfway, then returns this mesh whatever the request.
        case answers(BrickMesh)
        /// Throws this.
        case fails(ImplicitCompileError)
        /// Throws `CancellationError`, as an engine does when its task is cancelled between dispatches.
        case cancels
    }

    /// What `prepare` throws, when set.
    private let failure: ImplicitCompileError?
    private let meshing: Meshing
    /// The requests `meshBricks` was asked for, in order.
    private(set) var meshRequests: [BrickMeshRequest] = []
    private(set) var prepared = 0
    private(set) var evaluated = 0
    private(set) var cancels = 0
    private var solids: [UUID: ImplicitSolid] = [:]

    private let reported: ImplicitEngineAvailability

    nonisolated let name = "Stub"
    var availability: ImplicitEngineAvailability { reported }
    var deviceName: String { "stub device" }

    init(failure: ImplicitCompileError? = nil, meshing: Meshing = .unsupported, availability: ImplicitEngineAvailability = .available) {
        self.failure = failure
        self.meshing = meshing
        self.reported = availability
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

    func meshBricks(_ program: CompiledImplicit, _ request: BrickMeshRequest,
                    progress: @Sendable (Double) -> Void) async throws -> BrickMesh {
        meshRequests.append(request)
        switch meshing {
        case .unsupported: throw ImplicitCompileError.unsupported("meshing bricks")
        case .answers(let mesh):
            progress(0.5)
            return mesh
        case .fails(let error): throw error
        case .cancels: throw CancellationError()
        }
    }
}
