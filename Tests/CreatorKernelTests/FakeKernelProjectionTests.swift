import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel

struct FakeKernelProjectionTests {
    let tag = NodeTag(node: NodeID(), item: 0)
    let front = ProjectionFrame(direction: Vector3(0, 1, 0), up: Vector3(0, 0, 1))

    func box(_ kernel: FakeKernel) async throws -> Solid {
        try await kernel.extrude(.rectangle(width: 10, height: 20, plane: .xy), distance: 30, mode: .oneSided, tag: tag)
    }

    @Test func aBoxSeenFromTheFrontIsItsRectangle() async throws {
        let kernel = FakeKernel()
        let part = try await box(kernel)
        let found = try await kernel.projection(of: part, curves: [], frame: front, options: ProjectionOptions())
        #expect(found.lines.count == 4)
        #expect(found.lines.allSatisfy { $0.visibility == .visible && $0.lineClass == .sharp })
        #expect(found.bounds == Rect2D(min: Vector2(-5, 0), max: Vector2(5, 30)))
        let sources = found.lines.compactMap(\.source)
        #expect(sources.count == 4 && Set(sources).count == 4)
    }

    @Test func aCurveProjectsAsACurveLine() async throws {
        let kernel = FakeKernel()
        let curve = try await kernel.makeCurve([.line(Vector3(0, 0, 0), Vector3(4, 5, 6))], tag: tag)
        let found = try await kernel.projection(of: nil, curves: [curve], frame: front, options: ProjectionOptions())
        let line = try #require(found.lines.first)
        #expect(found.lines.count == 1 && line.lineClass == .curve && line.visibility == .visible)
        #expect(line.source == .curve(index: 0, piece: 0))
        #expect(line.curve == .polyline([Vector2(0, 0), Vector2(4, 6)]))
    }

    @Test func aTiltedDirectionIsUnsupported() async throws {
        let kernel = FakeKernel()
        let part = try await box(kernel)
        let tilted = try #require(ProjectionFrame.make(direction: Vector3(1, 1, 0), up: .unitZ))
        await #expect(throws: KernelError.unsupported("projecting along a tilted direction")) {
            try await kernel.projection(of: part, curves: [], frame: tilted, options: ProjectionOptions())
        }
    }

    @Test func theDefaultRefuses() async throws {
        let kernel = KernelUnavailable()
        await #expect(throws: KernelError.unsupported("projecting views")) {
            try await kernel.projection(of: nil, curves: [], frame: front, options: ProjectionOptions())
        }
    }

    @Test func theHookCanHoldACall() async throws {
        let kernel = FakeKernel()
        let part = try await box(kernel)
        let gate = Gate()
        await kernel.setProjectionHook { await gate.wait() }
        let frame = front
        let task = Task { try await kernel.projection(of: part, curves: [], frame: frame, options: ProjectionOptions()) }
        await gate.waitUntilWaiting()
        await gate.open()
        let found = try await task.value
        #expect(found.lines.count == 4)
    }

    @Test func compoundRefusesWithoutAHook() async throws {
        let kernel = FakeKernel()
        let part = try await box(kernel)
        await #expect(throws: KernelError.unsupported("compounds")) { try await kernel.compound([part], tag: tag) }
    }

    @Test func aCompoundHookAnswers() async throws {
        let kernel = FakeKernel()
        let part = try await box(kernel)
        let calls = Counter()
        await kernel.setCompoundHook { solids in
            calls.bump()
            return solids[0]
        }
        let made = try await kernel.compound([part], tag: tag)
        #expect(made === part)
        #expect(calls.value == 1)
    }
}

/// A one-shot gate a hook suspends on (never blocks a pool thread).
private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilWaiting() async {
        while continuation == nil { await Task.yield() }
    }
    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
