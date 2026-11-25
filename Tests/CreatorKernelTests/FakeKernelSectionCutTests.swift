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

    @Test func aHookCanSuspend() async throws {
        let kernel = FakeKernel()
        let solid = try await box(kernel)
        let (stream, gate) = AsyncStream<Void>.makeStream()
        await kernel.setSectionCutHook { part, _, _ in
            for await _ in stream { break }
            return part
        }
        let task = Task { try await kernel.cutAway(solid, by: cutter, tag: tag) }
        gate.yield()
        let result = try await task.value
        #expect(result === solid)
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
}

private actor Seen {
    var value = false
    func set(_ newValue: Bool) { value = newValue }
}
