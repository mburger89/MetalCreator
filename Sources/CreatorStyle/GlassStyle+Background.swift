import MetalUI

extension GlassStyle {
    /// The material layer under the tint: the surface's material in the theme's scheme. Always drawn: when Reduce
    /// Transparency is on MetalUI draws it as an opaque grey rect with no blur (divergence 315), which the tint then
    /// covers. The scheme is set on the material only, so the panel's content keeps the window's.
    @MainActor @ElementBuilder
    fileprivate func materialLayer<S: Shape>(in shape: S) -> some ProposalElementGroup {
        shape.fill(thickness.material).environment(\.colorScheme, colorScheme)
    }
}

extension ElementGroup {
    /// Fills `shape` behind this view as `style` says: the material first, blurring what is drawn beneath, then the
    /// theme's tint over it (the later `background` is the one behind, so the tint is written first). With Reduce
    /// Transparency on, MetalUI turns the material into an opaque grey, and a style that reduces transparency makes
    /// the tint opaque.
    public func glassBackground<S: Shape>(_ style: GlassStyle, in shape: S) -> some ElementGroup {
        background(style.tint.color, in: shape).background { style.materialLayer(in: shape) }
    }
}

extension ProposalElementGroup {
    /// `glassBackground(_:in:)` for a view that is still a proposal view, so a chip can be offset after its glass.
    public func glassBackground<S: Shape>(_ style: GlassStyle, in shape: S) -> some ProposalElementGroup {
        background(style.tint.color, in: shape).background { style.materialLayer(in: shape) }
    }
}
