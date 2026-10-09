/// How the viewport's camera moves while a `ViewportTool` is set.
public enum ViewportNavigation: Hashable, Sendable {
    /// The viewport's usual navigation: drags orbit, the view cube and its commands turn the camera.
    case free
    /// The camera keeps its orientation (the sketch editor, facing its plane): every drag the tool doesn't take pans,
    /// ⌥-drag, scroll and pinch zoom, the view cube, its arrows and its View menu are hidden, and no command or menu
    /// turns the camera (cube regions, arrows, Home, a projection change, Look At).
    case planar
}
