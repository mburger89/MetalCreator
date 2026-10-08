/// A handle is drawn in its node's category colour (spec §6.5, §6.6): purple for solids, orange for features.
public enum HandleTint: String, Hashable, Sendable {
    case solid
    case feature
}
