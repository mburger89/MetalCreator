import CreatorGraph
import Foundation

/// The add-node palette's search: every registered type whose name contains the query
/// (case- and diacritic-insensitive), name-prefix matches first, then by category and name.
public enum PaletteSearch {
    public static func entries(in registry: NodeRegistry, matching query: String) -> [PaletteEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let all = registry.all.map { PaletteEntry(typeID: $0.typeID, displayName: $0.displayName, category: $0.category) }
        let matches = needle.isEmpty ? all : all.filter { $0.displayName.localizedStandardContains(needle) }
        return matches.sorted { a, b in
            let aPrefix = isPrefix(needle, of: a.displayName), bPrefix = isPrefix(needle, of: b.displayName)
            if aPrefix != bPrefix { return aPrefix }
            let aRank = NodeCategory.allCases.firstIndex(of: a.category) ?? 0
            let bRank = NodeCategory.allCases.firstIndex(of: b.category) ?? 0
            if aRank != bRank { return aRank < bRank }
            return a.displayName.localizedStandardCompare(b.displayName) == .orderedAscending
        }
    }

    private static func isPrefix(_ needle: String, of name: String) -> Bool {
        !needle.isEmpty && name.range(of: needle, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
    }
}
