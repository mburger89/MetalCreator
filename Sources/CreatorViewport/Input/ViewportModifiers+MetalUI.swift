import MetalUI

extension ViewportModifiers {
    /// The modifiers a hover reads: ⌘ (Ctrl off Apple, MetalUI's `.primary`) suppresses the sketch's inference (sketcher
    /// spec §8). `ViewportView` watches only these (`onModifierKeysChanged(mask:)`), so pressing ⇧ or ⌥ over the viewport
    /// reports and redraws nothing.
    public static let hoverMask: Modifiers = .primary

    public init(_ modifiers: Modifiers) {
        var result: ViewportModifiers = []
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        // The platform's shortcut key is this model's `.command`: ⌘ on macOS, Ctrl on Linux and Windows.
        if modifiers.contains(.primary) { result.insert(.command) }
        self = result
    }
}
