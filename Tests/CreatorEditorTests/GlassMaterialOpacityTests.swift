import CreatorStyle
import MetalUI
import Testing

/// `GlassThickness.materialOpacity(isDark:)` reads MetalUI's `Material.tint(in:)` (MetalUI C27, gap C21-a). The glass solve
/// `t = 1 - (1 - g) / (1 - m)` assumes `m` is what the material really composites over its blur, so this renders each
/// material and reads the opacity of the backdrop record MetalUI draws: the tint API and the drawing agree. It guards no
/// copy of a table; MetalUI's own `MT-B` tests pin the API, and human check MT-3 covers the solve against a real window.
@MainActor
struct GlassMaterialOpacityTests {
    func backdropOpacity(_ thickness: GlassThickness, _ scheme: ColorScheme) throws -> Float {
        let scene = renderHeadless {
            ZStack {}.frame(width: Pixels(80), height: Pixels(40)).background(thickness.material)
                .environment(\.colorScheme, scheme)
        }
        return try #require(scene.backdrops.first).tint.a
    }

    @Test(arguments: GlassThickness.allCases, [true, false])
    func theOpacityTheSolveUsesIsTheOneTheMaterialIsDrawnWith(_ thickness: GlassThickness, _ isDark: Bool) throws {
        let drawn = try backdropOpacity(thickness, isDark ? .dark : .light)
        let read = thickness.materialOpacity(isDark: isDark)
        #expect(abs(Double(drawn) - read) < 1e-4, "\(thickness) \(isDark ? "dark" : "light"): drawn \(drawn), read \(read)")
    }
}
