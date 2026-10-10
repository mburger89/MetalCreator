import CreatorStyle
import MetalUI

/// The theme's colours for the sketch editor's views: the store's theme, or Dracula without one (headless tests).
struct SketchColors {
    let colors: ThemeColors

    @MainActor
    init(_ store: ThemeStore?) {
        colors = (store?.current ?? .dracula).colors
    }

    var primary: Color { colors.foreground.color }
    var secondary: Color { colors.comment.color }
    var problem: Color { colors.error.color }
    var warning: Color { colors.warning.color }
    /// Inferred constraints' glyphs: the selection's colour (the Sketch node's header green).
    var inferred: Color { colors.profileHeader.color }
    /// Floating chrome: the theme's glass and its hairline.
    var glass: Color { colors.glassFill.color }
    var hairline: Color { colors.glassStroke.color }
}
