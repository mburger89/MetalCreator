import MetalUI

extension ColorTheme {
    /// MetalUI's control tokens in this theme, for `.theme(_:)` over the window, so MetalUI's own buttons, fields,
    /// menus, pickers, sliders, toggles and colour wells match the panels. Each token takes the role it means: the
    /// canvas `background` is the gradient's bottom, a control's `surface` the node body (a dark theme) or the panel base (a light one: MetalUI draws a selected segment, a slider thumb and a menu in `surface`, and a light theme's glass is its node-body colour, so a node-body surface would vanish into the panel and a segmented control would look inverted, the track standing out instead of the selection), a track
    /// (`surfaceSecondary`) the field colour, `accent` the accent, `separator` (hairlines, and a control's accent
    /// outside the key window) the secondary text, `textPrimary` the text, and the scroll thumb the text at 35%.
    /// The modal `scrim` and the default `shadow`, which no role names, stay MetalUI's for a dark or a light theme.
    public var controlTheme: Theme {
        let base: Theme = isDark ? .dark : .light
        return Theme(background: colors.backgroundBottom.hsla, surface: (isDark ? colors.nodeBody : colors.panelBase).hsla,
                     surfaceSecondary: colors.field.hsla, accent: colors.accent.hsla, separator: colors.comment.hsla,
                     textPrimary: colors.foreground.hsla, scrollIndicator: colors.foreground.opacity(0.35).hsla,
                     scrim: base.scrim, shadow: base.shadow)
    }
}

extension HexColor {
    /// The colour as MetalUI's `Hsla`, for theme tokens.
    public var hsla: Hsla { .rgb(rgb & 0xffffff, alpha: Float(opacity)) }
}
