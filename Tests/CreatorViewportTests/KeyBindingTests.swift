import CreatorGeometry
import MetalUI
import Testing
@testable import CreatorViewport

@MainActor
struct KeyBindingTests {
    struct OtherAction: Action {}

    @Test func everyViewportKeyIsBoundToItsCommand() {
        let bindings = ViewportKeyBindings.bindings()
        #expect(bindings.map(\.spelling) == ViewportInputMap.keyBindings.map(\.spelling))
        #expect(bindings.allSatisfy { $0.context == nil })
        #expect(ViewportKeyBindings.bindings(context: "Viewport").allSatisfy { $0.context == "Viewport" })
        let commands = bindings.compactMap { ($0.action as? ViewportKeyAction)?.command }
        #expect(commands == ViewportInputMap.keyBindings.map(\.command))
    }

    @Test func handlingAnActionDrivesTheModel() {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: CameraPose(distance: 100), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        #expect(ViewportKeyBindings.handle(ViewportKeyAction(command: .zoomIn), model: model))
        #expect(abs(model.pose.distance - 80) < 1e-9)
        #expect(!ViewportKeyBindings.handle(OtherAction(), model: model))
        #expect(abs(model.pose.distance - 80) < 1e-9)
    }
}
