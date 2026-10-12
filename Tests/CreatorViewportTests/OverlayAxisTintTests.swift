import CreatorGeometry
import CreatorStyle
import Testing
@testable import CreatorViewport

/// The layout previews' triads (patterns spec §8) are drawn in the theme's axis colours, as the view cube's triad is.
struct OverlayAxisTintTests {
    @Test func theAxisTintsAreTheThemesAxisColours() {
        for theme in [ColorTheme.dracula, .alucard, .nord] {
            let palette = ViewportPalette(theme)
            #expect(palette.color(.axisX) == palette.axisX && palette.color(.axisY) == palette.axisY
                && palette.color(.axisZ) == palette.axisZ, "\(theme.name)")
        }
        #expect(ViewportPalette.dracula.color(.axisX) != ViewportPalette.dracula.color(.axisY))
    }

    @Test func aTriadsLinesBecomeInstancesInTheirAxisColours() {
        let palette = ViewportPalette.dracula
        let overlay = ViewportOverlay(lines: [
            OverlayLine(.zero, Vector3(5, 0, 0), tint: .axisX), OverlayLine(.zero, Vector3(0, 5, 0), tint: .axisY),
            OverlayLine(.zero, Vector3(0, 0, 5), tint: .axisZ),
        ])
        let instances = OverlayGeometry.instances(overlay, grid: nil, millimetresPerPoint: 1, scale: 1, palette: palette)
        #expect(instances.count == 3)
        #expect(instances.map(\.color) == [palette.axisX, palette.axisY, palette.axisZ])
    }

    @MainActor
    @Test func theTextColourOfAnAxisTintIsItsThemeRole() {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: CameraPose(target: .zero, distance: 100), clock: ManualClock())
        #expect(model.textColor(for: .axisX) == model.theme.colors.axisX.color)
    }
}
