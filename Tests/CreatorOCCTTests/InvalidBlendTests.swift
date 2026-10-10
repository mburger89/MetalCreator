import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// The kernel never returns a blend OCCT's own checker rejects; it names the largest size that works instead
/// (spec Errata (Kernel: invalid blends)).
struct InvalidBlendTests {
    func isValid(_ solid: Solid) throws -> Bool {
        let shape = try #require((solid.storage as? OCCTSolidStorage)?.shape)
        return OCCTKernel.serialized { shape.isValid }
    }

    @Test func aFilletOCCTBreaksIsRefusedWithTheLargestRadiusThatWorks() async throws {
        let kernel = OCCTKernel()
        let flange = try await HexagonFlange.make(kernel)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.fillet(flange.union, edges: flange.uprightEdges, radius: 3, tag: newTag())
        }
        #expect(error == .filletFailed(radius: 3, maxRadius: 2.5,
                                       reason: "rounding the 4 selected edges by 3 mm gives a broken solid."))
        #expect(error?.userMessage == "Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm).")
    }

    @Test func theRadiusItNamesWorksAndKeepsEveryFaceNamed() async throws {
        let kernel = OCCTKernel()
        let flange = try await HexagonFlange.make(kernel)
        let filletTag = newTag()
        let filleted = try await kernel.fillet(flange.union, edges: flange.uprightEdges, radius: 2.5, tag: filletTag)
        #expect(try isValid(filleted))
        let keys = flange.uprightEdges.compactMap { flange.union.topology.edge($0).flatMap(flange.union.topology.key(of:)) }
        #expect(keys.count == 4)
        for key in keys {
            #expect(faces(filleted, role: .blend(sourceEdge: key), of: filletTag).count == 1)
        }
        #expect(filleted.topology.faces.allSatisfy { face in !face.tags.contains { if case .unnamed = $0.role { true } else { false } } })
        let before = try await kernel.properties(of: flange.union).volume
        #expect(try await kernel.properties(of: filleted).volume < before)
    }

    @Test func aChamferOCCTBreaksIsRefusedWithTheLargestDistanceThatWorks() async throws {
        let kernel = OCCTKernel()
        let flange = try await HexagonFlange.make(kernel)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.chamfer(flange.union, edges: flange.uprightEdges, distance: 3, tag: newTag())
        }
        #expect(error?.userMessage == "Chamfer failed: chamfering the 4 selected edges by 3 mm gives a broken solid (max ≈ 2.5 mm).")
        let chamfered = try await kernel.chamfer(flange.union, edges: flange.uprightEdges, distance: 2.5, tag: newTag())
        #expect(try isValid(chamfered))
    }

    @Test func aCancelledSearchStopsBeforeTryingASize() async throws {
        let kernel = OCCTKernel()
        let flange = try await HexagonFlange.make(kernel)
        let source = try #require((flange.union.storage as? OCCTSolidStorage)?.shape)
        let search = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.largestValidBlend(of: source, edges: flange.uprightEdges, below: 3, chamfer: false)
        }
        await #expect(throws: CancellationError.self) { try await search.value }
    }

    /// The refused blend's search lets the cancellation through rather than naming a size. `fillet` checks cancellation
    /// on entry, so this calls the shared `blend` it delegates to: the first build runs, the checker refuses it, and the
    /// search's `CancellationError` must reach the caller (the `catch is OCCTError` wraps only the first build).
    @Test func aCancelledBlendStopsRatherThanNamingASize() async throws {
        let kernel = OCCTKernel()
        let flange = try await HexagonFlange.make(kernel)
        let blend = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.blend(flange.union, edges: flange.uprightEdges, size: 3, chamfer: false, tag: newTag())
        }
        await #expect(throws: CancellationError.self) { try await blend.value }
    }

    /// The search starts at the size asked for, so a size far beyond the part (or beyond `Int`) still ends in one that works.
    @Test func aRadiusFarBeyondThePartStillFindsOneThatWorks() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try #require(solid.topology.edges.first { $0.kind == .line && isClose($0.length, 30) })
        let source = try #require((solid.storage as? OCCTSolidStorage)?.shape)
        let largest = try await kernel.largestValidBlend(of: source, edges: [edge.id], below: .greatestFiniteMagnitude,
                                                         chamfer: false)
        let radius = try #require(largest)
        #expect(radius == 9.9, "its narrower face is 10 mm wide")
        let filleted = try await kernel.fillet(solid, edges: [edge.id], radius: radius, tag: newTag())
        #expect(try isValid(filleted))
    }

    @Test func theMessagesNameOneEdgeAndSayWhenNoSizeWorks() {
        #expect(KernelError.invalidBlend(size: 3, largest: nil, edgeCount: 1, chamfer: false).userMessage
            == "Radius 3 mm could not be applied: rounding the selected edge gives a broken solid, even by 0.1 mm.")
        #expect(KernelError.invalidBlend(size: 0.5, largest: nil, edgeCount: 2, chamfer: true).userMessage
            == "Chamfer failed: chamfering the 2 selected edges by 0.5 mm gives a broken solid, even by 0.1 mm.")
        #expect(KernelError.invalidBlend(size: 1.25, largest: 0.7, edgeCount: 1, chamfer: true).userMessage
            == "Chamfer failed: chamfering the selected edge by 1.25 mm gives a broken solid (max ≈ 0.7 mm).")
    }
}
