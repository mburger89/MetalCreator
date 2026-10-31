import CreatorGeometry
import CreatorKernel
import CreatorViewport
import Foundation
import Testing
@testable import CreatorApp

/// What the section's cap does when a request arrives while one is running: a moved plane lets it publish, an edit or a clear drops it.
@MainActor
struct SectionCapModelOrderTests {
    /// Holds each section in the kernel until released; `entered` yields once per held section.
    private final class SectionGate: @unchecked Sendable {
        let semaphore = DispatchSemaphore(value: 0)
        let entered: AsyncStream<Void>
        private let signal: AsyncStream<Void>.Continuation
        init() { (entered, signal) = AsyncStream<Void>.makeStream() }
        func hold() {
            signal.yield()
            _ = semaphore.wait(timeout: .now() + 60)
        }
        func release() { semaphore.signal() }
        func waitUntilEntered() async -> Bool {
            await withTaskGroup(of: Bool.self) { group in
                group.addTask { for await _ in self.entered { return true }; return false }
                group.addTask { try? await Task.sleep(for: .seconds(60)); return false }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
        }
    }

    private func boxSolid(_ size: Double, kernel: FakeKernel) async throws -> Solid {
        try await kernel.extrude(.rectangle(width: size, height: size, plane: .xy), distance: 10, mode: .oneSided,
                                 tag: NodeTag(node: NodeID(), item: 0))
    }

    @Test func aMovedPlanePublishesTheRunningCapFirst() async throws {
        let kernel = FakeKernel()
        let solid = try await boxSolid(10, kernel: kernel)
        let model = SectionCapModel(kernel: kernel, tolerance: 0.05)
        let gate = SectionGate()
        await kernel.setSectionHook { gate.hold() }
        let first = ViewportClip(origin: Vector3(0, 0, 3), normal: .unitZ)
        let second = ViewportClip(origin: Vector3(0, 0, 6), normal: .unitZ)
        model.follow(clip: first, items: [ViewportItem(solid: solid)])
        try #require(await gate.waitUntilEntered(), "the section hook was never reached")
        model.follow(clip: second, items: [ViewportItem(solid: solid)])
        gate.release()
        // The first cap lands while the second computation is held.
        try #require(await gate.waitUntilEntered(), "the second section never started")
        #expect(model.revision == 1)
        let published = try #require(model.section)
        #expect(published.plane == SectionCaps.plane(for: first))
        #expect(model.isComputing)
        gate.release()
        await model.waitForCaps()
        #expect(try #require(model.section).plane == SectionCaps.plane(for: second))
        #expect(!model.isComputing)
    }

    @Test func anEditCancelsTheRunningCap() async throws {
        let kernel = FakeKernel()
        let (small, big) = (try await boxSolid(10, kernel: kernel), try await boxSolid(20, kernel: kernel))
        let model = SectionCapModel(kernel: kernel, tolerance: 0.05)
        let gate = SectionGate()
        await kernel.setSectionHook { gate.hold() }
        let clip = ViewportClip(origin: Vector3(0, 0, 3), normal: .unitZ)
        model.follow(clip: clip, items: [ViewportItem(solid: small)])
        try #require(await gate.waitUntilEntered(), "the section hook was never reached")
        model.follow(clip: clip, items: [ViewportItem(solid: big)])
        #expect(model.isComputing)
        gate.release()
        gate.release()
        await model.waitForCaps()
        #expect(model.revision == 1, "the held result was never published")
        let section = try #require(model.section)
        #expect(section.caps.flatMap(\.positions).map { abs($0.x) }.max().map { $0 > 9.9 } == true, "the new solid's cap")
        #expect(section.generation == 2)
    }

    @Test func aClearDropsAFinishingCap() async throws {
        let kernel = FakeKernel()
        let solid = try await boxSolid(10, kernel: kernel)
        let model = SectionCapModel(kernel: kernel, tolerance: 0.05)
        let gate = SectionGate()
        await kernel.setSectionHook { gate.hold() }
        model.follow(clip: ViewportClip(origin: Vector3(0, 0, 3), normal: .unitZ), items: [ViewportItem(solid: solid)])
        try #require(await gate.waitUntilEntered(), "the section hook was never reached")
        model.follow(clip: nil, items: [])
        gate.release()
        await model.waitForCaps()
        #expect(model.section == nil && !model.isComputing)
    }
}
