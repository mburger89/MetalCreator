import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// The noisy fixtures' fields at fixed points on every GPU engine against the CPU, naming the first point that differs and both values
/// (plan xp-c, the Windows failure of `GPUMeshAgreementTests` on "noisy shell": the D3D12 mesh had non-finite vertices while the
/// random-point agreement suite passed). The points are the ones the noise code is most likely to get wrong: negative coordinates,
/// and the multiples of the noise's cell sizes (6 and 3 mm for the fixture's seed 4, scale 6, two octaves) a hair either side
/// of the simplex lattice's boundaries, besides a lattice of the mesher's spacing (shifted off the origin, where x = -y and z = 0 sit on a boundary). Not *on* a boundary: the kernel radius 0.6 makes the
/// noise jump there by about 2e-3, so which side a point falls on is a rounding (measured on Metal at (6.001, -0.001, 3.0): 1.8e-3). When this fails on a CI engine its message is
/// the diagnosis.
@Suite(.enabled(if: !GPUEnginesUnderTest.names.isEmpty, "needs a GPU engine: \(GPUEnginesUnderTest.unavailableReason)"))
struct GPUNoiseDiagnosticTests {
    static let names = ["noisy shell", "noisy smooth union"]

    /// Multiples of the noise cell on and either side of its boundary, in every sign; and the mesher's lattice for the noisy shell.
    static let points: [SIMD3<Float>] = {
        let stops: [Float] = [-7.5, -6, -4.5, -3, -1.5, 0, 1.5, 3, 4.5, 6, 7.5]
        // A different hair on each axis: with one hair, x - y is a whole number of cells and the three barycentric offsets tie.
        func axis(_ hair: Float) -> [Float] { stops.flatMap { [$0 - hair, $0 + hair] } }
        var points: [SIMD3<Float>] = []
        for x in axis(0.0137) { for y in axis(0.0291) { for z in axis(0.0571) where abs(z) <= 5 { points.append(SIMD3(x, y, z)) } } }
        let step: Float = 0.53
        for ix in -16...16 {
            for iy in -12...12 {
                for iz in -8...8 { points.append(SIMD3(Float(ix) * step + 0.0713, Float(iy) * step + 0.0291, Float(iz) * step + 0.0457)) }
            }
        }
        return points + GPUFixtures.points
    }()

    @Test(arguments: GPUEnginesUnderTest.names, names)
    func theNoisyFieldAgreesAtTheFixedPoints(_ engineName: String, _ name: String) async throws {
        let solid = try #require(GPUFixtures.all.first { $0.name == name }?.solid)
        let engine = try GPUEnginesUnderTest.engine(engineName)
        let evaluator = GPUBatchEvaluator(engine: engine, program: try await engine.compile(solid))
        let gpu = try await evaluator.evaluate(Self.points)
        let cpu = solid.signedDistances(at: Self.points.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) })
        var worst = (index: 0, difference: 0.0)
        var nonFinite = 0
        for index in cpu.indices {
            if !gpu[index].isFinite { nonFinite += 1; if worst.difference.isFinite { worst = (index, .infinity) } }
            let difference = abs(Double(gpu[index]) - cpu[index])
            if difference > worst.difference || difference.isNaN { worst = (index, difference.isNaN ? .infinity : difference) }
        }
        let point = Self.points[worst.index]
        #expect(nonFinite == 0 && worst.difference < 1e-4,
                """
                \(engineName), \(name): \(nonFinite) non-finite values of \(cpu.count); the first worst point is \(point) with \
                GPU \(gpu[worst.index]) against CPU \(cpu[worst.index])
                """)
    }

    /// The GPU mesh of a noisy fixture has only finite vertices and normals; if not, the first bad vertex, its neighbours in the mesh
    /// and the CPU's field at them.
    @Test(arguments: GPUEnginesUnderTest.names, names)
    func theGPUMeshHasOnlyFiniteVertices(_ engineName: String, _ name: String) async throws {
        let solid = try #require(GPUFixtures.all.first { $0.name == name }?.solid)
        let engine = try GPUEnginesUnderTest.engine(engineName)
        let selection = await ImplicitEvaluators.make(for: solid, choice: .automatic, engine: engine)
        let result = try await ImplicitMesher(evaluator: selection.evaluator)
            .meshReportingPath(solid, resolution: GPUMeshAgreementTests.resolution(of: solid), quality: .preview)
        let mesh = result.mesh
        let broken = mesh.positions.indices.filter { !(mesh.positions[$0] * 0).sum().isFinite || !(mesh.normals[$0] * 0).sum().isFinite }
        guard let first = broken.first else { return }
        var neighbours: Set<Int> = []
        for corner in stride(from: 0, to: mesh.triangles.count, by: 3) {
            let triangle = (0..<3).map { Int(mesh.triangles[corner + $0]) }
            if triangle.contains(first) { neighbours.formUnion(triangle) }
        }
        let finite = neighbours.sorted().filter { !broken.contains($0) }
        let evaluator = GPUBatchEvaluator(engine: engine, program: try await engine.compile(solid))
        let onGPU = try await evaluator.evaluate(finite.map { mesh.positions[$0] })
        let report = finite.indices.map { at -> String in
            let (index, p) = (finite[at], mesh.positions[finite[at]])
            let field = solid.signedDistances(at: [Vector3(Double(p.x), Double(p.y), Double(p.z))])[0]
            return "vertex \(index) at \(p) normal \(mesh.normals[index]) field: CPU \(field), GPU \(onGPU[at])"
        }
        let (position, normal) = (mesh.positions[first], mesh.normals[first])
        #expect(broken.isEmpty,
                """
                \(engineName), \(name): \(broken.count) of \(mesh.positions.count) vertices are not finite; the first is \(first) at \
                \(position) with normal \(normal); its finite neighbours: \(report)
                """)
    }
}
