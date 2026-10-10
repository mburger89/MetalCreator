import Foundation

/// The short, user-facing names of undo steps (the Edit menu reads "Undo Add Note"). A name says what the person did, in
/// the app's plain English, and carries no numbers; text the person typed (a note, a group's name) is never put in one.
/// Callers that know the intent pass one of these to `DocumentModel.perform(_:at:coalescingKey:name:)`; a caller that
/// gives none gets the generic `edit` ("Undo Edit"). Undo names are in memory only: they are never saved.
public enum UndoName {
    // MARK: Nodes and wires
    public static let connect = "Connect"
    public static let disconnect = "Disconnect"
    public static let delete = "Delete"
    public static let cut = "Cut"
    public static let paste = "Paste"
    public static let duplicate = "Duplicate"
    public static let move = "Move"
    public static let resize = "Resize"
    /// A node added from the palette or the library: "Add Box" (its type's title). A group node is "Add Group",
    /// whatever its definition is called, and a node with no title is "Add Node".
    public static func addNode(_ node: Node) -> String {
        if node.typeID == GroupNodes.groupTypeID { return "Add Group" }
        let title = node.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Add Node" : "Add \(title)"
    }
    /// An inspector input changed: "Change Width"; cleared: "Clear Width". `label` is the input's fixed label.
    public static func changeInput(_ label: String) -> String { label.isEmpty ? "Change Input" : "Change \(label)" }
    public static func clearInput(_ label: String) -> String { label.isEmpty ? "Clear Input" : "Clear \(label)" }
    public static let changeParameter = "Change Parameter"

    // MARK: Comments (canvas comments spec §7)
    public static let addNote = "Add Note"
    public static let editNote = "Edit Note"
    public static let addFrame = "Add Frame"
    public static let editFrame = "Edit Frame"

    // MARK: Groups (groups spec §5, §6)
    public static let group = "Group"
    public static let ungroup = "Ungroup"
    public static let makeUnique = "Make Unique"
    public static let renameGroup = "Rename Group"
    public static let changeGroupAccent = "Change Group Accent"
    public static let addInputSocket = "Add Input Socket"
    public static let addOutputSocket = "Add Output Socket"
    public static let renameSocket = "Rename Socket"
    public static let moveSocket = "Move Socket"
    public static let removeSocket = "Remove Socket"
    public static let deleteGroup = "Delete Group"

    // MARK: The viewport and the sketch editor
    public static let dragHandle = "Drag Handle"
    public static let pickEdges = "Pick Edges"
    public static let selectEdgesOfFace = "Select Edges of Face"
    public static let newSketchOnFace = "New Sketch on Face"
    public static let editSketch = "Edit Sketch"
    /// A sketch editor commit: its fixed step name (`SketchCommit.name`, "Add Line"), or "Edit Sketch" when it has none.
    public static func sketch(_ name: String) -> String { cleaned(name) ?? editSketch }

    /// The generic name, for a step whose caller gave none (or a blank one). No callers use it: a step called "Edit"
    /// is a forgotten name, which the tests of each call site catch.
    public static let edit = "Edit"

    /// `name` trimmed, or `nil` when nothing is left (a blank name is no name).
    static func cleaned(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
