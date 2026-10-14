import CreatorGraph
import CreatorStyle

/// The editor's colour roles (spec §6.6) in one theme. Views make it from the `ThemeStore` in their environment
/// (`Palette(themes)`), so they draw the current theme and re-render when it changes; without a store (headless
/// tests, `GraphPanelPreview`) they draw Dracula. The colours themselves live only in the themes (CreatorStyle).
public struct Palette: Hashable, Sendable {
    public var theme: ColorTheme

    public init(_ theme: ColorTheme) {
        self.theme = theme
    }

    /// The palette of the theme `store` shows, or Dracula's without a store.
    @MainActor
    public init(_ store: ThemeStore?) {
        self.init(store?.current ?? .dracula)
    }

    /// The default theme's palette.
    public static let dracula = Palette(.dracula)

    private var colors: ThemeColors { theme.colors }

    // Surfaces
    public var backgroundTop: HexColor { colors.backgroundTop }
    public var backgroundBottom: HexColor { colors.backgroundBottom }
    /// Glass panels (`#21222c` at about 86% in Dracula): the tint laid over a blurring material (`GlassPanel`, `GlassStyle`).
    public var glass: HexColor { colors.glassFill }
    /// The 1-pt hairline around glass panels (`#ffffff1f` in Dracula).
    public var hairline: HexColor { colors.glassStroke }
    public var panelBase: HexColor { colors.panelBase }
    public var nodeBody: HexColor { colors.nodeBody }
    /// Fields, tracks and dividers.
    public var field: HexColor { colors.field }
    public var primaryText: HexColor { colors.foreground }
    public var secondaryText: HexColor { colors.comment }

    /// Text drawn on any accent fill (headers, primary buttons, badges): `#282a36` in Dracula.
    public var textOnAccent: HexColor { colors.textOnAccent }
    /// Primary buttons and slider fill.
    public var primaryButton: HexColor { colors.accent }
    /// Focus outside the graph (keyboard focus, viewport hover), the wire being dragged and the box selection.
    public var focus: HexColor { colors.focus }
    /// What a selection rule selects, and its summary in the inspector.
    public var selection: HexColor { colors.selection }

    public var statusOK: HexColor { colors.success }
    public var statusWarning: HexColor { colors.warning }
    public var statusError: HexColor { colors.error }

    /// A node's header colour, by category.
    public func header(for category: NodeCategory) -> HexColor {
        switch category {
        case .value: colors.valueHeader
        case .profile: colors.profileHeader
        case .solid: colors.solidHeader
        case .selection: colors.selectionHeader
        case .feature, .patterns: colors.featureHeader
        // Lists & Trees shares the Value colour: the theme files have no role of its own.
        case .lists: colors.valueHeader
        // Fields borrows the Feature colour until the theme gains a role of its own (7b-3 adds the preview ramp's three).
        case .fields: colors.featureHeader
        // Implicit solids and meshes have roles of their own (implicit spec §2.1, §2.2).
        case .implicit: colors.implicitHeader
        case .mesh: colors.meshHeader
        case .output: colors.outputHeader
        }
    }

    /// A selected node's outline (no glow): always its own header colour (spec §6.6).
    public func selection(for category: NodeCategory) -> HexColor { header(for: category) }

    /// A socket's colour, and the colour of wires leaving it, by type: its category's header colour.
    public func socket(_ type: SocketType) -> HexColor {
        switch type {
        case .profile: header(for: .profile)
        case .solid: header(for: .solid)
        case .edgeSet, .faceSet: header(for: .selection)
        case .number, .integer, .bool, .vector, .plane: header(for: .value)
        case .field: header(for: .fields)
        case .implicit: header(for: .implicit)
        case .mesh: header(for: .mesh)
        case .any: header(for: .lists)
        }
    }

    /// The colour for a node's status badge.
    public func status(_ state: NodeState) -> HexColor {
        switch state {
        case .ok: statusOK
        case .warning: statusWarning
        case .error: statusError
        case .idle, .evaluating: secondaryText
        }
    }
}
