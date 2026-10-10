/// A theme accent role (groups spec §4, §7): the accent of a group definition and of a canvas comment. It names a
/// role of the current theme, never a colour, so it follows theme changes. Shared with comments (track B): whichever
/// of C1 and B merges first adds this file, and the other keeps it unchanged.
public enum AccentRole: String, Sendable, Codable, CaseIterable {
    case cyan, green, orange, pink, purple, yellow, muted
}
