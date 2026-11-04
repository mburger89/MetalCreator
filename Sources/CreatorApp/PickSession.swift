import CreatorGraph
import CreatorKernel

/// "Pick edges in view…" in progress (spec §5.3 rule 5): the viewport shows only `solid`, and clicking its edges
/// toggles them. Done writes the picks into an Edges by Tag rule: `rule` when there is one, else a new rule wired
/// from `source` into `consumer`. With `lattice` it is "Pick Face in View…" instead (implicit spec §3.5): one click on a face of
/// `solid` sets that lattice node's Face mapping to it.
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
    /// The lattice node a face is being picked for, or `nil` when this picks edges.
    public var lattice: NodeID?
    /// The Loft node and end a face is being picked for, or `nil`.
    public var loftEnd: LoftEndTarget?

    /// The Loft end a face pick sets: the loft's `startFace` or `endFace`.
    public struct LoftEndTarget: Equatable {
        public var loft: NodeID
        public var isStart: Bool

        public init(loft: NodeID, isStart: Bool) {
            self.loft = loft
            self.isStart = isStart
        }
    }

    /// What the pick banner asks for.
    public enum Prompt: Equatable {
        case edges
        case latticeFace
        case loftStartFace
        case loftEndFace

        /// The banner's sentence; `picked` is the number of edges chosen so far.
        public func text(picked: Int) -> String {
            switch self {
            case .edges: "Click edges to pick them · \(picked) picked"
            case .latticeFace: "Click a face of the part to map the lattice to it"
            case .loftStartFace: "Click a flat face of the part for the loft's start"
            case .loftEndFace: "Click a flat face of the part for the loft's end"
            }
        }
    }

    /// What this pick asks the person to click.
    public var prompt: Prompt {
        if let loftEnd { return loftEnd.isStart ? .loftStartFace : .loftEndFace }
        return lattice != nil ? .latticeFace : .edges
    }

    /// Whether this picks one face for a node (a lattice's or a loft's end) rather than edges.
    public var picksFace: Bool { lattice != nil || loftEnd != nil }

    public init(solid: Solid, source: Endpoint, rule: NodeID?, consumer: Endpoint?, picked: [EdgeID], level: [NodeID] = [],
                lattice: NodeID? = nil, loftEnd: LoftEndTarget? = nil) {
        self.solid = solid
        self.source = source
        self.rule = rule
        self.consumer = consumer
        self.picked = picked
        self.level = level
        self.lattice = lattice
        self.loftEnd = loftEnd
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
