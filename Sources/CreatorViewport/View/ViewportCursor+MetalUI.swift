import CreatorStyle
import MetalUI

extension ViewportCursor {
    /// The MetalUI pointer style. MetalUI's crosshair is `.rectSelection` (SwiftUI has no `.crosshair`). The closed hand is
    /// `GrabCursor`: the system one on macOS, a drawn one on SDL (gap XP-G8).
    @MainActor public var pointerStyle: PointerStyle {
        switch self {
        case .crosshair: .rectSelection
        case .grabbing: GrabCursor.pointerStyle()
        }
    }
}
