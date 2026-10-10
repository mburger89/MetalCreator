import CreatorStyle
import MetalUI
import Testing
@testable import CreatorEditor

/// The window background is a top-to-bottom gradient in the theme's two background colours (gap M5-d). The gradient is
/// one MetalUI image; its pixels are read straight from the headless frame.
@MainActor
struct WindowBackgroundTests {
    /// The first and last pixel of the gradient's strip, as red, green, blue.
    func ends(_ store: ThemeStore?) throws -> (top: [Int], bottom: [Int]) {
        let scene = renderHeadless { WindowBackground().environment(store) }
        let texture = try #require(scene.textures.first)
        #expect(scene.textures.count == 1)
        let pixels = texture.pixels
        let last = pixels.count - 4
        return (pixels[0..<3].map(Int.init), pixels[last..<(last + 3)].map(Int.init))
    }

    func rgb(_ hex: HexColor) -> [Int] {
        [Int((hex.rgb >> 16) & 0xff), Int((hex.rgb >> 8) & 0xff), Int(hex.rgb & 0xff)]
    }

    func closeEnough(_ a: [Int], _ b: [Int]) -> Bool {
        zip(a, b).allSatisfy { abs($0 - $1) <= 3 }
    }

    @Test func draculaFadesFromItsTopToItsBottomColour() throws {
        let colours = try ends(nil)
        #expect(closeEnough(colours.top, rgb(HexColor(0x3a3d4e))), "top \(colours.top)")
        #expect(closeEnough(colours.bottom, rgb(HexColor(0x191a21))), "bottom \(colours.bottom)")
    }

    @Test func aSelectedThemeIsTheOneDrawn() throws {
        let store = ThemeStore()
        store.select("nord")
        let colours = try ends(store)
        #expect(closeEnough(colours.top, rgb(ColorTheme.nord.colors.backgroundTop)))
        #expect(closeEnough(colours.bottom, rgb(ColorTheme.nord.colors.backgroundBottom)))
    }

    @Test func theGradientFillsTheWholeFrame() throws {
        let scene = renderHeadless { WindowBackground() }
        let image = try #require(scene.images.first)
        #expect(image.bounds.size.width >= 1800 && image.bounds.size.height >= 1200, "900 x 600 points at scale 2")
    }
}
