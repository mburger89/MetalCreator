/// Modifier keys held during viewport input. It mirrors MetalUI's `Modifiers`, so the model can be
/// tested without building MetalUI events.
public struct ViewportModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = ViewportModifiers(rawValue: 1 << 0)
    public static let control = ViewportModifiers(rawValue: 1 << 1)
    public static let option = ViewportModifiers(rawValue: 1 << 2)
    public static let command = ViewportModifiers(rawValue: 1 << 3)
}
