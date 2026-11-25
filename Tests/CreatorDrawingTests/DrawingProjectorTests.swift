import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing

@Suite("Drawing projector")
struct DrawingProjectorTests {
    let output = NodeID()

    func view() -> DrawingView {
        DrawingView(kind: .base, source: output, orientation: .standard(.front), center: .zero)
    }

    func source(_ state: DrawingSourceContent.State) -> DrawingSourceContent {
        DrawingSourceContent(output: output, name: "Output", state: state)
    }

    @Test func aReadySourceProjects() async throws {
        let kernel = FakeKernel()
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let solid = try await ProjectionCacheTests.box(kernel)
        let content = await projector.content(
            for: view(), scale: 1, source: source(.ready(solids: [solid], curves: [], meshCount: 0)), previous: nil)
        #expect(content.projection?.lines.isEmpty == false)
        #expect(content.problem == nil)
        #expect(!content.isPending)
        #expect(content.warnings.isEmpty)
        #expect(content.lastSize == Vector2(10, 10))
    }

    @Test func severalSolidsAreCompounded() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache()
        let projector = DrawingProjector(cache: cache, kernel: kernel)
        let solids = [try await ProjectionCacheTests.box(kernel), try await ProjectionCacheTests.box(kernel)]
        let refused = await projector.content(
            for: view(), scale: 1, source: source(.ready(solids: solids, curves: [], meshCount: 0)), previous: nil)
        #expect(refused.problem == KernelError.unsupported("compounds").userMessage)
        #expect(refused.projection == nil)
        #expect(await cache.count == 0)
        let merged = try await ProjectionCacheTests.box(kernel, 20)
        await kernel.setCompoundHook { _ in merged }
        let content = await projector.content(
            for: view(), scale: 1, source: source(.ready(solids: solids, curves: [], meshCount: 0)), previous: nil)
        #expect(content.problem == nil)
        #expect(content.lastSize == Vector2(20, 20))
    }

    @Test func meshesAreLeftOutWithAWarning() async throws {
        let kernel = FakeKernel()
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let solid = try await ProjectionCacheTests.box(kernel)
        let three = await projector.content(
            for: view(), scale: 1, source: source(.ready(solids: [solid], curves: [], meshCount: 3)), previous: nil)
        #expect(three.warnings == ["This view leaves out the Output's 3 meshes; drawings show solids, sheets and curves."])
        let one = await projector.content(
            for: view(), scale: 1, source: source(.ready(solids: [solid], curves: [], meshCount: 1)), previous: nil)
        #expect(one.warnings == ["This view leaves out the Output's mesh; drawings show solids, sheets and curves."])
    }

    @Test func onlyMeshesIsRefused() async {
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: FakeKernel())
        let content = await projector.content(
            for: view(), scale: 1, source: source(.ready(solids: [], curves: [], meshCount: 2)), previous: nil)
        #expect(
            content.problem
                == "Drawings show solids, sheets and curves; this Output holds a mesh. Mesh to Solid makes a solid of a small mesh.")
        #expect(content.projection == nil)
    }

    @Test func nothingYet() async {
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: FakeKernel())
        let content = await projector.content(
            for: view(), scale: 1, source: source(.ready(solids: [], curves: [], meshCount: 0)), previous: nil)
        #expect(content.problem == "This Output holds nothing to draw yet.")
    }

    @Test func aRemovedOutputKeepsNoProjection() async {
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: FakeKernel())
        let previous = ViewContent(projection: Projection2D(lines: []), lastSize: Vector2(12, 7))
        let content = await projector.content(for: view(), scale: 1, source: source(.removed), previous: previous)
        #expect(content.problem == "The Output this view showed was removed.")
        #expect(content.projection == nil)
        #expect(content.lastSize == Vector2(12, 7))
    }

    @Test func aFailedOutputKeepsTheLastProjection() async throws {
        let kernel = FakeKernel()
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let solid = try await ProjectionCacheTests.box(kernel)
        let first = await projector.content(
            for: view(), scale: 1, source: source(.ready(solids: [solid], curves: [], meshCount: 0)), previous: nil)
        let failed = await projector.content(for: view(), scale: 1, source: source(.failed("Boom.")), previous: first)
        #expect(failed.projection == first.projection)
        #expect(failed.problem == "Boom.")
        let evaluating = await projector.content(for: view(), scale: 1, source: source(.evaluating), previous: first)
        #expect(evaluating.projection == first.projection)
        #expect(evaluating.problem == nil)
        #expect(!evaluating.isPending)
    }

    @Test func theToleranceFollowsTheScale() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache()
        let projector = DrawingProjector(cache: cache, kernel: kernel)
        let solid = try await ProjectionCacheTests.box(kernel)
        let ready = source(.ready(solids: [solid], curves: [], meshCount: 0))
        let content = await projector.content(for: view(), scale: 2, source: ready, previous: nil)
        // The size is the sheet's millimetres: the model's 10 mm at scale 2.
        #expect(content.lastSize == Vector2(20, 20))
        // The same request through the cache with tolerance 0.005 is a hit.
        _ = try await cache.projection(
            of: [solid], curves: [], compoundTag: NodeTag(node: output, item: 0), frame: view().orientation.frame,
            options: ProjectionOptions(tolerance: 0.005), kernel: kernel)
        #expect(await cache.kernelCalls == 1)
    }

    @Test func twoSolidsRequestedTwiceAreOneCompoundAndOneProjection() async throws {
        let kernel = FakeKernel()
        let cache = ProjectionCache()
        let projector = DrawingProjector(cache: cache, kernel: kernel)
        let merged = try await ProjectionCacheTests.box(kernel, 20)
        await kernel.setCompoundHook { _ in merged }
        let a = try await ProjectionCacheTests.box(kernel)
        let b = try await ProjectionCacheTests.box(kernel)
        let ready = source(.ready(solids: [a, b], curves: [], meshCount: 0))
        _ = await projector.content(for: view(), scale: 1, source: ready, previous: nil)
        _ = await projector.content(for: view(), scale: 1, source: ready, previous: nil)
        let second = DrawingView(kind: .base, source: output, orientation: .standard(.front), center: Vector2(50, 50))
        _ = await projector.content(for: second, scale: 1, source: ready, previous: nil)
        #expect(await cache.compoundCalls == 1)
        #expect(await cache.kernelCalls == 1)
        let c = try await ProjectionCacheTests.box(kernel)
        _ = await projector.content(
            for: view(), scale: 1, source: source(.ready(solids: [c, b], curves: [], meshCount: 0)), previous: nil)
        #expect(await cache.compoundCalls == 2)
        #expect(await cache.kernelCalls == 2)
    }
}
