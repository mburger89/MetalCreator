import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

/// NS-5 R17 and the kernel's refusing defaults.
struct SolidKindTests {
    let node = NodeID()

    func solid(open: [Bool]) -> Solid {
        let faces = open.enumerated().map { index, isOpen in
            FaceInfo(id: FaceID(index), kind: .plane, normal: .unitZ, area: 1, centroid: .zero,
                     tags: [TopoTag(node: node, item: 0, role: .unnamed(face: index))], isOnOpenShell: isOpen)
        }
        return Solid(topology: Topology(faces: faces, edges: []), bounds: BoundingBox(min: .zero, max: .zero),
                     storage: FakeStorage())
    }

    @Test func aMixedValueHoldsAClosedSolid() {
        let sheets = solid(open: [true, true])
        #expect(sheets.hasOpenShell && !sheets.holdsClosedSolid)
        let solids = solid(open: [false, false])
        #expect(solids.holdsClosedSolid && !solids.hasOpenShell)
        let mixed = solid(open: [true, false])
        #expect(mixed.hasOpenShell && mixed.holdsClosedSolid)
    }

    @Test func theNewCallsAreRefusedByDefault() async {
        let kernel = FakeKernel()
        let body = solid(open: [true])
        let tag = NodeTag(node: node, item: 0)
        await expectRefused("thickening", "Thickening isn't supported by this kernel yet.") {
            _ = try await kernel.thickened(body, distance: 1, side: .front, tag: tag)
        }
        await expectRefused("sewing", "Sewing isn't supported by this kernel yet.") {
            _ = try await kernel.sewn([body], tolerance: 0.01, tag: tag)
        }
        await expectRefused("offsetting surfaces", "Offsetting surfaces isn't supported by this kernel yet.") {
            _ = try await kernel.offsetSurface(body, distance: 1, tag: tag)
        }
        await expectRefused("capping holes", "Capping holes isn't supported by this kernel yet.") {
            _ = try await kernel.cappingPlanarHoles(body, tag: tag)
        }
        await expectRefused("splitting solids", "Splitting solids isn't supported by this kernel yet.") {
            _ = try await kernel.splitSolid(body, by: [], tag: tag)
        }
        await expectRefused("separating solids", "Separating solids isn't supported by this kernel yet.") {
            _ = try await kernel.separated(body, tag: tag)
        }
    }

    func expectRefused(_ phrase: String, _ message: String, _ call: () async throws -> Void) async {
        do {
            try await call()
            Issue.record("expected a refusal")
        } catch let error as KernelError {
            #expect(error == .unsupported(phrase))
            #expect(error.userMessage == message)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
