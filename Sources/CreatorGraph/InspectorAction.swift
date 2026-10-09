/// An inspector button's effect, carried out by the editor or viewport.
public enum InspectorAction: String, Sendable, Codable {
    case pickEdgesInView, pickFacesInView
    /// "Edit sketch" (sketcher spec §8): the app shell opens the node's sketch in the viewport.
    case editSketch
}
