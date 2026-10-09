import CreatorGeometry

/// A press on a node-library type, followed in window points by a `DragGesture` on its row
/// (`GraphPanelInput.libraryGesture(for:)`): MetalUI's own gesture inside the window, no system drag and drop.
/// Until the pointer has moved `threshold` from the press it is still a click.
public struct LibraryDrag: Equatable, Sendable {
    /// How far, in points, the pointer must move from the press before it is a drag rather than a click (MetalUI's
    /// and SwiftUI's default `DragGesture` minimum distance).
    public static let threshold = 10.0

    public var typeID: String
    /// The press, in window points.
    public var start: Vector2
    /// The pointer now, in window points.
    public var location: Vector2

    public init(typeID: String, start: Vector2, location: Vector2) {
        self.typeID = typeID
        self.start = start
        self.location = location
    }

    /// Whether the pointer has moved far enough from the press for this to be a drag rather than a click.
    public var isDragging: Bool { (location - start).length >= Self.threshold }
}
