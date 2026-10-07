import CreatorGeometry

/// Editor state saved with a document. Every key is optional when decoding, so files stay
/// readable as later milestones add fields (such as the camera in M4).
public struct ViewState: Sendable, Codable, Equatable {
    public var dock: DockSide
    public var canvasOffset: Vector2
    public var canvasZoom: Double

    public init(dock: DockSide = .left, canvasOffset: Vector2 = .zero, canvasZoom: Double = 1) {
        self.dock = dock
        self.canvasOffset = canvasOffset
        self.canvasZoom = canvasZoom
    }

    private enum CodingKeys: String, CodingKey { case dock, canvasOffset, canvasZoom }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dock = try container.decodeIfPresent(DockSide.self, forKey: .dock) ?? .left
        canvasOffset = try container.decodeIfPresent(Vector2.self, forKey: .canvasOffset) ?? .zero
        canvasZoom = try container.decodeIfPresent(Double.self, forKey: .canvasZoom) ?? 1
    }
}
