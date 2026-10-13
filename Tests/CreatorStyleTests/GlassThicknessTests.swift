import CreatorStyle
import MetalUI
import Testing

/// The material opacity a `GlassThickness` reports is read from MetalUI (gap C21-a), so these tests state what any table
/// must satisfy, not its numbers: a thicker material is more opaque, every opacity is a real fraction, and the dark and
/// light schemes are not the same table.
@MainActor
struct GlassThicknessTests {
    @Test(arguments: [true, false])
    func aThickerMaterialIsMoreOpaque(_ isDark: Bool) {
        let opacities = GlassThickness.allCases.map { $0.materialOpacity(isDark: isDark) }
        #expect(opacities == opacities.sorted(), "\(isDark): \(opacities)")
        #expect(Set(opacities).count == opacities.count, "each thickness is its own step")
        #expect(opacities.allSatisfy { $0 > 0 && $0 < 1 })
    }

    @Test func theSchemesAreDifferentTables() {
        let light = GlassThickness.allCases.map { $0.materialOpacity(isDark: false) }
        let dark = GlassThickness.allCases.map { $0.materialOpacity(isDark: true) }
        #expect(light != dark)
    }
}
