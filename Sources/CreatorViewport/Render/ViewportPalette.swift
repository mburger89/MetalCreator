import CreatorStyle

/// A theme's viewport colours (spec §6.6) as gamma-space RGBA for the GPU: each role's hex value divided by 255,
/// because MetalUI composites in gamma space. The viewport makes one from its `theme` for every frame, so a theme
/// switch reaches the uniforms on the next frame.
struct ViewportPalette: Hashable, Sendable {
    var backgroundTop: SIMD4<Float>
    var backgroundBottom: SIMD4<Float>
    var shadeLight: SIMD4<Float>
    var shadeDark: SIMD4<Float>
    var edge: SIMD4<Float>
    /// Viewport hover, and the view cube's hovered and active regions: the theme's focus colour.
    var hover: SIMD4<Float>
    var selection: SIMD4<Float>
    /// Handles of solid nodes and of feature nodes: their categories' header colours.
    var solid: SIMD4<Float>
    var feature: SIMD4<Float>
    var gridMinor: SIMD4<Float>
    var gridMajor: SIMD4<Float>
    var cubeFace: SIMD4<Float>
    var cubeRim: SIMD4<Float>
    /// The face names painted on the view cube.
    var cubeLabel: SIMD4<Float>
    var axisX: SIMD4<Float>
    var axisY: SIMD4<Float>
    var axisZ: SIMD4<Float>
    /// The sketch overlay (sketcher spec §8): free, fixed, conflicting, construction and projected geometry, the
    /// selection (the Sketch node's header colour) and a tool's rubber band (the free colour, faded).
    var sketchUnderConstrained: SIMD4<Float>
    var sketchFullyConstrained: SIMD4<Float>
    var sketchConflicting: SIMD4<Float>
    var sketchConstruction: SIMD4<Float>
    var sketchProjected: SIMD4<Float>
    var sketchSelected: SIMD4<Float>
    var sketchPreview: SIMD4<Float>

    init(_ theme: ColorTheme) {
        let colors = theme.colors
        backgroundTop = colors.backgroundTop.rgba
        backgroundBottom = colors.backgroundBottom.rgba
        shadeLight = colors.shadeLight.rgba
        shadeDark = colors.shadeDark.rgba
        edge = colors.edge.rgba
        hover = colors.focus.rgba
        selection = colors.selection.rgba
        solid = colors.solidHeader.rgba
        feature = colors.featureHeader.rgba
        gridMinor = colors.gridMinor.rgba
        gridMajor = colors.gridMajor.rgba
        cubeFace = colors.cubeFace.rgba
        cubeRim = colors.cubeRim.rgba
        cubeLabel = colors.cubeLabel.rgba
        axisX = colors.axisX.rgba
        axisY = colors.axisY.rgba
        axisZ = colors.axisZ.rgba
        sketchUnderConstrained = colors.sketchUnderConstrained.rgba
        sketchFullyConstrained = colors.sketchFullyConstrained.rgba
        sketchConflicting = colors.sketchConflicting.rgba
        sketchConstruction = colors.sketchConstruction.rgba
        sketchProjected = colors.sketchProjected.rgba
        sketchSelected = colors.profileHeader.rgba
        sketchPreview = colors.sketchUnderConstrained.opacity(0.6).rgba
    }

    /// The default theme's colours.
    static let dracula = ViewportPalette(.dracula)
}
