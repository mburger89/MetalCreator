import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct FeatureConformanceTests {
    /// The four 30 mm vertical edges of a 10 × 20 × 30 box.
    func verticalEdges(_ solid: Solid) -> [EdgeInfo] {
        solid.topology.edges.filter { $0.kind == .line && isClose($0.length, 30) }
    }

    @Test(arguments: KernelUnderTest.allCases)
    func filletRemovesTheAnalyticVolumeAndNamesTheBlend(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try #require(verticalEdges(solid).first)
        let key = try #require(solid.topology.key(of: edge))
        let filletTag = newTag()
        let result = try await kernel.fillet(solid, edges: [edge.id], radius: 2, tag: filletTag)
        #expect(isClose(try await kernel.properties(of: result).volume, 6000 - (4 - Double.pi) * 30))
        #expect(result.topology.faces.count == 7)
        let blends = faces(result, role: .blend(sourceEdge: key), of: filletTag)
        #expect(blends.count == 1)
        #expect(blends.first?.kind == .cylinder)
        // The six original faces keep their extrude tags.
        #expect(result.topology.faces.filter { face in face.tags.contains { $0.node != filletTag.node } }.count == 6)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func filletingAllVerticalEdgesKeepsEveryFaceNamed(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 10, 20, 30)
        let result = try await kernel.fillet(solid, edges: verticalEdges(solid).map(\.id), radius: 1, tag: newTag())
        #expect(result.topology.faces.count == 10)
        #expect(result.topology.faces.allSatisfy { face in !face.tags.contains { if case .unnamed = $0.role { true } else { false } } })
    }

    @Test(arguments: KernelUnderTest.allCases)
    func chamferRemovesTheAnalyticVolume(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try #require(verticalEdges(solid).first)
        let result = try await kernel.chamfer(solid, edges: [edge.id], distance: 1, tag: newTag())
        #expect(isClose(try await kernel.properties(of: result).volume, 6000 - 0.5 * 30))
        #expect(result.topology.faces.count == 7)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func impossibleFilletFailsCleanlyAndKernelRecovers(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try #require(verticalEdges(solid).first)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.fillet(solid, edges: [edge.id], radius: 40, tag: newTag())
        }
        guard case .filletFailed(let radius, _, let reason)? = error else { Issue.record("expected filletFailed"); return }
        #expect(radius == 40)
        #expect(!reason.isEmpty)
        #expect(error?.userMessage.contains("40") == true)
        // The kernel is still usable.
        let ok = try await kernel.fillet(solid, edges: [edge.id], radius: 1, tag: newTag())
        #expect(ok.topology.faces.count == 7)
    }

    @Test(arguments: KernelUnderTest.allCases)
    func featureInputsAreValidated(_ under: KernelUnderTest) async throws {
        let kernel = under.make()
        let solid = try await box(kernel, 10, 20, 30)
        await #expect(throws: KernelError.invalidInput("No edges are selected.")) {
            try await kernel.fillet(solid, edges: [], radius: 1, tag: newTag())
        }
        await #expect(throws: KernelError.invalidInput("Edge 999 doesn't exist on the input solid.")) {
            try await kernel.fillet(solid, edges: [EdgeID(999)], radius: 1, tag: newTag())
        }
        await #expect(throws: KernelError.invalidInput("The size must be greater than 0 mm.")) {
            try await kernel.chamfer(solid, edges: [EdgeID(0)], distance: .nan, tag: newTag())
        }
    }
}
