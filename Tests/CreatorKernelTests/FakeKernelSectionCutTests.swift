import CreatorGeometry
import Testing
@testable import CreatorKernel

struct FakeKernelSectionCutTests {
    let frame = ProjectionFrame(direction: Vector3(0, 0, -1), up: Vector3(0, 1, 0))
    var cutter: SectionCutter { SectionCutter(frame: frame, points: [Vector2(-5, 5), Vector2(45, 5)], viewing: Vector2(0, 1)) }
    let tag = NodeTag(node: SectionCutter.toolNode, item: 0)

    func box(_ kernel: FakeKernel) async throws -> Solid {
        let profile = Profile2D(plane: .xy, segments: [
            .line(Vector2(0, 0), Vector2(40, 0)), .line(Vector2(40, 0), Vector2(40, 20)),
            .line(Vector2(40, 20), Vector2(0, 20)), .line(Vector2(0, 20), Vector2(0, 0)),
        ])
        return try await kernel.extrude(profile, distance: 10, mode: .oneSided, tag: tag)
    }

    @Test func refusesWithoutAHook() async throws {
        let kernel = FakeKernel()
        let solid = try await box(kernel)
        await #expect(throws: KernelError.unsupported("cutting sections")) {
            _ = try await kernel.cutAway(solid, by: cutter, tag: tag)
        }
    }

    @Test func aHookAnswers() async throws {
        let kernel = FakeKernel()
        let solid = try await box(kernel)
        let seen = Seen()
        await kernel.setSectionCutHook { part, line, nodeTag in
            await seen.set(part === solid && line == cutter && nodeTag == tag)
            return part
        }
        let result = try await kernel.cutAway(solid, by: cutter, tag: tag)
        #expect(result === solid)
        #expect(await seen.value)
    }

    /// The hook suspends (it never blocks a thread): while it waits the caller is observed still suspended, and it goes on when the
    /// hook is let through.
    @Test func aHookCanSuspend() async throws {
        let kernel = FakeKernel()
        let solid = try await box(kernel)
        let gate = HookGate()
        await kernel.setSectionCutHook { part, _, _ in
            await gate.hold()
            return part
        }
        let cutter = self.cutter, tag = self.tag
        let finished = Seen()
        let task = Task {
            let result = try await kernel.cutAway(solid, by: cutter, tag: tag)
            await finished.set(true)
            return result
        }
        await gate.waitUntilHeld()
        for _ in 0..<50 { await Task.yield() }
        #expect(await finished.value == false, "the caller is suspended while the hook awaits")
        await gate.open()
        let result = try await task.value
        #expect(result === solid)
        #expect(await finished.value)
    }

    @Test func anInvalidCutterIsRefusedFirst() async throws {
        let kernel = FakeKernel()
        let solid = try await box(kernel)
        await kernel.setSectionCutHook { part, _, _ in part }
        let bad = SectionCutter(frame: frame, points: [Vector2(0, 0)], viewing: Vector2(0, 1))
        await #expect(throws: KernelError.invalidInput("A cutting line needs at least two points.")) {
            _ = try await kernel.cutAway(solid, by: bad, tag: tag)
        }
    }

    @Test func aBadFrameIsRefusedAsOCCTRefusesIt() async throws {
        let kernel = FakeKernel()
        let solid = try await box(kernel)
        await kernel.setSectionCutHook { part, _, _ in part }
        let skew = ProjectionFrame(direction: Vector3(0, 0, -1), up: Vector3(0, 0, -1))
        let bad = SectionCutter(frame: skew, points: [Vector2(-5, 5), Vector2(45, 5)], viewing: Vector2(0, 1))
        await #expect(throws: KernelError.invalidInput("The view direction and its up direction must be perpendicular unit vectors.")) {
            _ = try await kernel.cutAway(solid, by: bad, tag: tag)
        }
    }
}

private actor Seen {
    var value = false
    func set(_ newValue: Bool) { value = newValue }
}

/// Suspends a hook until `open()`, holding no thread; `waitUntilHeld()` returns once a hook has begun waiting.
private actor HookGate {
    private var held: [CheckedContinuation<Void, Never>] = []
    private var watchers: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func hold() async {
        let ready = watchers
        watchers = []
        for watcher in ready { watcher.resume() }
        if isOpen { return }
        await withCheckedContinuation { held.append($0) }
    }

    func waitUntilHeld() async {
        if !held.isEmpty { return }
        await withCheckedContinuation { watchers.append($0) }
    }

    func open() {
        isOpen = true
        let all = held
        held = []
        for continuation in all { continuation.resume() }
    }
}
