/// Where a scroll over the graph canvas sits in its gesture (from MetalUI's `ScrollEvent` phases,
/// `GraphPanelInput.scrollPhase(of:)`), as `EditorModel.scrolled(by:at:modifiers:phase:)` needs it.
public enum CanvasScrollPhase: Hashable, Sendable {
    /// A wheel mouse's step, with no gesture around it: ⌘ held zooms, anything else pans.
    case step
    /// A trackpad scroll's fingers touched or began to move: ⌘ held now makes the whole scroll a zoom.
    case began
    /// A trackpad scroll goes on, zooming or panning as it began (or, when it began elsewhere, as it was when it
    /// first reached the canvas).
    case changed
    /// The fingers lifted, or the system cancelled the scroll.
    case ended
    /// The glide after the fingers lift: it keeps panning a scroll that panned, and is ignored after a zoom.
    case momentum
    /// The glide's last event (its momentum ended or was cancelled): a zoom's glide is ignored no longer.
    case momentumEnded
}
