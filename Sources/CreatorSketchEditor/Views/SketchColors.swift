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
}
