/// An inspector button's effect, carried out by the editor or viewport.
public enum InspectorAction: String, Sendable, Codable {
    case pickEdgesInView, pickFacesInView
    /// "Edit sketch" (sketcher spec §8): the app shell opens the node's sketch in the viewport.
    case editSketch
    /// "Edit Group", "Make Unique" and "Ungroup" on a group node (groups spec §6): the graph panel carries them out
    /// itself, so they never reach the app shell.
    case editGroup, makeUnique, ungroup
    /// An Image Field's picture (fields spec §5), carried out by the app shell, which owns the file panels: "Choose Image…"
    /// (a file, embedded), "Link Image…" (an embedded picture is saved to a file and linked; with none, an existing file is
    /// linked), "Relink…" (another file for a link) and "Embed Image" (a link's file is read into the document).
    case chooseImage, linkImage, relinkImage, embedImage
}
