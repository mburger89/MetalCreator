import MetalUI

extension ViewportModel {
    /// Primary text over the viewport: the theme's foreground (#f8f8f2 in Dracula, spec §6.6).
    var labelColor: Color { theme.colors.foreground.color }
    /// Secondary and hint text: the theme's comment colour (#6272a4 in Dracula).
    var hintColor: Color { theme.colors.comment.color }
}
