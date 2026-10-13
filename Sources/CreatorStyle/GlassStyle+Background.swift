import MetalUI

extension GlassStyle {
    /// The material layer under the tint: the surface's material in the theme's scheme, or nothing when transparency is
    /// reduced. The scheme is set on the material only, so the panel's content keeps the window's.
    @MainActor @ElementBuilder
    fileprivate func materialLayer<S: Shape>(in shape: S) -> some ProposalElementGroup {
        if blursBackdrop {
            shape.fill(thickness.material).environment(\.colorScheme, colorScheme)
        }
    }
}

extension ElementGroup {
    /// Fills `shape` behind this view as `style` says: the material first, blurring what is drawn beneath, then the
    /// theme's tint over it (the later `background` is the one behind, so the tint is written first). A style that
    /// reduces transparency draws the tint alone.
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
