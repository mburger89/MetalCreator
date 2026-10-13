import MetalUI

/// How frosted a glass panel's material is: MetalUI's five thicknesses, thin to thick (`Material.ultraThinMaterial` and
/// the rest). MetalUI blurs what is drawn beneath the material by one radius (52 points) whatever the thickness; a
/// thicker material lays more of its own grey over the blur, so less of the backdrop and less of the theme's colour
/// shows through (`GlassStyle.tint` makes up the difference).
public enum GlassThickness: String, CaseIterable, Sendable {
    case ultraThin
    case thin
    case regular
    case thick
    case ultraThick

    /// The MetalUI material that blurs the backdrop.
    public var material: Material {
        switch self {
        case .ultraThin: .ultraThinMaterial
        case .thin: .thinMaterial
        case .regular: .regularMaterial
        case .thick: .thickMaterial
        case .ultraThick: .ultraThickMaterial
        }
    }

    /// How opaque the material's own tint is in a light or dark scheme: MetalUI's `LK-L` table (`Material.fill(for:)`,
    /// which is internal). `GlassMaterialTableTests` renders each material and compares, so a MetalUI change fails
    /// a test here instead of shifting every panel's look unseen.
    public func materialOpacity(isDark: Bool) -> Double {
        switch (self, isDark) {
        case (.ultraThin, false): 0.4706
        case (.thin, false): 0.5961
        case (.regular, false): 0.7137
        case (.thick, false): 0.8275
        case (.ultraThick, false): 0.9373
        case (.ultraThin, true): 0.5059
        case (.thin, true): 0.5961
        case (.regular, true): 0.6902
        case (.thick, true): 0.7804
        case (.ultraThick, true): 0.8627
        }
    }
}
