import MetalUI

extension ViewportPointerButton {
    /// The MetalUI button a viewport drag follows.
    public var mouseButton: MouseButton {
        switch self {
        case .primary: .primary
        case .secondary: .secondary
        case .middle: .middle
        }
    }
}
