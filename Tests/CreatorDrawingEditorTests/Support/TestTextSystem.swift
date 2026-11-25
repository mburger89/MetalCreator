// Test fixture file: the text system the headless render tests draw with.
import MetalUI
#if canImport(MetalUIText)
import MetalUIText
#else
import Foundation
import MetalUIPortableText
import MetalUISystemFonts
#endif

#if !canImport(MetalUIText)
/// The installed fonts, found once: MetalUI's portable text needs a resolver, and a machine with no font cannot run the render tests.
@MainActor
private let installedFonts: PortableFontResolver = {
    do {
        return try SystemFonts.resolver()
    } catch {
        preconditionFailure("The render tests need an installed font: \(error)")
    }
}()
#endif

/// The text system a headless frame is drawn with: CoreText on macOS, as the app's window uses, and MetalUI's portable
/// text over the machine's installed fonts elsewhere.
@MainActor
func testTextSystem() -> any TextSystem {
    #if canImport(MetalUIText)
    CoreTextTextSystem()
    #else
    PortableTextSystem(resolver: installedFonts)
    #endif
}
