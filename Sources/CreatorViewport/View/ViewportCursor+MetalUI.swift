import MetalUI

extension ViewportCursor {
    /// The MetalUI pointer style. MetalUI's crosshair is `.rectSelection` (SwiftUI has no `.crosshair`).
    public var pointerStyle: PointerStyle {
        switch self {
        case .crosshair: .rectSelection
        case .grabbing: .grabActive
        }
    }
}
