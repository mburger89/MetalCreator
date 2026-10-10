extension ViewportPalette {
    /// How much of the selection colour shows in a guide's edges where the part hides them (spec §6.3, Errata (M6)).
    static let hiddenGuideOpacity: Float = 0.35

    /// The selection colour, faded: a guide's edges seen through the part in front of them.
    var hiddenSelection: SIMD4<Float> {
        var faded = selection
        faded.w *= Self.hiddenGuideOpacity
        return faded
    }
}
