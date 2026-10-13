import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// Where the legend stands (fields spec §6): above the axis triad, clear of the docked graph panel.
@MainActor
struct FieldLegendLayoutTests {
    let aboveTheTriad = 16 + TriadLayout().side + 12

    @Test func leftDockedItStandsRightOfThePanelAboveTheTriad() {
        let area = AppLayout.modelArea(dock: .left, panelWidth: 460, panelHeight: 300)
        let insets = AppLayout.legendInsets(dock: .left, panelWidth: 460, panelHeight: 300)
        #expect(insets.leading == area.leading + 16 && insets.bottom == area.bottom + aboveTheTriad)
        #expect(insets.top == 0 && insets.trailing == 0)
    }

    @Test func bottomDockedItStandsAboveThePanel() {
        let area = AppLayout.modelArea(dock: .bottom, panelWidth: 460, panelHeight: 300)
        let insets = AppLayout.legendInsets(dock: .bottom, panelWidth: 460, panelHeight: 300)
        #expect(insets.leading == 16 && insets.bottom == area.bottom + aboveTheTriad)
        #expect(insets.bottom > 300 + aboveTheTriad)
    }

    @Test func withThePanelHiddenItClearsTheShowButton() {
        let area = AppLayout.modelArea(dock: .hidden, panelWidth: 460, panelHeight: 300)
        #expect(AppLayout.legendInsets(dock: .hidden, panelWidth: 460, panelHeight: 300).bottom == area.bottom + aboveTheTriad)
    }

    @Test func theTriadIsWhereTheLegendThinksItIs() async throws {
        let app = await makeApp()
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.viewport.setModelArea(AppLayout.modelArea(dock: .left, panelWidth: 460, panelHeight: 300))
        let triad = app.viewport.triadLayout
        let insets = AppLayout.legendInsets(dock: .left, panelWidth: 460, panelHeight: 300)
        #expect(triad.leading == insets.leading && triad.bottom + triad.side + 12 == insets.bottom)
    }
}
