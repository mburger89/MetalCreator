import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// Every GPU engine this machine has against the CPU reference (implicit spec §4.1, §7, Errata D11, D21): every node and every field kind on a fixed
/// point set, within 1e-4 mm. Engines: Metal (a Mac with a device); the HLSL engine as "Metal (HLSL)" on a Mac where `scripts/linux-test.sh kernels`
/// compiled the generated kernels, as "Vulkan" on Linux and "Direct3D 12" on Windows over SDL_GPU. With none the suite is skipped, by name.
@Suite(.enabled(if: !GPUEnginesUnderTest.names.isEmpty, "needs a GPU engine: \(GPUEnginesUnderTest.unavailableReason)"))
struct GPUAgreementTests {
    static let tolerance = 1e-4

    @Test(arguments: GPUEnginesUnderTest.names, GPUFixtures.all.map(\.name))
    func theGPUAgreesWithTheCPU(_ engineName: String, _ name: String) async throws {
        let solid = try #require(GPUFixtures.all.first { $0.name == name }?.solid)
        let engine = try GPUEnginesUnderTest.engine(engineName)
        let evaluator = GPUBatchEvaluator(engine: engine, program: try await engine.compile(solid))
        let gpu = try await evaluator.evaluate(GPUFixtures.points)
        let cpu = solid.signedDistances(at: GPUFixtures.points.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) })
        #expect(gpu.count == cpu.count)
        var worst = 0.0
        for index in cpu.indices { worst = max(worst, abs(Double(gpu[index]) - cpu[index])) }
        #expect(worst < Self.tolerance, "\(engineName), \(name): the largest difference is \(worst) mm")
        #expect(evaluator.engineName == engine.name)
    }

    @Test(arguments: GPUEnginesUnderTest.names, LatticeFixtures.everyMapped.map(\.name))
    func mappedLatticesAgreeNextToTheSingularSetAndTheCut(_ engineName: String, _ name: String) async throws {
        let solid = try #require(LatticeFixtures.everyMapped.first { $0.name == name }?.solid)
        let engine = try GPUEnginesUnderTest.engine(engineName)
        let centre = LatticeFixtures.crossing
        let random = SeededRandom(seed: 17, stream: 6)
        var points: [SIMD3<Float>] = (0..<400).map { index in
            SIMD3(Float(centre.x + 6 * random.unit(at: 3 * index) - 3), Float(centre.y + 6 * random.unit(at: 3 * index + 1) - 3),
                  Float(28 * random.unit(at: 3 * index + 2) - 14))
        }
        points += (0..<200).map { index in
            SIMD3(Float(centre.x) - 0.5 - Float(index) * 0.05, Float(centre.y) + (index % 2 == 0 ? 1e-3 : -1e-3), Float(index % 20) - 10)
        }
        let evaluator = GPUBatchEvaluator(engine: engine, program: try await engine.compile(solid))
        let gpu = try await evaluator.evaluate(points)
        let cpu = solid.signedDistances(at: points.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) })
        var worst = 0.0
        for index in cpu.indices { worst = max(worst, abs(Double(gpu[index]) - cpu[index])) }
        #expect(worst < Self.tolerance, "\(engineName), \(name): the largest difference is \(worst) mm")
    }
}
