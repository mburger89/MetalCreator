/// The mouse button behind a viewport drag (spec §9, MetalUI C7's `DragGesture(button:)`).
public enum ViewportPointerButton: Hashable, Sendable {
    case primary
    case secondary
    case middle
}
