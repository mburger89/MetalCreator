import CreatorStyle
import MetalUI

extension CanvasCursor {
    /// The MetalUI pointer style. The closed hand is `GrabCursor`: the system one on macOS, a drawn one on SDL (gap XP-G8).
    @MainActor public var pointerStyle: PointerStyle {
        switch self {
        case .grabbing: GrabCursor.pointerStyle()
        }
    }
}
