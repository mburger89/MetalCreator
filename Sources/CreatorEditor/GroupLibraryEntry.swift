import CreatorGraph
import Foundation

/// One group definition in the node library's "Groups" section (groups spec §6): a click or drag places another
/// instance of it, and one with no instances offers Delete.
public struct GroupLibraryEntry: Equatable, Sendable, Identifiable {
    public var group: GroupID
    public var name: String
    public var accent: AccentRole
    /// Group nodes of the definition, on every level.
    public var uses: Int

    public var id: String { key }

    /// The key the library's gestures carry for this entry in place of a node type's ID (`LibraryDrag.typeID`).
    public var key: String { Self.key(for: group) }

    /// A definition with no instance can be deleted from the library.
    public var canDelete: Bool { uses == 0 }

    /// The prefix of a group's library key: no node type's ID starts with it.
    static let keyPrefix = "group:"

    static func key(for group: GroupID) -> String { keyPrefix + group.rawValue.uuidString }

    /// The definition a library key names, or `nil` for a node type's ID.
    static func group(forKey key: String) -> GroupID? {
        guard key.hasPrefix(keyPrefix) else { return nil }
        return UUID(uuidString: String(key.dropFirst(keyPrefix.count))).map { GroupID(rawValue: $0) }
    }

    /// The row the library, the palette's label and the drag ghost draw for it.
    public var paletteEntry: PaletteEntry {
        PaletteEntry(typeID: key, displayName: name, category: .feature, accent: accent)
    }
}
