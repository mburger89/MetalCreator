import CreatorGeometry

/// Editor state saved with a document. Every key is optional when decoding, so files stay
/// readable as later milestones add fields. Older readers ignore keys they don't know.
public struct ViewState: Sendable, Codable, Equatable {
    public var dock: DockSide
    public var canvasOffset: Vector2
    public var canvasZoom: Double
    /// The viewport camera when the document was saved (M4). `nil` in older files, in which case the viewport
    /// frames the part when it first appears.
    public var camera: CameraPose?
    /// The document's home view, set from the viewport's View menu (spec §6.3). `nil` means isometric and framed.
    public var homeCamera: CameraPose?

    public init(dock: DockSide = .left, canvasOffset: Vector2 = .zero, canvasZoom: Double = 1,
                camera: CameraPose? = nil, homeCamera: CameraPose? = nil) {
        self.dock = dock
        self.canvasOffset = canvasOffset
        self.canvasZoom = canvasZoom
        self.camera = camera
        self.homeCamera = homeCamera
    }

    private enum CodingKeys: String, CodingKey { case dock, canvasOffset, canvasZoom, camera, homeCamera }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dock = try container.decodeIfPresent(DockSide.self, forKey: .dock) ?? .left
        canvasOffset = try container.decodeIfPresent(Vector2.self, forKey: .canvasOffset) ?? .zero
        canvasZoom = try container.decodeIfPresent(Double.self, forKey: .canvasZoom) ?? 1
        camera = try container.decodeIfPresent(CameraPose.self, forKey: .camera)
        homeCamera = try container.decodeIfPresent(CameraPose.self, forKey: .homeCamera)
    }
}
