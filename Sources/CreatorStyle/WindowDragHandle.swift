import MetalUI

/// A region that moves the window when it is pressed and dragged (gap M6-c, MetalUI C22): SwiftUI's
/// `WindowDragGesture`. Under a hidden title bar there is no bar to grab, so the app marks the empty parts of its own
/// top bar with this view. It fills the space it is given and, being a gesture-carrying view, has a hitbox that wins
/// the press over the viewport beneath it. The gesture is ready at a 5-point move, so a plain click on it does
/// nothing, and a double click does not zoom the window.
///
/// The app puts it beside its controls or behind a label, not behind a button or a field. An enabled control above it
/// keeps its press (MetalUI's arena lets the control win), but a disabled one has no hitbox, so a press on it would
/// fall through to the handle and drag the window.
public struct WindowDragHandle: Component {
    public init() {}

    public var content: some ElementGroup {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
    }
}
