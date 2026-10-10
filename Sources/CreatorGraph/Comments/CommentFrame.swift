/// A titled frame drawn behind the nodes (canvas comments spec 2026-10-09 §7). Pure data: which nodes it holds is
/// geometric and never stored. `frame` is in stored (left-to-right) canvas points, as a node's position is: the left
/// dock draws its transpose. The title bar is the top strip of the drawn rectangle.
public struct CommentFrame: Sendable, Equatable {
    public let id: CommentID
    public var title: String
    public var frame: CanvasRect
    public var accent: AccentRole

    public init(id: CommentID = CommentID(), title: String = "Frame", frame: CanvasRect, accent: AccentRole = .muted) {
        self.id = id
        self.title = title
        self.frame = frame
        self.accent = accent
    }
}

/// Saved in `Graph.frames` (format 5, optional on decode); an unknown accent reads as muted.
extension CommentFrame: Codable {
    private enum CodingKeys: String, CodingKey { case id, title, frame, accent }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(CommentID.self, forKey: .id),
                  title: try container.decodeIfPresent(String.self, forKey: .title) ?? "Frame",
                  frame: try container.decode(CanvasRect.self, forKey: .frame),
                  accent: (try? container.decodeIfPresent(AccentRole.self, forKey: .accent)) ?? .muted)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(frame, forKey: .frame)
        try container.encode(accent, forKey: .accent)
    }
}
