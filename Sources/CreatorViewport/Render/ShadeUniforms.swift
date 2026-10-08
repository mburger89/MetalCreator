/// The shading colours (spec §6.6): lavender greys, cyan hover and pink selection.
struct ShadeUniforms {
    var light: SIMD4<Float>
    var dark: SIMD4<Float>
    var hover: SIMD4<Float>
    var selection: SIMD4<Float>

    static let palette = ShadeUniforms(light: ViewportPalette.shadeLight, dark: ViewportPalette.shadeDark,
                                       hover: ViewportPalette.hover, selection: ViewportPalette.selection)
}
