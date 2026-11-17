import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Synchronization
import Testing
@testable import CreatorNodes

#if canImport(CreatorOCCT)
@testable import CreatorOCCT

/// The mesh budgets and `Inline` warnings of the KI-3 final review.
extension ImportKiCadMeshComponentsTests {
    @Test func severalFootprintsOverTheLimitAreNamedTogether() async throws {
        try write(Self.vrml(), "v.wrl")  // 20 triangles each
        let parts = [60.0, 70, 80].enumerated().map { part("U\($0 + 1)", x: $1, models: [model("v.wrl")]) }
        let (many, manyNode, _) = try board(parts)
        let plural = try await go(many, manyNode, limits: MeshLimits(footprint: 15, board: 1_000))
        let expected = "3 components' meshes were left out because each has more than 15 triangles together: U1, U2, U3."
        #expect(warnings(plural, manyNode) == [expected])
        #expect(meshes(plural, manyNode).isEmpty)
    }

    @Test func pointsOfLeftOutFootprintsAreNeverMoved() async throws {
        try write(Self.vrml(), "v.wrl")  // 20 triangles each
        let parts = (1...6).map { part("U\($0)", x: Double($0) * 10, models: [model("v.wrl")]) }
        let (h, node, _) = try board(parts)
        let moves = Mutex(0)
        let environment = environment
        let observer: @Sendable (Int) -> Void = { _ in moves.withLock { $0 += 1 } }
        let report = try await BoardComponents.$meshMoveObserver.withValue(observer) {
            try await BoardComponents.$meshLimits.withValue(MeshLimits(footprint: 1_000, board: 50)) {
                try await BoardComponents.$environment.withValue(environment) { try await h.run([node], kernel: kernel) }
            }
        }
        #expect(meshes(report, node).count == 2)
        #expect(moves.withLock { $0 } == 2)
        #expect(warnings(report, node) == ["4 component meshes were left out: a board's meshes are limited to 50 triangles."])
        #expect(try facts(report, node)["Components"] == "6 placed, 0 as solids, 2 as meshes, 0 without a 3D model")
    }

    @Test func inlineOnlyFilesWarnAboutOtherFiles() async throws {
        try write("#VRML V2.0 utf8\nInline { url \"a.wrl\" }", "in.wrl")
        try write(Self.vrml(extra: Self.sphere + "Inline { url \"a.wrl\" }"), "both.wrl")
        let (h, node, _) = try board([part("U1", models: [model("in.wrl")]), part("U2", x: 60, models: [model("both.wrl")])])
        let lines = warnings(try await go(h, node), node)
        #expect(lines.contains("in.wrl refers to other files, which aren't read."), "\(lines)")
        #expect(!lines.contains { $0.hasPrefix("in.wrl has shapes") }, "\(lines)")
        #expect(lines.contains("both.wrl refers to other files, which aren't read."), "\(lines)")
        #expect(lines.contains("both.wrl has shapes that aren't read (spheres, cylinders and the like)."), "\(lines)")
    }
}
#endif
