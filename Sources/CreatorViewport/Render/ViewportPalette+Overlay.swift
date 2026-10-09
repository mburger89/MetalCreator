extension ViewportPalette {
    /// An overlay tint's colour (sketcher spec §8's table).
    func color(_ tint: OverlayTint) -> SIMD4<Float> {
        switch tint {
        case .underConstrained: sketchUnderConstrained
        case .fullyConstrained: sketchFullyConstrained
        case .conflicting: sketchConflicting
        case .construction: sketchConstruction
        case .projected: sketchProjected
        case .selected: sketchSelected
        case .hovered: hover
        case .preview: sketchPreview
        }
    }
}
