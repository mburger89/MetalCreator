import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import Testing
@testable import CreatorApp

/// The progressive preview (implicit spec §4.3, §5.1): passes arrive finer and finer, and an edit stops them.
@MainActor
struct MeshRefinementModelTests {
    /// The first pass of a sphere of radius 6, as the Mesh node makes it, with a target.
    func firstPass(of solid: ImplicitSolid = .sphere(radius: 6), target: PreviewSchedule.Target) async throws -> TriangleMesh {
        let first = PreviewSchedule(target).firstResolution(for: solid.bounds)
        return try await ImplicitMesher(evaluator: CPUBatchEvaluator(solid))
            .mesh(solid, resolution: first, quality: .preview, source: MeshSource(solid: solid, target: target))
    }

    @Test func passesArriveFinerUntilTheTarget() async throws {
        let model = MeshRefinementModel(engine: .cpu)
        let base = try await firstPass(target: .fixed(0.06))
        model.follow([base])
        #expect(model.badge == .init(text: "Preview 0.094 mm", isRefining: true))
        await model.waitForRefinement()
        let pass = try #require(model.refined[base.id])
        #expect(pass.resolution == 0.06 && pass.triangleCount > base.triangleCount)
        #expect(MeshTopology(pass).isClosedManifold)
        #expect(model.badge == .init(text: "Preview 0.06 mm", isRefining: false))
        #expect(model.revision >= 2)
    }

    @Test func aMeshAtItsTargetIsNeverRefined() async throws {
        let model = MeshRefinementModel(engine: .cpu)
        let base = try await firstPass(target: .fixed(1))
        model.follow([base])
        await model.waitForRefinement()
        #expect(model.refined.isEmpty)
        #expect(model.badge == .init(text: "Preview 1 mm", isRefining: false))
    }

    @Test func aMeshThatLeavesTheSceneStopsItsPassesAndIsForgotten() async throws {
        let model = MeshRefinementModel(engine: .cpu)
        let base = try await firstPass(target: .fixed(0.06))
        model.follow([base])
        model.follow([])
        await model.waitForRefinement()
        #expect(model.refined.isEmpty && model.statuses.isEmpty && model.badge == nil)
    }

    @Test func aReplacementMeshStartsOverAndTheOldOneIsDropped() async throws {
        let model = MeshRefinementModel(engine: .cpu)
        let old = try await firstPass(target: .fixed(0.06))
        model.follow([old])
        let replacement = try await firstPass(of: .sphere(radius: 5), target: .fixed(0.06))
        model.follow([replacement])
        #expect(model.statuses.keys.contains(replacement.id) && !model.statuses.keys.contains(old.id))
        await model.waitForRefinement()
        #expect(model.refined[old.id] == nil && model.refined[replacement.id] != nil)
    }

    @Test func followingTheSameMeshAgainDoesNotRestartIt() async throws {
        let model = MeshRefinementModel(engine: .cpu)
        let base = try await firstPass(target: .fixed(0.06))
        model.follow([base])
        let revision = model.revision
        model.follow([base])
        #expect(model.revision == revision)
        await model.waitForRefinement()
        let done = try #require(model.refined[base.id])
        model.follow([base])
        #expect(model.refined[base.id]?.id == done.id, "a finished mesh is not meshed again")
    }

    @Test func aMeshWithoutASourceIsIgnored() {
        let model = MeshRefinementModel(engine: .cpu)
        model.follow([MeshFixture.tetrahedron])
        #expect(model.statuses.isEmpty && model.badge == nil)
    }

    @Test func theBadgeShowsTheCoarsestOfSeveralMeshes() async throws {
        let model = MeshRefinementModel(engine: .cpu)
        let coarse = try await firstPass(of: .sphere(radius: 12), target: .fixed(1))
        let fine = try await firstPass(of: .sphere(radius: 3), target: .fixed(1))
        model.follow([coarse, fine])
        #expect(model.badge?.text == "Preview 1 mm")
    }

    @Test func resetStopsEverything() async throws {
        let model = MeshRefinementModel(engine: .cpu)
        model.follow([try await firstPass(target: .fixed(0.06))])
        model.reset()
        await model.waitForRefinement()
        #expect(model.refined.isEmpty && model.badge == nil)
    }
}
