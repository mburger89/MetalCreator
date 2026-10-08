/// A colour theme: a name and a colour for every role (`ThemeColors`). Themes are app-level: the
/// `ThemeStore` holds the one shown, and a `.mcgraph` file never stores one. M6 ships three read-only
/// built-ins; custom themes and `.mctheme` files are the Themes milestone after M6.
public struct ColorTheme: Identifiable, Hashable, Sendable {
    /// Stable across launches and renames: what preferences remember.
    public var id: String
    /// The name shown in View ▸ Theme.
    public var name: String
    /// A dark theme asks the window for MetalUI's dark controls, a light one for its light controls.
    public var isDark: Bool
    public var colors: ThemeColors

    public init(id: String, name: String, isDark: Bool, colors: ThemeColors) {
        self.id = id
        self.name = name
        self.isDark = isDark
        self.colors = colors
    }

    /// The built-in themes, in menu order. Dracula, the default, comes first.
    public static let builtIns = [dracula, alucard, nord]
}
