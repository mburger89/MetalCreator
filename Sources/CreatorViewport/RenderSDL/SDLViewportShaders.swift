#if canImport(MetalUISDLGPU)
import Foundation
import MetalUISDLGPU

/// Finds the viewport's compiled shaders (cross-platform spec section 4): HLSL in `Sources/CreatorViewport/Shaders`, compiled on every
/// `swift build` by MetalUI's build-tool plugin `CompileShadersOnBuild` (BS-D; Package.swift applies it on Linux and Windows) and the
/// pinned SDL_shadercross into the `MetalUIAppShaders` resource of this target (SPIR-V for Vulkan, DXIL for Direct3D 12, MSL, a reflection
/// file each, `SOURCE.sha256`, `INCLUDES.sha256`). Nothing compiled is checked in (user decision U1(b)).
enum SDLViewportShaders {
    /// The source tree's compiled directory: this file is `Sources/CreatorViewport/RenderSDL/SDLViewportShaders.swift`, so the target's
    /// directory is two up. Nothing is checked in, so it holds a directory only if someone ran MetalUI's `compile-shaders` into it; the
    /// build's resource bundle and the packaged `MetalUIAppShaders` beside the executable are the real places.
    static var sourceTree: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Shaders/compiled")
    }

    /// The viewport's shader library, or an error naming the directories tried: `MetalUIAppShaders` beside the executable (a package),
    /// then this target's resource bundle (the build's), then `sourceTree` (MetalUI `SDLGPUShaderLibrary.locate`). `sourceTree` is a
    /// parameter, and `bundled: false` skips the resource bundle, so a test can point the search at an empty place.
    static func library(sourceTree: URL = sourceTree, bundled: Bool = true) throws -> SDLGPUShaderLibrary {
        try SDLGPUShaderLibrary.locate(resourceBundle: bundled ? Bundle.module : nil, sourceTree: sourceTree)
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
    static func verify(driver: String = platformDriver, sourceTree: URL = sourceTree, bundled: Bool = true) throws -> Int {
        let library = try library(sourceTree: sourceTree, bundled: bundled)
        for name in names {
            _ = try library.vertex(name, driver: driver)
            _ = try library.fragment(name, driver: driver)
        }
        return names.count * 2
    }
}
#endif
