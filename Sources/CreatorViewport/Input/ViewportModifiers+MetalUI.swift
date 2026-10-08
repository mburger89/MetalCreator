import MetalUI

extension ViewportModifiers {
    public init(_ modifiers: Modifiers) {
        var result: ViewportModifiers = []
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.command) { result.insert(.command) }
        self = result
    }
}
