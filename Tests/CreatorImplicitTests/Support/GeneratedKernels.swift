import CreatorGeometry
import Foundation
@testable import CreatorImplicit

/// The HLSL kernels the tests run before MetalUI's run-time compiler exists (plan xp-c, task 3; gap XP-G25): every shape a GPU test or bench uses,
/// its seven sources exported as `<digest>.comp.hlsl` and compiled offline in the Linux image by the build-time SDL_shadercross
/// (`scripts/linux-test.sh kernels`) into `.build/generated-kernels/compiled`. A shape not in `solids` has no compiled kernel and its test fails
/// naming the script: add the shape here.
enum GeneratedKernels {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: ".build/generated-kernels")
    static let source = root.appending(path: "source")
    static let compiled = root.appending(path: "compiled")
    static let remedy = "run XP_TRACK=xp-c IMAGE=metalcreator-linux:xp-c scripts/linux-test.sh kernels"

    /// Every solid whose shape a GPU test or bench compiles (numbers do not matter: a shape is its source).
    static var solids: [(name: String, solid: ImplicitSolid)] {
        let ball = ImplicitSolid.sphere(radius: 10)
        let move = RigidMove(origin: Vector3(4_000, -3_000, 2_500), xAxis: .unitX, yAxis: .unitY, zAxis: .unitZ)
        return GPUFixtures.all + LatticeFixtures.everyMapped + ImplicitFixtures.all + [
            ("sphere", ball), ("moved sphere", .moved(ball, move)), ("box", .box(halfSize: Vector3(1, 1, 1), cornerRadius: 0)),
            ("bench sheet", ImplicitBenchHLSL.sheet(wall: 3)),
        ]
    }

    /// The distinct kernel sources of `solids`.
    static var sources: [KernelSource] {
        var seen: Set<String> = []
        var all: [KernelSource] = []
        for (_, solid) in solids {
            guard let compiled = try? ImplicitCompiler.compileHLSL(solid) else { continue }
            for kernel in ImplicitKernel.allCases {
                guard let source = compiled.kernels[kernel], seen.insert(source.digest).inserted else { continue }
                all.append(source)
            }
        }
        return all
    }
}
