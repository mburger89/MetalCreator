import MetalUI
#if canImport(MetalUIText)
import MetalUIText
#else
import MetalUIPortableText
import MetalUISystemFonts
#endif

/// Where the view cube's face names get their glyphs: the text system the platform draws the rest of the app with, so the
/// names are in the same system face. CoreText's on macOS; MetalUI's portable text over the installed fonts elsewhere.
@MainActor
enum CubeLabelFonts {
    /// The atlas of the six names, or a blank one (the cube draws, unlabelled) when there is no text system or it draws no ink.
    static func atlas() -> CubeLabelAtlas {
        textSystem().flatMap { CubeLabelAtlas.rasterize(using: $0) } ?? .blank
    }

    private static func textSystem() -> (any TextSystem)? {
        #if canImport(MetalUIText)
        CoreTextTextSystem()
        #else
        (try? SystemFonts.resolver()).map { PortableTextSystem(resolver: $0) }
        #endif
    }
}
