/// A note on the canvas (canvas comments spec 2026-10-09 §7). Pure data: it never affects evaluation. `frame` is in
/// stored (left-to-right) canvas points, as a node's position is: the left dock draws its transpose.
public struct StickyNote: Sendable, Equatable {
    public let id: CommentID
    public var text: String
    public var frame: CanvasRect
    public var accent: AccentRole

    public init(id: CommentID = CommentID(), text: String = "Note", frame: CanvasRect, accent: AccentRole = .muted) {
        self.id = id
        self.text = text
        self.frame = frame
        self.accent = accent
    }
}

/// Saved in `Graph.stickies` (format 5, optional on decode). An accent this build doesn't know reads as muted, so a
/// newer theme role never stops a file from opening.
extension StickyNote: Codable {
    private enum CodingKeys: String, CodingKey { case id, text, frame, accent }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(CommentID.self, forKey: .id),
                  text: try container.decodeIfPresent(String.self, forKey: .text) ?? "",
                  frame: try container.decode(CanvasRect.self, forKey: .frame),
                  accent: (try? container.decodeIfPresent(AccentRole.self, forKey: .accent)) ?? .muted)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(frame, forKey: .frame)
        try container.encode(accent, forKey: .accent)
    }
}
