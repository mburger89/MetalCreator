/// A theme's colours, one per role (spec §6.6, and the sketcher's roles from the constraint-sketcher spec §8).
/// Roles name what a colour is for, never its hue: Dracula's `selection` is pink, Nord's is purple. Every role is
/// a stored property, so a theme is total by construction: a built-in that left one out wouldn't compile. The
/// property names are the role names a `.mctheme` file will use (the Themes milestone after M6).
public struct ThemeColors: Hashable, Sendable {
    // Surfaces
    /// The window and viewport background gradient, top to bottom.
    public var backgroundTop: HexColor
    public var backgroundBottom: HexColor
    /// Glass panels' translucent fill, and the 1-pt hairline around them.
    public var glassFill: HexColor
    public var glassStroke: HexColor
    /// The panel base: status badges' capsules and socket rims.
    public var panelBase: HexColor
    /// Node bodies.
    public var nodeBody: HexColor
    /// Fields, tracks and dividers.
    public var field: HexColor

    // Text
    /// Primary text.
    public var foreground: HexColor
    /// Secondary, hint and comment text, and anything dimmed.
    public var comment: HexColor
    /// Text on an accent fill: node and inspector headers, primary buttons.
    public var textOnAccent: HexColor

    // Interaction
    /// Primary buttons and slider fill.
    public var accent: HexColor
    /// Hover and focus outside the graph: the view cube's hover and active face, keyboard focus, viewport hover,
    /// a wire being dragged, the box selection.
    public var focus: HexColor
    /// What a selection rule selects: picked and selected edges and faces, a rule's summary.
    public var selection: HexColor

    // Node categories: each header, its sockets and wires, and a selected node's outline and glow.
    public var valueHeader: HexColor
    public var profileHeader: HexColor
    /// Solid nodes, and in-view handles of solid nodes.
    public var solidHeader: HexColor
    /// Selection-rule nodes.
    public var selectionHeader: HexColor
    /// Feature nodes (Fillet, Chamfer), and in-view handles of feature nodes.
    public var featureHeader: HexColor
    public var outputHeader: HexColor

    // Status
    public var success: HexColor
    public var warning: HexColor
    public var error: HexColor

    // The model
    /// The part shading ramp, lit to unlit.
    public var shadeLight: HexColor
    public var shadeDark: HexColor
    /// B-rep edges drawn over the part.
    public var edge: HexColor
    /// The ground grid's minor and major lines.
    public var gridMinor: HexColor
    public var gridMajor: HexColor

    // Viewport widgets
    /// View cube face tiles, edge and corner tiles, and the face names painted on them.
    public var cubeFace: HexColor
    public var cubeRim: HexColor
    public var cubeLabel: HexColor
    /// The axis triad's X, Y and Z.
    public var axisX: HexColor
    public var axisY: HexColor
    public var axisZ: HexColor

    // The constraint sketcher (its spec §8; sub-project 6)
    public var sketchUnderConstrained: HexColor
    public var sketchFullyConstrained: HexColor
    public var sketchConflicting: HexColor
    /// Construction geometry, drawn dashed.
    public var sketchConstruction: HexColor
    /// Geometry projected from the model.
    public var sketchProjected: HexColor
}
