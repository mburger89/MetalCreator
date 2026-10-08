import CreatorKernel
import CreatorOCCT
import CreatorViewport
import Foundation
import MetalUI

/// The viewport in a window, for docs/verification/human-checks.md group V.
/// - `swift run ViewportHarness` shows the part.
/// - `HARNESS_GHOST=1` draws it as a stale ghost.
/// - `HARNESS_SELECT=1` selects its top face and edges.
/// Clicking a face selects it and its edges (an edge selects that edge; empty space clears). Dragging a handle
/// rebuilds the part with the new plate thickness or fillet radius. Clicks, menu choices and handle drags print
/// to the terminal.
@MainActor
func runHarness() throws {
    let app = try App()
    let environment = ProcessInfo.processInfo.environment
    let kernel = OCCTKernel()
    let model = ViewportModel(kernel: kernel)
    let modifiers = ViewportModifierTracker()
    let selection = HarnessSelection()
    model.events.clicked = { [weak model] target in
        print("clicked: \(String(describing: target))")
        if let model { selection.apply(target, on: model) }
    }
    model.events.selectEdgesOfFace = { [weak model] face, picks, edges in
        print("select edges of face \(face.face.rawValue): edges \(edges.map(\.rawValue)), \(picks.count) picks")
        if let model { selection.selectEdges(edges, ofSolid: face.solidIndex, on: model) }
    }
    model.events.showProducingNode = { print("show producing node \($0)") }
    let rebuilder = HarnessRebuilder(kernel: kernel, selection: selection,
                                     ghost: environment["HARNESS_GHOST"] == "1",
                                     selectTop: environment["HARNESS_SELECT"] == "1")
    model.events.handleChanged = { [weak model] id, value, phase in
        print("handle \(id) = \(value) (\(phase))")
        if let model { rebuilder.handleChanged(id, to: value, on: model) }
    }
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
    rebuilder.rebuild(on: model)
    app.run()
}

try runHarness()
