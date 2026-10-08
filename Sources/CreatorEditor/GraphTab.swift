import MetalUI

/// Tab over the visible canvas: opens the add-node palette. Bound to `tab` in
/// `GraphPanelInput.keymap`, because the window keymap runs before Tab focus traversal, and an
/// unclaimed binding (`handleAction(_:)` returns false) falls through to traversal (gap M5-b).
public struct GraphTab: Action, Equatable, Sendable {
    public init() {}
}
