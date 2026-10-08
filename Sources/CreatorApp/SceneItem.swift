import CreatorGraph
import CreatorViewport

/// One solid the viewport shows, and the output socket that produced it (`nil` when it can't be named), so a
/// face menu's "Select Edges of Face" can wire a new rule to the same solid.
public struct SceneItem {
    public var item: ViewportItem
    public var source: Endpoint?

    public init(item: ViewportItem, source: Endpoint?) {
        self.item = item
        self.source = source
    }
}
