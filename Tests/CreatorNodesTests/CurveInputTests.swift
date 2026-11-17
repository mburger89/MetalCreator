import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorNodes

struct CurveInputTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    func square(_ side: Double, at origin: Vector2 = .zero) -> [Segment2D] {
        let p = [origin, origin + Vector2(side, 0), origin + Vector2(side, side), origin + Vector2(0, side)]
        return (0..<4).map { .line(p[$0], p[($0 + 1) % 4]) }
    }

    @Test func aProfileWithAHoleGivesTwoLoops() async throws {
        let profile = Profile2D(plane: .xy, outer: square(10), holes: [square(2, at: Vector2(4, 4))])
        let curves = try await CurveInput.loops([.profile(profile)], holes: .all, kernel: FakeKernel(), tag: tag)
        #expect(curves.count == 2 && curves.allSatisfy(\.isClosed))
    }

    @Test func aHoleCanBeRefused() async {
        let profile = Profile2D(plane: .xy, outer: square(10), holes: [square(2, at: Vector2(4, 4))])
        await #expect(throws: NodeError.invalidValue("x")) {
            try await CurveInput.loops([.profile(profile)], holes: .refuse("x"), kernel: FakeKernel(), tag: tag)
        }
    }

    @Test func aWiredCurvePassesThrough() async throws {
        let kernel = FakeKernel()
        let curve = try await kernel.makeCurve([.line(.zero, Vector3(1, 0, 0))], tag: tag)
        let out = try await CurveInput.loops([.curve(curve)], holes: .all, kernel: kernel, tag: tag)
        #expect(out.count == 1 && out[0] === curve)
    }
}
