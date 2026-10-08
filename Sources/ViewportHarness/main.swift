import CreatorKernel
import CreatorOCCT
import CreatorViewport
import Foundation
import MetalUI

/// The viewport in a window, for docs/verification/human-checks.md group V.
/// - `swift run ViewportHarness` shows the part.
/// - `HARNESS_GHOST=1` draws it as a stale ghost.
/// - `HARNESS_SELECT=1` selects its top face and edges.
/// Clicks, menu choices and handle drags print to the terminal.
@MainActor
func runHarness() throws {
    let app = try App()
    let environment = ProcessInfo.processInfo.environment
    let kernel = OCCTKernel()
    let model = ViewportModel(kernel: kernel)
    let modifiers = ViewportModifierTracker()
    model.events.clicked = { print("clicked: \(String(describing: $0))") }
    model.events.selectEdgesOfFace = { face, picks, edges in
        print("select edges of face \(face.face.rawValue): edges \(edges.map(\.rawValue)), \(picks.count) picks")
    }
    model.events.showProducingNode = { print("show producing node \($0)") }
    model.events.handleChanged = { id, value, phase in print("handle \(id) = \(value) (\(phase))") }
    let window = try app.openWindow(title: "MetalCreator — Viewport Harness",
                                    size: Size(width: Pixels(1100), height: Pixels(720)),
                                    content: {
                                        // A window's root must be an Element, and a Component is a group, so it's wrapped.
                                        ZStack { ViewportView(model: model, modifiers: modifiers) }
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    })
    modifiers.install(on: window)
    window.keymap = Keymap(ViewportKeyBindings.bindings())
    window.onAction = { [weak model] action in
        guard let model else { return false }
        return ViewportKeyBindings.handle(action, model: model)
    }
    Task {
        do {
            let scene = try await HarnessScene.build(kernel, ghost: environment["HARNESS_GHOST"] == "1",
                                                     selectTop: environment["HARNESS_SELECT"] == "1")
            model.show(scene.items)
            model.showHandles(scene.handles)
        } catch {
            print("ViewportHarness: \(error)")
        }
    }
    app.run()
}

try runHarness()
