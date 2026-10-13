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

    /// How opaque the material's own tint is in a light or dark scheme: the opacity of MetalUI's `Material.tint(in:)`
    /// (MetalUI C27, record 101, ruling `MT-B`), which is the tint the material composites over its blur. Read from
    /// MetalUI each time, so a retune of its fitted table moves every panel's tint with it and nothing here copies it.
    public func materialOpacity(isDark: Bool) -> Double {
        let tint = material.tint(in: isDark ? .dark : .light)
        return Double(tint.resolve(in: EnvironmentValues()).opacity)
    }
}
