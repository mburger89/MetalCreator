/// One colour role (spec §6.6): its name, which is `ThemeColors`' property name and the key a `.mctheme` file uses,
/// its title in the theme editor and its group there. `ThemeColors[role]` reads and writes the role's colour, so
/// code that walks every role (the file format, the editor) never lists the properties again.
public struct ThemeRole: Identifiable, Hashable, Sendable {
    /// The `.mctheme` key, `ThemeColors`' property name: "selection".
    public let name: String
    /// The editor's label: "Selection".
    public let title: String
    public let group: ThemeRoleGroup
    /// Whether the editor offers an opacity: the glass and the edges are translucent by design, every other role
    /// is opaque.
    public let allowsOpacity: Bool
    let keyPath: WritableKeyPath<ThemeColors, HexColor> & Sendable

    public var id: String { name }

    init(_ name: String, _ title: String, _ group: ThemeRoleGroup,
         _ keyPath: WritableKeyPath<ThemeColors, HexColor> & Sendable, allowsOpacity: Bool = false) {
        self.name = name
        self.title = title
        self.group = group
        self.keyPath = keyPath
        self.allowsOpacity = allowsOpacity
    }

    /// The role a `.mctheme` file calls `name`, or `nil` for a name this version doesn't know.
    public static func named(_ name: String) -> ThemeRole? { byName[name] }

    private static let byName = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    public static func == (lhs: ThemeRole, rhs: ThemeRole) -> Bool { lhs.name == rhs.name }

    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
}
