/// The plain sentences a refused group edit carries, as `GraphError.invalidValue` (groups spec §5).
enum GroupRefusal {
    static let missing = GraphError.invalidValue("That group no longer exists.")
    static let containsItself = GraphError.invalidValue("A group can't contain itself.")
    static let outputInside = GraphError.invalidValue("An Output node can't go in a group.")
    static let boundaryOutside = GraphError.invalidValue("Group Input and Group Output only go inside a group.")
    static let boundaryCount = GraphError.invalidValue("A group has exactly one Group Input and one Group Output.")
    static let boundaryDeleted = GraphError.invalidValue("A group's Group Input and Group Output can't be deleted.")
    static let boundaryMoved = GraphError.invalidValue("Group Input and Group Output belong to their group.")
    static let nested = GraphError.invalidValue("A group edit can't go inside another edit.")
    static let duplicateID = GraphError.invalidValue("That group already exists.")
    static let wouldCycle = GraphError.invalidValue(
        "These nodes can't be grouped: a node outside the selection both takes from them and feeds them.")
    static let emptyName = GraphError.invalidValue("A group needs a name.")
    /// Fields are never saved and `"field"` is no socket type a format-6 file may hold (CLAUDE.md: a change older readers can't
    /// decode bumps the format; 7b-2's format 7 lifts this).
    static let fieldSocket = GraphError.invalidValue(
        "A field can't cross a group's edge yet: group the nodes on both sides of the wire together, "
            + "or sample the field into numbers first.")

    static func nameTaken(_ name: String) -> GraphError { .invalidValue("A group named “\(name)” already exists.") }
    static func inUse(_ name: String) -> GraphError { .invalidValue("“\(name)” is still in use. Delete its group nodes first.") }
}
