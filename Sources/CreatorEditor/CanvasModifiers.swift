/// Modifier keys held during a canvas press or drag. They come from the gesture's own value
/// (MetalUI C7's `DragGesture.Value.modifiers`, read by `GraphPanelInput`), so they can't go stale.
public struct CanvasModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let shift = CanvasModifiers(rawValue: 1 << 0)
    public static let option = CanvasModifiers(rawValue: 1 << 1)
    public static let command = CanvasModifiers(rawValue: 1 << 2)
}
