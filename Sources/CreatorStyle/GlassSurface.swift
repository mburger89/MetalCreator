/// A kind of floating glass surface, so the thickness of each is chosen in one place (`GlassSurface.thickness`)
/// and no view names a material. The persistent panels are the thinnest material, so the most of the theme's own
/// colour shows; the palette, which floats over the graph panel's glass and its busy canvas, is one step thicker.
public enum GlassSurface: String, CaseIterable, Sendable {
    /// The graph panel (spec §6.2) and the sketch editor's lists.
    case graphPanel
    /// The context inspector (spec §6.4) and the sketch inspector.
    case inspector
    /// The top bar, and the sketch toolbar that replaces its contents.
    case topBar
    /// The "Pick edges in view" banner.
    case pickBanner
    /// The hidden graph panel's "Show graph" button.
    case showButton
    /// The add-node palette.
    case palette
    /// The theme editor's panel.
    case themeEditor
    /// The sketch editor's small readout and inference chips.
    case chip
    /// The field preview's legend (fields spec §6): a small persistent card at the viewport's lower left.
    case fieldLegend
    /// The section panel (section spec §5): a small persistent card at the viewport's upper right while a section is on.
    case sectionPanel
    /// The Measure panel (measure spec): a small persistent card under the section panel while Measure runs.
    case measurePanel
    /// The export sheet (implicit spec §5.3): a card with a progress bar and Cancel over the viewport.
    case exportSheet

    /// The material this surface is built on.
    public var thickness: GlassThickness {
        switch self {
        case .palette, .exportSheet: .thin
        case .graphPanel, .inspector, .topBar, .pickBanner, .showButton, .themeEditor, .chip, .fieldLegend, .sectionPanel,
             .measurePanel: .ultraThin
        }
    }
}
