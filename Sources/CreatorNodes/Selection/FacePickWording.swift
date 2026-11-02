import CreatorKernel

/// The sentences a picked face earns when it is not a clean match, shared by every node that stores a face pick (Plane from Face,
/// Face Pattern, Loft). Only the subject (`plane`, `pattern`, `loft`) and what the node does with the face differ.
enum FacePickWording {
    /// The pick has no stable name: `subject` is "plane", "pattern" or "loft".
    static func unnamed(_ subject: String) -> String {
        "The picked face has no stable name, so the \(subject) may move to a different face "
            + "when the model changes. Pick it again after the change."
    }

    /// A union merged the face with another part's: `action` is "The plane sits on", "The pattern fills", "The loft uses".
    static func merged(_ action: String) -> String {
        "The picked face was merged with a face from another part of the model that has since changed, "
            + "so it isn't clear which part was picked. \(action) the closest one; pick the face again to settle it."
    }

    /// The pick matches several faces: `action` is "the plane is on", "the pattern fills", "the loft uses".
    static func several(_ count: Int, _ action: String) -> String {
        "The pick matches \(count.display) faces; \(action) the first."
    }
}
