import CreatorStyle
import Foundation
import Testing

/// `.mctheme` files: small, versioned JSON of hex colours by role. Missing roles are Dracula's, unknown roles are
/// ignored, and anything that isn't a theme is refused with one plain sentence.
struct ThemeFileTests {
    /// A custom theme as the app holds one: quantized colours, a few changed.
    static let midnight: ColorTheme = {
        var colors = ColorTheme.dracula.colors.quantized
        colors.selection = HexColor(0x00ffaa)
        colors.glassFill = HexColor(0x101010, opacity: 128.0 / 255)
        return ColorTheme(id: "custom-1", name: "Midnight", isDark: false, colors: colors)
    }()

    func decode(_ json: String, fallbackName: String = "File") throws(ThemeFileError) -> ColorTheme {
        try ThemeFile.decode(Data(json.utf8), id: "custom-2", fallbackName: fallbackName)
    }

    @Test func aThemeRoundTripsExactly() throws {
        let data = try ThemeFile.encode(Self.midnight)
        #expect(try ThemeFile.decode(data, id: "custom-1", fallbackName: "") == Self.midnight)
        #expect(try ThemeFile.encode(Self.midnight) == data, "the same theme always writes the same bytes")
    }

    @Test func theFileIsVersionedJSONWithEveryRoleAsHex() throws {
        let object = try #require(try JSONSerialization.jsonObject(with: ThemeFile.encode(ColorTheme.dracula)) as? [String: Any])
        #expect(object.keys.sorted() == ["colors", "dark", "name", "version"])
        #expect(object["version"] as? Int == 1)
        #expect(object["name"] as? String == "Dracula")
        #expect(object["dark"] as? Bool == true)
        let colors = try #require(object["colors"] as? [String: String])
        #expect(colors.keys.sorted() == ThemeRole.all.map(\.name).sorted())
        #expect(colors["selection"] == "#ff79c6")
        #expect(colors["glassFill"] == "#21222cdb")
    }

    /// A missing role is Dracula's, quantized like every colour a file holds (Dracula's glass is 0.86 opaque, a file's
    /// 219/255), so the theme equals itself once saved and read back.
    @Test func missingRolesAreDraculas() throws {
        let theme = try decode(##"{ "version": 1, "name": "Pink", "dark": true, "colors": { "selection": "#00ff00" } }"##)
        var expected = ColorTheme.dracula.colors.quantized
        expected.selection = HexColor(0x00ff00)
        #expect(theme == ColorTheme(id: "custom-2", name: "Pink", isDark: true, colors: expected))
    }

    @Test func unknownRolesAndKeysAreIgnored() throws {
        let theme = try decode(##"""
        { "version": 1, "name": "Later", "dark": true, "author": "someone",
          "colors": { "accent": "#112233", "sparkle": "#123456", "glow": "not a colour", "rim": { "a": 1 }, "n": 3 } }
        """##)
        #expect(theme.colors.accent == HexColor(0x112233))
        #expect(theme.name == "Later")
    }

    @Test func aBadColourIsRefusedNamingItsRole() {
        #expect(throws: ThemeFileError.notAColour(role: "selection")) {
            try decode(#"{ "version": 1, "colors": { "selection": "pink" } }"#)
        }
        #expect(ThemeFileError.notAColour(role: "selection").message == "‘selection’ isn’t a colour like #ff79c6.")
        #expect(throws: ThemeFileError.notAColour(role: "accent")) {
            try decode(#"{ "version": 1, "colors": { "accent": 12 } }"#)
        }
        #expect(ThemeFileError.notAColour(role: "accent").message == "‘accent’ isn’t a colour like #bd93f9.")
    }

    @Test(arguments: [
        "not json", "{}", "[]", #"{ "version": 1 }"#, #"{ "colors": {} }"#, #"{ "version": 0, "colors": {} }"#,
        #"{ "version": "1", "colors": {} }"#, #"{ "formatVersion": 4, "graph": { "nodes": {} } }"#,
    ])
    func whatIsntAThemeIsRefused(_ json: String) {
        #expect(throws: ThemeFileError.damaged) { try decode(json) }
    }

    @Test func aNewerVersionIsRefused() {
        #expect(throws: ThemeFileError.newerVersion(2)) { try decode(#"{ "version": 2, "colors": {} }"#) }
        #expect(ThemeFileError.newerVersion(2).message
            == "It was made by a newer MetalCreator (theme version 2); this one reads version 1.")
        #expect(ThemeFileError.damaged.message == "It isn’t a MetalCreator theme, or it is damaged.")
    }

    @Test func aMissingNameIsTheFallbackAndAMissingDarkFollowsThePanelBase() throws {
        #expect(try decode(#"{ "version": 1, "colors": {} }"#, fallbackName: "Ocean").name == "Ocean")
        #expect(try decode(#"{ "version": 1, "name": "  ", "colors": {} }"#, fallbackName: "Ocean").name == "Ocean")
        #expect(try decode(#"{ "version": 1, "name": " Sea ", "colors": {} }"#).name == "Sea")
        #expect(try decode(#"{ "version": 1, "colors": {} }"#).isDark, "Dracula's panel base is dark")
        #expect(try !decode(##"{ "version": 1, "colors": { "panelBase": "#fffbeb" } }"##).isDark)
        #expect(try !decode(#"{ "version": 1, "dark": false, "colors": {} }"#).isDark, "a stated `dark` wins")
    }
}
