import CreatorGraph

/// The view state as a format-3 reader from before the node library decodes it: the same optional keys, without
/// `showsLibrary`. Swift's keyed decoding ignores keys a type doesn't name, so this is what an older build does
/// with a file that has the new key.
struct FormatThreeViewState: Decodable {
    var dock: DockSide
    var canvasZoom: Double

    private enum CodingKeys: String, CodingKey { case dock, canvasOffset, canvasZoom, camera, homeCamera }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dock = try container.decodeIfPresent(DockSide.self, forKey: .dock) ?? .left
        canvasZoom = try container.decodeIfPresent(Double.self, forKey: .canvasZoom) ?? 1
    }
}
