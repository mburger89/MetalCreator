extension ViewportPalette {
    // One case per tint, nothing to branch on.
    // swiftlint:disable cyclomatic_complexity
    /// An overlay tint's colour (sketcher spec §8's table, and the axis colours of the layout previews).
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
        case .region: sketchRegion
        case .dimensionDriving: dimensionDriving
        case .dimensionReference: dimensionReference
        case .axisX: axisX
        case .axisY: axisY
        case .axisZ: axisZ
        }
    }
    // swiftlint:enable cyclomatic_complexity
}
