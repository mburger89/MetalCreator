import CreatorStyle
import MetalUI

/// The theme's colours for the drawing editor's views: the store's theme, or Dracula without one (headless tests).
/// A value, so an `.equatable()` layer that holds it is redrawn when a theme change alters one of them.
struct DrawingColors: Hashable {
    var paper: HexColor
    var ink: HexColor
    var highlight: HexColor
    var warning: HexColor
    /// The area around the paper.
    var surround: HexColor
    var primary: HexColor
    var secondary: HexColor
    var hairline: HexColor
    var accent: HexColor
    var onAccent: HexColor
    var field: HexColor

    @MainActor
    init(_ store: ThemeStore?) {
        let colors = (store?.current ?? .dracula).colors
        paper = colors.drawingPaper
        ink = colors.drawingInk
        highlight = colors.drawingHighlight
        warning = colors.warning
        surround = colors.backgroundBottom
        primary = colors.foreground
        secondary = colors.comment
        hairline = colors.glassStroke
        accent = colors.accent
        onAccent = colors.textOnAccent
        field = colors.field
    }
}

extension Double {
    /// This length as MetalUI points. Sheet geometry is `Double`; MetalUI lengths are `Float`.
    var px: Pixels { Pixels(Float(self)) }
}
