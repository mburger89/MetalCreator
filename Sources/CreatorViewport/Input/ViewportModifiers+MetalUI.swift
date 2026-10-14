import MetalUI

extension ViewportModifiers {
    /// The modifiers a hover reads: ⌘ (Ctrl off Apple, MetalUI's `.primary`) suppresses the sketch's inference (sketcher
    /// spec §8). `ViewportView` watches only these (`onModifierKeysChanged(mask:)`), so pressing ⇧ or ⌥ over the viewport
    /// reports and redraws nothing.
    public static let hoverMask: Modifiers = .primary

    public init(_ modifiers: Modifiers) {
        var result: ViewportModifiers = []
        if modifiers.contains(.shift) { result.insert(.shift) }
        // Control is its own key only where it is not the shortcut key: on Linux and Windows Ctrl is `.primary`, and is
        // this model's `.command` alone, as in the graph canvas (`GraphPanelInput.canvasModifiers`). Otherwise a Ctrl press
        // would read as control and command at once, unlike ⌘ on macOS.
        if modifiers.contains(.control), Modifiers.primary != .control { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        // The platform's shortcut key is this model's `.command`: ⌘ on macOS, Ctrl on Linux and Windows.
        if modifiers.contains(.primary) { result.insert(.command) }
        self = result
    }
}
