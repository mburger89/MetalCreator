import CreatorStyle
import MetalUI
import Testing

/// `GlassThickness.materialOpacity(isDark:)` copies MetalUI's `LK-L` table, which MetalUI keeps internal. This renders
/// each material and reads the opacity MetalUI really gives its backdrop record, so a MetalUI change to the table fails here.
@MainActor
struct GlassMaterialTableTests {
    func backdropOpacity(_ thickness: GlassThickness, _ scheme: ColorScheme) throws -> Float {
        let scene = renderHeadless {
            ZStack {}.frame(width: Pixels(80), height: Pixels(40)).background(thickness.material)
                .environment(\.colorScheme, scheme)
        }
        return try #require(scene.backdrops.first).tint.a
    }

    @Test(arguments: GlassThickness.allCases)
    func ourTableIsMetalUIs(_ thickness: GlassThickness) throws {
        let dark = try backdropOpacity(thickness, .dark)
        let light = try backdropOpacity(thickness, .light)
        #expect(abs(Double(dark) - thickness.materialOpacity(isDark: true)) < 1e-4, "\(thickness) dark: \(dark)")
        #expect(abs(Double(light) - thickness.materialOpacity(isDark: false)) < 1e-4, "\(thickness) light: \(light)")
    }
}
