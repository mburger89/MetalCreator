extension ColorTheme {
    /// Dracula (draculatheme.com), the default: spec §6.6's colours, and the sketcher's from its spec §8.
    public static let dracula = ColorTheme(id: "dracula", name: "Dracula", isDark: true, colors: ThemeColors(
        backgroundTop: HexColor(0x3a3d4e), backgroundBottom: HexColor(0x191a21),
        glassFill: HexColor(0x21222c, opacity: 0.86), glassStroke: HexColor(0xffffff, opacity: Double(0x1f) / 255),
        panelBase: HexColor(0x282a36), nodeBody: HexColor(0x343746), field: HexColor(0x44475a),
        foreground: HexColor(0xf8f8f2), comment: HexColor(0x6272a4), textOnAccent: HexColor(0x282a36),
        accent: HexColor(0xbd93f9), focus: HexColor(0x8be9fd), selection: HexColor(0xff79c6),
        valueHeader: HexColor(0x6272a4), profileHeader: HexColor(0x50fa7b), solidHeader: HexColor(0xbd93f9),
        selectionHeader: HexColor(0xff79c6), featureHeader: HexColor(0xffb86c), outputHeader: HexColor(0x8be9fd),
        success: HexColor(0x50fa7b), warning: HexColor(0xf1fa8c), error: HexColor(0xff5555),
        shadeLight: HexColor(0xc5c8de), shadeDark: HexColor(0x6f739a), edge: HexColor(0xf8f8f2, opacity: 0.9),
        gridMinor: HexColor(0x44475a), gridMajor: HexColor(0x6272a4),
        cubeFace: HexColor(0x282a36), cubeRim: HexColor(0x21222c), cubeLabel: HexColor(0xf8f8f2),
        axisX: HexColor(0xff5555), axisY: HexColor(0x50fa7b), axisZ: HexColor(0x8be9fd),
        sketchUnderConstrained: HexColor(0x8be9fd), sketchFullyConstrained: HexColor(0xf8f8f2),
        sketchConflicting: HexColor(0xff5555), sketchConstruction: HexColor(0x6272a4),
        sketchProjected: HexColor(0xbd93f9)
    ))
}
