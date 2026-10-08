/// The viewport's keyboard commands (spec §9 stopgaps): F frames, + and − zoom.
public enum ViewportKeyCommand: Hashable, Sendable, CaseIterable {
    case frame
    case zoomIn
    case zoomOut
}
