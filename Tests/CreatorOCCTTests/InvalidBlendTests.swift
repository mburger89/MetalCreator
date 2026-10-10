import Synchronization
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

    /// Counts the checker's calls from a closure the kernel runs on its own actor.
    final class CheckCount: Sendable {
        let calls = Mutex(0)
        func record() { calls.withLock { $0 += 1 } }
    }

    /// A checker that throws says nothing about any size: the blend fails with the generic message and no search runs.
    /// The search checks every try it makes, so exactly one call to the checker means no search ran.
    @Test func aCheckerThatThrowsGivesTheGenericMessageInsteadOfASearch() async throws {
        let kernel = OCCTKernel()
        let flange = try await HexagonFlange.make(kernel)
        let count = CheckCount()
        let error = await #expect(throws: KernelError.self) {
            try await kernel.blend(flange.union, edges: flange.uprightEdges, size: 3, chamfer: false, tag: newTag()) { _ in
                count.record()
                return .unchecked
            }
        }
        #expect(error == .filletFailed(radius: 3, maxRadius: nil, reason: "the selected edges can't be rounded this much."))
        #expect(count.calls.withLock { $0 } == 1)
        let chamfer = await #expect(throws: KernelError.self) {
            try await kernel.blend(flange.union, edges: flange.uprightEdges, size: 3, chamfer: true, tag: newTag()) { _ in
                count.record()
                return .unchecked
            }
        }
        #expect(chamfer?.userMessage == "Chamfer failed: the selected edges can't be chamfered by 3 mm.")
        #expect(count.calls.withLock { $0 } == 2)
    }

    /// A checker that rejects every size leaves the search nothing to name: the message keeps no maximum, and says "even
    /// by 0.1 mm" because the search did try it. (The not-built path has its own wiring of `largest`; see
    /// `UnbuildableBlendTests.aBlendNoSizeCanBuildKeepsTheGenericMessage`.)
    @Test func aCheckerThatRejectsEverySizeFindsNoMaximum() async throws {
        let kernel = OCCTKernel()
        let flange = try await HexagonFlange.make(kernel)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.blend(flange.union, edges: flange.uprightEdges, size: 3, chamfer: false, tag: newTag()) { _ in .invalid }
        }
        #expect(error == .filletFailed(radius: 3, maxRadius: nil,
                                       reason: "rounding the 4 selected edges gives a broken solid, even by 0.1 mm."))
    }

    /// A size of 0.1 mm or less never tried 0.1 mm, so the messages can't say "even by 0.1 mm".
    @Test func aSizeNoLargerThanTheSmallestOneDoesNotClaimToHaveTriedIt() {
        #expect(KernelError.invalidBlend(size: 0.1, largest: nil, edgeCount: 1, chamfer: false).userMessage
            == "Radius 0.1 mm could not be applied: rounding the selected edge gives a broken solid.")
        #expect(KernelError.invalidBlend(size: 0.05, largest: nil, edgeCount: 4, chamfer: true).userMessage
            == "Chamfer failed: chamfering the 4 selected edges by 0.05 mm gives a broken solid.")
        #expect(KernelError.invalidBlend(size: 0.15, largest: nil, edgeCount: 4, chamfer: true).userMessage
            == "Chamfer failed: chamfering the 4 selected edges by 0.15 mm gives a broken solid, even by 0.1 mm.")
    }

    /// Computed sizes land a hair off the grid: asked for `0.1 + 0.2`, the search names a size below it (0.2), not 0.3.
    /// 0.3 would build; the maximum is conservative for an off-grid size (`BlendGrid`).
    @Test func aSizeAHairOverTheGridNamesTheOneBelowIt() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try #require(solid.topology.edges.first { $0.kind == .line && isClose($0.length, 30) })
        let source = try #require((solid.storage as? OCCTSolidStorage)?.shape)
        let largest = try await kernel.largestValidBlend(of: source, edges: [edge.id], below: 0.1 + 0.2, chamfer: false)
        #expect(largest == 0.2)
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
