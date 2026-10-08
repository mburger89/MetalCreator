import CreatorGraph
import CreatorKernel

/// The inspector's header bar for the selected node: its name, category colour and status.
public struct InspectorHeader: Equatable, Sendable {
    public var node: NodeID
    public var title: String
    public var category: NodeCategory
    public var state: NodeState?
}
