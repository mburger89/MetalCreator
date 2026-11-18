import MetalUI

/// The keys of the control-point mode as invisible buttons, which run before the graph panel's keys (as `SketchToolbarKeys` does):
/// X, Y and Z lock the drag to an axis, N to the grabbed point's normal, and Esc cancels a drag, else ends the mode (R5). The
/// buttons are never disabled, so a key never falls through to the graph.
struct ControlNetKeys: Component {
    let session: ControlNetSession

    var content: some ElementGroup {
        HStack(spacing: Pixels(0)) {
            Button("X Axis") { session.toggleLock(.x) }
                .keyboardShortcut("x", modifiers: [])
                .frame(width: Pixels(0), height: Pixels(0))
            Button("Y Axis") { session.toggleLock(.y) }
                .keyboardShortcut("y", modifiers: [])
                .frame(width: Pixels(0), height: Pixels(0))
            Button("Z Axis") { session.toggleLock(.z) }
                .keyboardShortcut("z", modifiers: [])
                .frame(width: Pixels(0), height: Pixels(0))
            Button("Normal") { session.toggleLock(.normal) }
                .keyboardShortcut("n", modifiers: [])
                .frame(width: Pixels(0), height: Pixels(0))
            Button("Escape") { session.cancel() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: Pixels(0), height: Pixels(0))
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
