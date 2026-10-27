import CreatorGraph
import CreatorStyle
import MetalUI

/// A tie's band (cable ties spec 2026-10-26 §5.1): a rounded rectangle across its lanes, in the theme's glass stroke, or in
/// its selection colour while the tie is selected. `band` is in display canvas points.
struct TieBandView: Component, Equatable {
    let band: CanvasRect
    let isSelected: Bool
    let palette: Palette

    var content: some ElementGroup {
        RoundedRectangle(cornerRadius: TieLayout.bandOverhang.px)
            .fill((isSelected ? palette.selection : palette.hairline).color)
            .frame(width: band.size.x.px, height: band.size.y.px)
            .offset(x: band.origin.x.px, y: band.origin.y.px)
    }
}
