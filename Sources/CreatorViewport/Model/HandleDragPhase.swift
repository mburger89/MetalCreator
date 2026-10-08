/// A handle drag reports `.changed` on every move and `.ended` once at release. The host ends undo coalescing on
/// `.ended` (spec §4.5).
public enum HandleDragPhase: Hashable, Sendable {
    case changed
    case ended
}
