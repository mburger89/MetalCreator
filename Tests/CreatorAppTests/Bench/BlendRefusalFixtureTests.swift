import CreatorKernel
import Testing
@testable import CreatorOCCT

/// `BlendRefusalBench`'s hexagon flange is a copy of `HexagonFlange` (CreatorOCCTTests, which this target can't
/// import). The bench only runs on request, so this checks the copy in every run: the original's four upright edges,
/// and R3 refused naming 2.5 mm (`InvalidBlendTests`).
@MainActor
struct BlendRefusalFixtureTests {
    @Test func theBenchFlangeIsTheOneThatBreaksAtR3() async throws {
        let kernel = OCCTKernel()
        let (union, edges) = try await BlendRefusalBench.flange(kernel)
        #expect(edges.count == 4)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.fillet(union, edges: edges, radius: 3, tag: BlendRefusalBench.tag())
        }
        #expect(error?.userMessage == "Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm).")
    }
}
