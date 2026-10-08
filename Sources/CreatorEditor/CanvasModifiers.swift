/// Modifier keys held during a canvas press or drag. MetalUI gives no modifiers on a gesture yet
/// (docs/metalui-gaps.md item 5), so `GraphPanelInput` tracks them from the window's key events.
public struct CanvasModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let shift = CanvasModifiers(rawValue: 1 << 0)
    public static let option = CanvasModifiers(rawValue: 1 << 1)
    public static let command = CanvasModifiers(rawValue: 1 << 2)
}
