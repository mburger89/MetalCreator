/// An inspector button's effect, carried out by the editor or viewport.
public enum InspectorAction: String, Sendable, Codable {
    case pickEdgesInView, pickFacesInView
    /// "Edit sketch" (sketcher spec §8): the app shell opens the node's sketch in the viewport.
    case editSketch
    /// "Edit Group", "Make Unique" and "Ungroup" on a group node (groups spec §6): the graph panel carries them out
    /// itself, so they never reach the app shell.
    case editGroup, makeUnique, ungroup
}
