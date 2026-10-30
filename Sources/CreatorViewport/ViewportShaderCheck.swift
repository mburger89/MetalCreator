import Foundation

/// `MetalCreator --self-test` asks the viewport whether its shaders were built and ship: Metal compiles its source at run time, so
/// there is nothing to find on macOS; on Linux and Windows the SDL_GPU renderer needs the shaders compiled at build time
/// (`swift build` makes them through MetalUI's `CompileShadersOnBuild` plugin into the target's resource bundle; `MetalUIAppShaders` beside
/// the executable in a shipped app, where packaging copied them), and a build without them draws nothing.
public enum ViewportShaderCheck {
    /// The check failed: the message says where it looked and what to run, in words a person new to the project can follow.
    public struct Failure: Error, CustomStringConvertible, LocalizedError, Equatable {
        public let description: String
        public var errorDescription: String? { description }
    }

    /// What a passing check reports, or `nil` where the viewport has no shader files to find. Throws a ``Failure``.
    public static func run() throws -> String? {
        #if canImport(MetalUISDLGPU)
        try run(sourceTree: SDLViewportShaders.sourceTree)
        #else
        nil
        #endif
    }

    /// The same check against another source-tree directory, without the resource bundle when `bundled` is false (the test points it at an
    /// empty one).
    static func run(sourceTree: URL, bundled: Bool = true) throws -> String? {
        #if canImport(MetalUISDLGPU)
        do {
            let stages = try SDLViewportShaders.verify(sourceTree: sourceTree, bundled: bundled)
            return "the viewport's \(stages.formatted()) SDL_GPU shader stages were found"
        } catch {
            throw Failure(description: "The viewport's compiled SDL_GPU shaders are missing or incomplete (\(error)). "
                + "They are compiled at build time and are not in the repository: "
                + "rebuild with SDL_shadercross at the commit pinned in scripts/shadercross.env "
                + "(METALUI_SHADERCROSS or PATH; swift package clean after installing it), "
                + "and in a shipped app copy the build's MetalUIAppShaders beside the executable.")
        }
        #else
        return nil
        #endif
    }
}
