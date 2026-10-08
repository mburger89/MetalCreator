/// The view cube's arrow buttons (spec §6.3): each one rotates the view 90° to the adjacent face.
public enum CubeArrow: Hashable, Sendable, CaseIterable {
    case left, right, up, down
}
