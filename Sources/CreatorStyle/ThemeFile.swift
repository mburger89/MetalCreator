import Foundation

/// The `.mctheme` file (Themes milestone): small, versioned JSON holding a theme's name, whether it is dark, and a
/// colour per role, keyed by role name (`ThemeRole.name`), as `#rrggbb` or, when translucent, `#rrggbbaa`:
///
/// ```json
/// { "colors" : { "accent" : "#bd93f9", "backgroundBottom" : "#191a21", … }, "dark" : true, "name" : "Midnight",
///   "version" : 1 }
/// ```
///
/// Reading forgives what it safely can and refuses the rest plainly: a missing role is Dracula's (quantized, as every
/// colour a file holds is), a role this version doesn't know is ignored (a newer MetalCreator's), a missing `dark`
/// follows the panel base's lightness and a missing name is the caller's fallback (the file's name); but a colour
/// that isn't one is refused, naming the role, and so is a file from a newer version or one that isn't a theme. The
/// theme's id is not in the file: it is the caller's (the themes folder names files by id; an import makes a new one).
public enum ThemeFile {
    /// The version this build writes and the newest it reads.
    public static let currentVersion = 1

    /// The file's bytes: every role, keys sorted, so the same theme always writes the same file.
    public static func encode(_ theme: ColorTheme) throws -> Data {
        var colors: [String: ThemeFileColor] = [:]
        for role in ThemeRole.all { colors[role.name] = .text(theme.colors[role].hex) }
        let body = ThemeFileBody(version: currentVersion, name: theme.name, dark: theme.isDark, colors: colors)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(body)
    }

    /// The theme in `data`, with `id`, named `fallbackName` if the file names it nothing.
    public static func decode(_ data: Data, id: ColorTheme.ID, fallbackName: String) throws(ThemeFileError) -> ColorTheme {
        let body: ThemeFileBody
        do {
            body = try JSONDecoder().decode(ThemeFileBody.self, from: data)
        } catch {
            throw .damaged
        }
        guard body.version >= 1 else { throw .damaged }
        guard body.version <= currentVersion else { throw .newerVersion(body.version) }
        // Quantized like every custom theme's colours, so a missing role reads back from a saved file unchanged.
        var colors = ColorTheme.dracula.colors.quantized
        for role in ThemeRole.all {
            guard let entry = body.colors[role.name] else { continue }
            guard case .text(let text) = entry, let colour = HexColor(hex: text) else { throw .notAColour(role: role.name) }
            colors[role] = colour
        }
        let name = body.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ColorTheme(id: id, name: name.isEmpty ? fallbackName : name, isDark: body.dark ?? isDarkSurface(colors.panelBase),
                          colors: colors)
    }

    /// Whether `colour` is on the dark side of mid-grey: a file that doesn't say asks for dark controls on a dark panel.
    static func isDarkSurface(_ colour: HexColor) -> Bool {
        let channels = [16, 8, 0].map { (colour.rgb >> UInt32($0)) & 0xff }
        return channels.reduce(0, +) < 3 * 128
    }
}
