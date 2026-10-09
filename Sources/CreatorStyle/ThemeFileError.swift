/// Why a `.mctheme` file can't be read, as one plain sentence (`message`).
public enum ThemeFileError: Error, Equatable, Sendable {
    /// Not JSON, or JSON without a theme's `version` and `colors`.
    case damaged
    /// Written by a newer MetalCreator in a version this one can't read.
    case newerVersion(Int)
    /// The colour of the role named `role` isn't `#rrggbb` or `#rrggbbaa`.
    case notAColour(role: String)

    public var message: String {
        switch self {
        case .damaged:
            "It isn’t a MetalCreator theme, or it is damaged."
        case .newerVersion(let version):
            "It was made by a newer MetalCreator (theme version \(version)); this one reads version \(ThemeFile.currentVersion)."
        case .notAColour(let role):
            "‘\(role)’ isn’t a colour like \(Self.example(for: role))."
        }
    }

    /// Dracula's colour for `role`, to show what a colour looks like.
    private static func example(for role: String) -> String {
        ThemeRole.named(role).map { ColorTheme.dracula.colors[$0].hex } ?? "#ff79c6"
    }
}
