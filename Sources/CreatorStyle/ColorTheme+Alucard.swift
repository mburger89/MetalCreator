extension ColorTheme {
    /// Alucard, Dracula's official light variant (draculatheme.com/spec, "Alucard Classic"), role for role as
    /// Dracula: its background `#fffbeb` with the UI shades `#efeddc` (floating), `#dedccf` (light) and `#ceccc0`
    /// (dark), selection `#cfcfde`, foreground `#1f1f1f`, comment `#6c664b`, and its accents. Text on its darker
    /// accents is the background colour.
    public static let alucard = ColorTheme(id: "alucard", name: "Alucard", isDark: false, colors: ThemeColors(
        backgroundTop: HexColor(0xfffbeb), backgroundBottom: HexColor(0xceccc0),
        glassFill: HexColor(0xefeddc, opacity: 0.86), glassStroke: HexColor(0x1f1f1f, opacity: Double(0x1f) / 255),
        panelBase: HexColor(0xfffbeb), nodeBody: HexColor(0xefeddc), field: HexColor(0xcfcfde),
        foreground: HexColor(0x1f1f1f), comment: HexColor(0x6c664b), textOnAccent: HexColor(0xfffbeb),
        accent: HexColor(0x644ac9), focus: HexColor(0x036a96), selection: HexColor(0xa3144d),
        valueHeader: HexColor(0x6c664b), profileHeader: HexColor(0x14710a), solidHeader: HexColor(0x644ac9),
        selectionHeader: HexColor(0xa3144d), featureHeader: HexColor(0xa34d14), outputHeader: HexColor(0x036a96),
        success: HexColor(0x14710a), warning: HexColor(0x846e15), error: HexColor(0xcb3a2a),
        shadeLight: HexColor(0xcfcfde), shadeDark: HexColor(0x6c664b), edge: HexColor(0x1f1f1f, opacity: 0.9),
        gridMinor: HexColor(0xcfcfde), gridMajor: HexColor(0x6c664b),
        cubeFace: HexColor(0xcfcfde), cubeRim: HexColor(0xdedccf), cubeLabel: HexColor(0x1f1f1f),
        axisX: HexColor(0xcb3a2a), axisY: HexColor(0x14710a), axisZ: HexColor(0x036a96),
        sketchUnderConstrained: HexColor(0x036a96), sketchFullyConstrained: HexColor(0x1f1f1f),
        sketchConflicting: HexColor(0xcb3a2a), sketchConstruction: HexColor(0x6c664b),
        sketchProjected: HexColor(0x644ac9)
    ))
}
