/// Key contexts the app shell contributes (MetalUI `keyContext`, matched along the focus chain).
public enum AppKeyContext {
    /// Contributed by the graph panel and the inspector, the panels with text fields (the inspector's number
    /// fields, the add-node palette's search field).
    public static let panel = "Panel"
    /// The viewport's keys (F, + and −) are in scope unless focus is inside a panel, where they would type.
    public static let viewport = "!\(panel)"
}
