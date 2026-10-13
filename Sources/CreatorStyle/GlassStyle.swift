import MetalUI

/// What one glass surface looks like in one theme (spec §6.1, §6.6): a MetalUI material that blurs the backdrop, and the
/// theme's own `glassFill` over it. The theme owns the colour: the tint is the role's colour and the role's opacity is
/// still how much of the backdrop the panel lets through, as it was when the glass was a flat tint with nothing under
/// it. So the tint's own opacity is lowered to make up for the material under it (`tintOpacity(glass:materialOpacity:)`):
/// Dracula's 86% glass over `.ultraThinMaterial` is a 72% tint over the material, and the two together hide 86% of the
/// backdrop, as the flat tint did. A value, so the views stay thin and a test reads what they will draw.
public struct GlassStyle: Hashable, Sendable {
    public let thickness: GlassThickness
    /// The theme's `glassFill`: its colour and the opacity the person chose for the whole panel.
    public let fill: HexColor
    /// Whether the theme is a dark one; the material's grey and the controls follow it.
    public let isDark: Bool
    /// Reduce Transparency, the system setting as MetalUI's `\.accessibilityReduceTransparency` reads it (MetalUI C27, gap
    /// C21-b). MetalUI itself then draws the material as an opaque grey rect with no blur (divergence 315), so the style
    /// keeps the material layer and leaves the fallback to MetalUI; what the style changes is the theme's tint over it,
    /// which goes fully opaque so the theme's text sits on the colour it was designed for (plan decision U-C27-1).
    public let reducesTransparency: Bool

    public init(theme: ColorTheme, surface: GlassSurface, reducesTransparency: Bool = false) {
        thickness = surface.thickness
        fill = theme.colors.glassFill
        isDark = theme.isDark
        self.reducesTransparency = reducesTransparency
    }

    /// The style in the theme `themes` shows, or Dracula's without a store (headless tests, `GraphPanelPreview`).
    @MainActor
    public init(themes: ThemeStore?, surface: GlassSurface, reducesTransparency: Bool = false) {
        self.init(theme: themes?.current ?? .dracula, surface: surface, reducesTransparency: reducesTransparency)
    }

    /// The theme's colour laid over the material: its role's colour at the opacity that, with the material beneath, hides
    /// as much of the backdrop as the role's own opacity says. Fully opaque when transparency is reduced.
    public var tint: HexColor {
        guard !reducesTransparency else { return fill.opacity(1) }
        let material = thickness.materialOpacity(isDark: isDark)
        return fill.opacity(Self.tintOpacity(glass: fill.opacity, materialOpacity: material))
    }

    /// The colour scheme the material is drawn in: the theme's, not the window's.
    public var colorScheme: ColorScheme { isDark ? .dark : .light }

    /// The opacity of a tint laid over a material of opacity `materialOpacity` so that together they let through
    /// `1 - glass` of the backdrop: `(1 - tint) * (1 - material) = 1 - glass`. At least 0 (a material already more
    /// opaque than the glass gets no tint) and at most 1.
    public static func tintOpacity(glass: Double, materialOpacity: Double) -> Double {
        guard materialOpacity < 1 else { return 0 }
        return min(1, max(0, 1 - (1 - glass) / (1 - materialOpacity)))
    }
}
