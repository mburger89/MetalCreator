import MetalUI

extension ViewportModel {
    /// Primary text over the viewport: the theme's foreground (#f8f8f2 in Dracula, spec §6.6).
    var labelColor: Color { theme.colors.foreground.color }
    /// Secondary and hint text: the theme's comment colour (#6272a4 in Dracula).
    var hintColor: Color { theme.colors.comment.color }
    /// An overlay label's box: the theme's glass.
    var labelFill: Color { theme.colors.glassFill.color }

    /// An overlay label's text colour: its tint's role in the theme, the same role the GPU draws that tint in.
    func textColor(for tint: OverlayTint) -> Color {
        let colors = theme.colors
        return switch tint {
        case .underConstrained, .preview: colors.sketchUnderConstrained.color
        case .fullyConstrained: colors.sketchFullyConstrained.color
        case .conflicting: colors.sketchConflicting.color
        case .construction: colors.sketchConstruction.color
        case .projected: colors.sketchProjected.color
        case .selected, .region: colors.profileHeader.color
        case .hovered: colors.focus.color
        }
    }
}
