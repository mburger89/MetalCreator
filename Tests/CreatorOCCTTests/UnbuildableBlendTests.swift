import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// A fillet or chamfer OCCT reports not done names the largest size that works, as one OCCT builds but its checker
/// rejects does (Errata (Kernel: largest size for blends OCCT can't build)).
struct UnbuildableBlendTests {
    func verticalEdge(of solid: Solid) throws -> EdgeInfo {
        try #require(solid.topology.edges.first { $0.kind == .line && isClose($0.length, 30) })
    }

    @Test func aChamferOCCTCantBuildNamesTheLargestDistanceThatWorks() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try verticalEdge(of: solid)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.chamfer(solid, edges: [edge.id], distance: 40, tag: newTag())
        }
        guard case .operationFailed(let operation, _)? = error else { Issue.record("expected operationFailed"); return }
        #expect(operation == "chamfer")
        #expect(error?.userMessage == "Chamfer failed: the selected edges can't be chamfered by 40 mm (max ≈ 9.9 mm).")
    }

    @Test func theSizeItNamesBuildsAndIsValid() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try verticalEdge(of: solid)
        let filleted = try await kernel.fillet(solid, edges: [edge.id], radius: 9.9, tag: newTag())
        let chamfered = try await kernel.chamfer(solid, edges: [edge.id], distance: 9.9, tag: newTag())
        for result in [filleted, chamfered] {
            let shape = try #require((result.storage as? OCCTSolidStorage)?.shape)
            #expect(OCCTKernel.serialized { shape.isValid })
        }
    }

    /// The search runs after OCCT's first build fails, so a cancelled evaluation must stop it rather than name a size.
    @Test func aCancelledBlendOCCTCantBuildStopsRatherThanNamingASize() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try verticalEdge(of: solid)
        let blend = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.blend(solid, edges: [edge.id], size: 40, chamfer: false, tag: newTag())
        }
        await #expect(throws: CancellationError.self) { try await blend.value }
    }

    /// The search starts from the size asked for, capped, so a size far beyond the part (here 1e9 mm, a thousand
    /// kilometres) ends in the same maximum as one just beyond it.
    @Test func aRadiusFarBeyondThePartNamesTheSameMaximum() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try verticalEdge(of: solid)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.fillet(solid, edges: [edge.id], radius: 1e9, tag: newTag())
        }
        #expect(error?.userMessage.hasSuffix("(max ≈ 9.9 mm).") == true)
    }

    /// A real blend that no size can build: the vertical edge of a 0.1 mm square post, where even 0.1 mm rounds the
    /// whole face away. The search finds nothing, so the message keeps no maximum. OCCT's first build failed, not the
    /// checker, so this pins the not-built path's own wiring of `largest`.
    @Test func aBlendNoSizeCanBuildKeepsTheGenericMessage() async throws {
        let kernel = OCCTKernel()
        let post = try await box(kernel, 0.1, 0.1, 30)
        let edge = try verticalEdge(of: post)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.fillet(post, edges: [edge.id], radius: 5, tag: newTag())
        }
        #expect(error == .filletFailed(radius: 5, maxRadius: nil, reason: "the selected edges can't be rounded this much."))
        let chamfer = await #expect(throws: KernelError.self) {
            try await kernel.chamfer(post, edges: [edge.id], distance: 5, tag: newTag())
        }
        #expect(chamfer?.userMessage == "Chamfer failed: the selected edges can't be chamfered by 5 mm.")
    }

    @Test func theMessagesAddTheMaximumOnlyWhenOneWasFound() {
        #expect(KernelError.blendFailed(size: 40, chamfer: false, largest: 9.9).userMessage
            == "Radius 40 mm is too large for the selected edges (max ≈ 9.9 mm).")
        #expect(KernelError.blendFailed(size: 40, chamfer: false, largest: nil).userMessage
            == "Radius 40 mm could not be applied: the selected edges can't be rounded this much.")
        #expect(KernelError.blendFailed(size: 40, chamfer: true, largest: 9.9).userMessage
            == "Chamfer failed: the selected edges can't be chamfered by 40 mm (max ≈ 9.9 mm).")
        #expect(KernelError.blendFailed(size: 2.5, chamfer: true, largest: nil).userMessage
            == "Chamfer failed: the selected edges can't be chamfered by 2.5 mm.")
    }
}
