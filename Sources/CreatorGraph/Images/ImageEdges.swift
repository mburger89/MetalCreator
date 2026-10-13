/// What an Image Field does outside its picture's rectangle (fields spec §5). The raw value is the index of the inspector's
/// segmented control, stored in an integer socket.
public enum ImageEdges: Int, Sendable, CaseIterable {
    /// The picture repeats.
    case tile = 0
    /// The nearest edge pixel is held.
    case clamp = 1

    /// The names the segmented control shows, in raw-value order.
    public static let options = ["Tile", "Clamp"]

    /// The edge mode a recipe names ("tile", "clamp").
    public var name: String { self == .tile ? "tile" : "clamp" }
}
