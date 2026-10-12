import CreatorGraph

/// A Cull Pattern's mask written as text: `1 0 1`, `T F T` or `1,0,1` (1 or T keeps an item, 0 or F culls it).
enum CullMask {
    /// What the node's `cullPattern` setting says; refuses text with anything else in it, or nothing at all.
    static func parse(_ text: String) throws -> [Bool] {
        var mask: [Bool] = []
        for character in text where !character.isWhitespace && character != "," {
            switch character {
            case "1", "t", "T": mask.append(true)
            case "0", "f", "F": mask.append(false)
            default: throw NodeError.invalidValue("“\(text)” isn't a pattern. Use 1 to keep an item and 0 to cull it, like 1 0 1.")
            }
        }
        guard !mask.isEmpty else {
            throw NodeError.invalidValue("The pattern is empty. Write 1 to keep an item and 0 to cull it, like 1 0 1.")
        }
        return mask
    }
}
