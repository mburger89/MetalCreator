import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation
import Synchronization
@testable import CreatorApp
@testable import CreatorViewport

/// A box over `FakeKernel` (exact for its line edges), with the app showing it and a view size recorded, and helpers to click on it.
@MainActor
struct MeasureAppFixture {
    let app: AppModel
    let kernel: FakeKernel
    let box: (rectangle: Node, extrude: Node, output: Node)

    static func open(kernel: FakeKernel = FakeKernel()) async -> MeasureAppFixture {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph, kernel: kernel)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        await app.viewport.waitForMeshes()
        return MeasureAppFixture(app: app, kernel: kernel, box: box)
    }

    var solid: Solid { app.viewport.items[0].solid }
    var projector: ViewportProjector { app.viewport.projector }

    /// The box's straight edges that run along z, in id order: its four vertical edges.
    var verticals: [EdgeInfo] {
        solid.topology.edges.filter { edge in
            guard case .line? = edge.curve, let direction = edge.direction else { return false }
            return abs(abs(direction.z) - 1) < 1e-9
        }.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    func target(_ edge: EdgeInfo) -> PickTarget { .edge(solid: 0, edge.id) }

    /// A click on `target` as the viewport delivers it, at the middle of `edge` when it is one (far from its ends).
    @discardableResult
    func click(_ target: PickTarget?, at point: ScreenPoint? = nil) -> Bool {
        guard let session = app.measure else { return false }
        return session.clickedModel(target, at: point ?? target.map(middle(of:)) ?? ScreenPoint(700, 450), modifiers: [],
                                    projector: projector)
    }

    /// Where the middle of an edge target is on screen; the middle of the view for anything else.
    func middle(of target: PickTarget) -> ScreenPoint {
        if case let .edge(_, id) = target, let edge = solid.topology.edge(id), let point = projector.screenPoint(of: edge.midpoint) {
            return point
        }
        return ScreenPoint(700, 450)
    }

    func screen(_ world: Vector3) -> ScreenPoint {
        projector.screenPoint(of: world) ?? ScreenPoint(0, 0)
    }
}

/// Lets exactly one caller through a hook later: the first call waits for `release()`. Each test releases the gate when it
/// ends (`defer { gate.release() }`), so a test that fails before its own `release()` never leaves the call held.
///
/// The hold lapses after 600 s: `enter()` blocks a thread of Swift's shared pool, and with no limit a few gated tests running
/// at once on a small machine (CI's aarch64 runner) used the pool up and stalled the whole suite for good.
/// `waitUntilEntered()` has no deadline: on Windows every test of the suite starts at once and then waits its turn for the
/// main actor, so the kernel call can be minutes away (`measuringShowsWhileTheDistanceIsHeld` ran 1,064 s in CI and its
/// one-minute wait lapsed before the measurement had even started). A test that really hangs is the CI job's timeout to catch.
final class FirstCallGate: Sendable {
    private let calls = Mutex(0)
    private let semaphore = DispatchSemaphore(value: 0)

    func enter() {
        let first = calls.withLock { count -> Bool in
            count += 1
            return count == 1
        }
        if first { _ = semaphore.wait(timeout: .now() + 600) }
    }

    func release() { semaphore.signal() }

    /// Waits until the first call is inside the gate (so the work it holds is really held); false only if the test is cancelled.
    func waitUntilEntered() async -> Bool {
        while calls.withLock({ $0 }) == 0, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        return calls.withLock { $0 } > 0
    }
}
