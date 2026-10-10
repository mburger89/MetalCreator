/// Which graph an edit addresses (groups spec §5): the top level, or the inside of a group definition.
public enum GraphPath: Hashable, Sendable {
    case root
    case definition(GroupID)
}
