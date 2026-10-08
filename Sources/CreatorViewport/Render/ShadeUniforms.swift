/// The shading colours (spec §6.6): the shading ramp (lavender greys in Dracula), hover (cyan) and selection (pink).
struct ShadeUniforms {
    var light: SIMD4<Float>
    var dark: SIMD4<Float>
    var hover: SIMD4<Float>
    var selection: SIMD4<Float>

    init(_ palette: ViewportPalette) {
        light = palette.shadeLight
        dark = palette.shadeDark
        hover = palette.hover
        selection = palette.selection
    }
}
