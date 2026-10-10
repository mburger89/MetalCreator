import CreatorKernel

/// The whole recipe: nodes, wires, document parameters and canvas comments. Pure data.
public struct Graph: Sendable, Equatable {
    public var nodes: [NodeID: Node]
    public var links: [Link]
    public var parameters: [GraphParameter]
    /// Sticky notes and comment frames (canvas comments spec 2026-10-09 §7). Editor furniture: they never affect
    /// evaluation. A comment ID is in at most one of the two.
    public var stickies: [CommentID: StickyNote]
    public var frames: [CommentID: CommentFrame]

    public init(nodes: [NodeID: Node] = [:], links: [Link] = [], parameters: [GraphParameter] = [],
                stickies: [CommentID: StickyNote] = [:], frames: [CommentID: CommentFrame] = [:]) {
        self.nodes = nodes
        self.links = links
        self.parameters = parameters
        self.stickies = stickies
        self.frames = frames
    }
}

extension Graph: Codable {
    private enum CodingKeys: String, CodingKey { case nodes, links, parameters, stickies, frames }

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
    }
}
