#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU

/// Finds the viewport's compiled shaders (cross-platform spec section 4): HLSL in `Shaders/viewport`, compiled at build time by
/// `scripts/build-shaders.sh` (`.ps1` on Windows) through MetalUI's `MetalUICompileShaders` and the pinned SDL_shadercross into
/// `Shaders/viewport/compiled` (SPIR-V for Vulkan, DXIL for Direct3D 12, MSL, a reflection file each, `SOURCE.sha256`). The directory is a
/// build product: git-ignored, never checked in (user decision U1(b)).
enum SDLViewportShaders {
    /// The source tree's compiled directory: this file is `Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift`, so the
    /// repository root is four directories up. Valid on the machine that built the app; a shipped app carries a copy as
    /// `MetalUIAppShaders` beside the executable (MetalUI `docs/packaging.md` section 4a), which is looked for first.
    static var sourceTree: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Shaders/viewport/compiled")
    }

    /// The viewport's shader library, or an error naming the directories tried. `sourceTree` is a parameter so a test (and
    /// `ViewportShaderCheck`'s test) can point it at an empty directory.
    static func library(sourceTree: URL = sourceTree) throws -> SDLGPUShaderLibrary {
        try SDLGPUShaderLibrary.locate(sourceTree: sourceTree)
    }

    /// Every shader the viewport builds a pipeline from; each has a vertex stage and a fragment stage of the same name.
    static let names = ["background", "fill", "mesh", "field_mesh", "line", "grid", "cube", "slice", "id_mesh", "id_line"]

    /// The driver whose blobs this platform's SDL picks: Direct3D 12 (DXIL) on Windows, Vulkan (SPIR-V) elsewhere.
    static var platformDriver: String {
        #if os(Windows)
        "direct3d12"
        #else
        "vulkan"
        #endif
    }

    /// Loads every blob for `driver`, which proves the directory and each stage's file and reflection are there, and returns how many
    /// stages that was.
    static func verify(driver: String = platformDriver, sourceTree: URL = sourceTree) throws -> Int {
        let library = try library(sourceTree: sourceTree)
        for name in names {
            _ = try library.vertex(name, driver: driver)
            _ = try library.fragment(name, driver: driver)
        }
        return names.count * 2
    }
}
#endif
