import Synchronization
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// The search for the largest size that works (`OCCTKernel.largestValidBlend`) when its checker doesn't answer every time.
struct BlendSearchTests {
    /// A checker that, called again, gives a different answer: every odd call is `.unchecked` and every even one `.valid`.
    final class Flaky: Sendable {
        let calls = Mutex(0)

        func check(_: OCCTShape) -> OCCTValidity {
            calls.withLock { calls in
                calls += 1
                return calls.isMultiple(of: 2) ? .valid : .unchecked
            }
        }
    }

    func standingBox() async throws -> (kernel: OCCTKernel, source: OCCTShape, edge: EdgeID) {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try #require(solid.topology.edges.first { $0.kind == .line && isClose($0.length, 30) })
        return (kernel, try #require((solid.storage as? OCCTSolidStorage)?.shape), edge.id)
    }

    /// A try the checker could not judge says nothing about that size: it is asked once more before the size counts as
    /// failed, so a checker that fails now and then does not name a smaller maximum than the part allows.
    @Test func aTryTheCheckerCouldNotJudgeIsCheckedOnceMoreBeforeItCountsAsFailed() async throws {
        let (kernel, source, edge) = try await standingBox()
        let sure = try await kernel.largestValidBlend(of: source, edges: [edge], below: 40, chamfer: false)
        #expect(sure == 9.9)
        let flaky = Flaky()
        let found = try await kernel.largestValidBlend(of: source, edges: [edge], below: 40, chamfer: false) { flaky.check($0) }
        #expect(found == sure, "the same maximum as with a checker that always answers")
        #expect(flaky.calls.withLock { $0 } > 0)
    }

    /// A checker that never answers names nothing: no size was ever shown to work.
    @Test func aCheckerThatNeverAnswersNamesNoSize() async throws {
        let (kernel, source, edge) = try await standingBox()
        let found = try await kernel.largestValidBlend(of: source, edges: [edge], below: 40, chamfer: false) { _ in .unchecked }
        #expect(found == nil)
    }
}
