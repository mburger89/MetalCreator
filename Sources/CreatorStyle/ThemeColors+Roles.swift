extension ThemeColors {
    /// The colour of `role`.
    public subscript(role: ThemeRole) -> HexColor {
        get { self[keyPath: role.keyPath] }
        set { self[keyPath: role.keyPath] = newValue }
    }

    /// Every role's colour quantized (`HexColor.quantized`), as a `.mctheme` file holds them.
    public var quantized: ThemeColors {
        var colors = self
        for role in ThemeRole.all { colors[role] = colors[role].quantized }
        return colors
    }
}
