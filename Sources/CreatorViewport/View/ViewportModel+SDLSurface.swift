#if !canImport(Metal)
import MetalUI

extension ViewportModel {
    /// The `GPUSurface` draw where there is no Metal. Until the SDL renderer is installed (xp-3 task 8) it clears the surface to the
    /// colour a viewport whose GPU objects could not be made shows on macOS.
    func draw(_ context: any GPUSurfaceContext) {
        context.clear(red: 0.35, green: 0.08, blue: 0.1, alpha: 1)
    }
}
#endif
