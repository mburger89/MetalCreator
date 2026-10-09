import CreatorStyle
import Testing

/// The roles by name: the `.mctheme` keys and the theme editor's rows. They must be exactly `ThemeColors`' stored
/// properties, in order, each reading and writing its own colour.
struct ThemeRoleTests {
    /// `ThemeColors`' stored properties by label, in declaration order.
    static func properties(_ colors: ThemeColors) -> [(label: String, colour: HexColor)] {
        Mirror(reflecting: colors).children.compactMap { child in
            guard let label = child.label, let colour = child.value as? HexColor else { return nil }
            return (label, colour)
        }
    }

    @Test func theRolesAreThePropertiesOfThemeColorsInOrder() {
        #expect(Self.properties(ColorTheme.dracula.colors).map(\.label) == ThemeRole.all.map(\.name))
        #expect(ThemeRole.all.count == 38)
    }

    @Test(arguments: ThemeRole.all)
    func eachRoleReadsAndWritesItsOwnColour(_ role: ThemeRole) {
        var colors = ColorTheme.dracula.colors
        #expect(colors[role] == Self.properties(colors).first { $0.label == role.name }?.colour)
        colors[role] = HexColor(0x123456)
        for (label, colour) in Self.properties(colors) {
            let original = Self.properties(ColorTheme.dracula.colors).first { $0.label == label }?.colour
            #expect(colour == (label == role.name ? HexColor(0x123456) : original), "\(role.name) wrote \(label)")
        }
    }

    @Test func namesAndTitlesAreUniqueAndNamesFindTheirRole() {
        #expect(Set(ThemeRole.all.map(\.name)).count == ThemeRole.all.count)
        #expect(Set(ThemeRole.all.map(\.title)).count == ThemeRole.all.count)
        #expect(ThemeRole.named("selection")?.title == "Selection")
        #expect(ThemeRole.named("sparkle") == nil)
    }

    @Test func everyGroupHasRolesAndTheGroupsListEveryRoleInOrder() {
        #expect(ThemeRoleGroup.allCases.allSatisfy { !$0.roles.isEmpty })
        #expect(ThemeRoleGroup.allCases.flatMap(\.roles) == ThemeRole.all)
    }

    @Test func onlyTheGlassAndTheEdgesOfferOpacity() {
        #expect(ThemeRole.all.filter(\.allowsOpacity).map(\.name) == ["glassFill", "glassStroke", "edge"])
    }

    @Test func quantizingAThemeRoundsOnlyItsTranslucentRoles() {
        let quantized = ColorTheme.dracula.colors.quantized
        #expect(quantized.glassFill == HexColor(0x21222c, opacity: 219.0 / 255))
        #expect(quantized.edge == HexColor(0xf8f8f2, opacity: 230.0 / 255))
        #expect(quantized.selection == ColorTheme.dracula.colors.selection)
        #expect(quantized.quantized == quantized)
    }
}
