import CreatorGraph
import CreatorKernel

/// "Pick edges in view…" in progress (spec §5.3 rule 5): the viewport shows only `solid`, and clicking its edges
/// toggles them. Done writes the picks into an Edges by Tag rule: `rule` when there is one, else a new rule wired
/// from `source` into `consumer`.
public struct PickSession {
    /// The solid being picked on.
    public var solid: Solid
    /// The output that produces `solid`, which a new rule's `solid` input is wired from.
    public var source: Endpoint
    /// The Edges by Tag node that receives the picks, or `nil` to make one.
    public var rule: NodeID?
    /// The feature input (Fillet or Chamfer `edges`) a new rule is wired into.
    public var consumer: Endpoint?
    /// The picked edges, in the order they were picked.
    public var picked: [EdgeID]
    /// The level of the graph panel the pick began on (`EditorModel.levelPath`): `source`, `rule` and `consumer` are
    /// nodes of that level's graph, and Done writes there.
    public var level: [NodeID]

    public init(solid: Solid, source: Endpoint, rule: NodeID?, consumer: Endpoint?, picked: [EdgeID], level: [NodeID] = []) {
        self.solid = solid
        self.source = source
        self.rule = rule
        self.consumer = consumer
        self.picked = picked
        self.level = level
    }

    /// Adds `edge`, or removes it if it's already picked.
    public mutating func toggle(_ edge: EdgeID) {
        if let index = picked.firstIndex(of: edge) {
            picked.remove(at: index)
        } else {
            picked.append(edge)
        }
    }

    /// Adds every edge not yet picked, keeping their order.
    public mutating func add(_ edges: [EdgeID]) {
        for edge in edges where !picked.contains(edge) { picked.append(edge) }
    }
}
