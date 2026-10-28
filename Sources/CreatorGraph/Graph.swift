import CreatorGeometry
import CreatorKernel

/// The whole recipe: nodes, wires, document parameters, canvas comments and cable ties. Pure data.
public struct Graph: Sendable, Equatable {
    public var nodes: [NodeID: Node]
    public var links: [Link]
    public var parameters: [GraphParameter]
    /// Sticky notes and comment frames (canvas comments spec 2026-10-09 §7). Editor furniture: they never affect
    /// evaluation. A comment ID is in at most one of the two.
    public var stickies: [CommentID: StickyNote]
    public var frames: [CommentID: CommentFrame]
    /// Cable ties (cable ties spec 2026-10-26 §3). Editor furniture like the comments. Every wire a tie holds is a link's
    /// input here, and every tie holds two or more: `apply` keeps both, and decoding repairs both.
    public var ties: [TieID: CableTie]
    /// The document's display units (DIM-1, format 10). Internal values stay millimetres. Written only when not `.millimetres`.
    public var units: DocumentUnits
    /// The dimensions the user pinned (DIM-3): sorted, unique, each of a node that is here. Editor furniture: never affects
    /// evaluation. Written only when non-empty.
    public var dimensionPins: [DimensionPin]

    public init(nodes: [NodeID: Node] = [:], links: [Link] = [], parameters: [GraphParameter] = [],
                stickies: [CommentID: StickyNote] = [:], frames: [CommentID: CommentFrame] = [:],
                ties: [TieID: CableTie] = [:], units: DocumentUnits = .millimetres,
                dimensionPins: [DimensionPin] = []) {
        self.nodes = nodes
        self.links = links
        self.parameters = parameters
        self.stickies = stickies
        self.frames = frames
        self.ties = ties
        self.units = units
        self.dimensionPins = dimensionPins
    }
}

extension Graph: Codable {
    private enum CodingKeys: String, CodingKey { case nodes, links, parameters, stickies, frames, ties, units, dimensionPins }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let list = try container.decode([Node].self, forKey: .nodes)
        nodes = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        links = try container.decodeIfPresent([Link].self, forKey: .links) ?? []
        parameters = try container.decodeIfPresent([GraphParameter].self, forKey: .parameters) ?? []
        // A hand-edited file may repeat an ID: the first one read wins, and a frame never takes a note's ID.
        var notes: [CommentID: StickyNote] = [:]
        for note in try container.decodeIfPresent([StickyNote].self, forKey: .stickies) ?? [] where notes[note.id] == nil {
            notes[note.id] = note
        }
        var boxes: [CommentID: CommentFrame] = [:]
        for box in try container.decodeIfPresent([CommentFrame].self, forKey: .frames) ?? []
        where boxes[box.id] == nil && notes[box.id] == nil {
            boxes[box.id] = box
        }
        stickies = notes
        frames = boxes
        // Format 9; absent before it. Repaired against the links just read (I1, then I2).
        ties = Self.repaired(try container.decodeIfPresent([CableTie].self, forKey: .ties) ?? [], links: links)
        // Format 10; absent before it, and a file without it is in millimetres.
        units = try container.decodeIfPresent(DocumentUnits.self, forKey: .units) ?? .millimetres
        // DIM-3; absent before it. Pins of nodes that are not here are dropped.
        dimensionPins = Self.repairedPins(try container.decodeIfPresent([DimensionPin].self, forKey: .dimensionPins) ?? [],
                                          nodes: nodes)
        sortLinks()  // Canonical order, so command + undo yields an equal graph.
    }

    /// Nodes are written as an array sorted by ID, so saved files diff cleanly.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nodes.values.sorted { $0.id < $1.id }, forKey: .nodes)
        try container.encode(links, forKey: .links)
        try container.encode(parameters, forKey: .parameters)
        // Comments are written, sorted by ID, only when there are some, so a graph without them is written as before.
        if !stickies.isEmpty { try container.encode(stickies.values.sorted { $0.id < $1.id }, forKey: .stickies) }
        if !frames.isEmpty { try container.encode(frames.values.sorted { $0.id < $1.id }, forKey: .frames) }
        // Ties likewise, each with its wires sorted (`CableTie.encode`), so the output is deterministic.
        if !ties.isEmpty { try container.encode(ties.values.sorted { $0.id < $1.id }, forKey: .ties) }
        if units != .millimetres { try container.encode(units, forKey: .units) }
        if !dimensionPins.isEmpty { try container.encode(dimensionPins, forKey: .dimensionPins) }
    }
}
