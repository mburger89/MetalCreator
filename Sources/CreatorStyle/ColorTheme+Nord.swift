extension ColorTheme {
    /// Nord (nordtheme.com), a dark theme in its published colours: Polar Night `#2e3440` `#3b4252` `#434c5e`
    /// `#4c566a` for surfaces, Snow Storm `#d8dee9` `#eceff4` for text and the lit shade, Frost `#88c0d0` `#81a1c1`
    /// `#5e81ac` and Aurora `#bf616a` `#d08770` `#ebcb8b` `#a3be8c` `#b48ead` for accents. Comment text is Frost
    /// `#81a1c1`, because Nord's comment grey `#4c566a` is too dark to read on its panels; Nord has no pink, so
    /// `selection` is its purple.
    public static let nord = ColorTheme(id: "nord", name: "Nord", isDark: true, colors: ThemeColors(
        backgroundTop: HexColor(0x434c5e), backgroundBottom: HexColor(0x2e3440),
        glassFill: HexColor(0x2e3440, opacity: 0.86), glassStroke: HexColor(0xeceff4, opacity: Double(0x1f) / 255),
        panelBase: HexColor(0x2e3440), nodeBody: HexColor(0x3b4252), field: HexColor(0x434c5e),
        foreground: HexColor(0xeceff4), comment: HexColor(0x81a1c1), textOnAccent: HexColor(0x2e3440),
        accent: HexColor(0x5e81ac), focus: HexColor(0x88c0d0), selection: HexColor(0xb48ead),
        valueHeader: HexColor(0x81a1c1), profileHeader: HexColor(0xa3be8c), solidHeader: HexColor(0x5e81ac),
        selectionHeader: HexColor(0xb48ead), featureHeader: HexColor(0xd08770), outputHeader: HexColor(0x88c0d0),
        success: HexColor(0xa3be8c), warning: HexColor(0xebcb8b), error: HexColor(0xbf616a),
        shadeLight: HexColor(0xd8dee9), shadeDark: HexColor(0x4c566a), edge: HexColor(0xeceff4, opacity: 0.9),
        gridMinor: HexColor(0x3b4252), gridMajor: HexColor(0x4c566a),
        cubeFace: HexColor(0x434c5e), cubeRim: HexColor(0x3b4252), cubeLabel: HexColor(0xeceff4),
        axisX: HexColor(0xbf616a), axisY: HexColor(0xa3be8c), axisZ: HexColor(0x88c0d0),
        sketchUnderConstrained: HexColor(0x88c0d0), sketchFullyConstrained: HexColor(0xeceff4),
        sketchConflicting: HexColor(0xbf616a), sketchConstruction: HexColor(0x81a1c1),
        sketchProjected: HexColor(0x5e81ac)
    ))
}
