import CreatorGeometry
import Foundation
import Testing
@testable import CreatorKernel

/// The kernel of a platform with no OpenCascade (cross-platform spec 2.3): every operation answers "Geometry isn't available on
/// this platform yet." and none of them produces geometry.
struct KernelUnavailableTests {
    static let message = "Geometry isn't available on this platform yet."
    let kernel = KernelUnavailable()
    let tag = NodeTag(node: NodeID(), item: 0)

    /// A solid to hand the operations that take one (the fake kernel makes it; `KernelUnavailable` never could).
    func solid() async throws -> Solid {
        try await FakeKernel().extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
    }

    @Test func theErrorReadsAsTheSpecSaysAndIsTheKernelsUnavailableError() {
        #expect(KernelError.unavailable.userMessage == Self.message)
        #expect(KernelError.unavailable == .invalidInput(Self.message))
    }

    @Test func everyOperationRefusesWithThatError() async throws {
        let profile = Profile2D.rectangle(width: 10, height: 10, plane: .xy)
        let part = try await solid()
        let transform = Transform(translation: Vector3(1, 0, 0))
        await #expect(throws: KernelError.unavailable) { try await kernel.extrude(profile, distance: 5, mode: .oneSided, tag: tag) }
        await #expect(throws: KernelError.unavailable) {
            try await kernel.revolve(profile, axis: Axis(origin: .zero, direction: Vector3(0, 1, 0)), angle: .degrees(90), tag: tag)
        }
        await #expect(throws: KernelError.unavailable) { try await kernel.loft([profile, profile], ruled: true, tag: tag) }
        await #expect(throws: KernelError.unavailable) { try await kernel.boolean(.union, part, [part], tag: tag) }
        await #expect(throws: KernelError.unavailable) { try await kernel.transform(part, by: transform, tag: tag) }
        await #expect(throws: KernelError.unavailable) { try await kernel.place([part], at: [transform], qualifying: { $0 }, tag: tag) }
        await #expect(throws: KernelError.unavailable) { try await kernel.fillet(part, edges: [], radius: 1, tag: tag) }
        await #expect(throws: KernelError.unavailable) { try await kernel.chamfer(part, edges: [], distance: 1, tag: tag) }
        await #expect(throws: KernelError.unavailable) { try await kernel.tessellate(part, tolerance: 0.1) }
        await #expect(throws: KernelError.unavailable) {
            try await kernel.export([part], format: .stl, to: URL.temporaryDirectory.appending(path: "never-written.stl"))
        }
        await #expect(throws: KernelError.unavailable) { try await kernel.properties(of: part) }
        await #expect(throws: KernelError.unavailable) {
            try await kernel.distances(from: [.zero], to: .solid(part), signed: true)
        }
    }

    @Test func aSupersededCallIsCancelledBeforeItIsRefused() async {
        let profile = Profile2D.rectangle(width: 10, height: 10, plane: .xy)
        let task = Task { [kernel, tag] in
            while !Task.isCancelled { await Task.yield() }
            return try await kernel.extrude(profile, distance: 5, mode: .oneSided, tag: tag)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
