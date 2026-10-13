import MetalUI

extension ViewportModifiers {
    /// The modifiers a hover reads: ⌘ suppresses the sketch's inference (sketcher spec §8). `ViewportView` watches only
    /// these (`onModifierKeysChanged(mask:)`), so pressing ⇧ or ⌥ over the viewport reports and redraws nothing.
    public static let hoverMask: Modifiers = .command

    public init(_ modifiers: Modifiers) {
        var result: ViewportModifiers = []
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.command) { result.insert(.command) }
        self = result
    }
}
