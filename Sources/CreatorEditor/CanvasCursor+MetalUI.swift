import MetalUI

extension CanvasCursor {
    /// The MetalUI pointer style.
    public var pointerStyle: PointerStyle {
        switch self {
        case .grabbing: .grabActive
        }
    }
}
