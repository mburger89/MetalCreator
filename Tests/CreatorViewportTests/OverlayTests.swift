import CreatorGeometry
import CreatorKernel
import CreatorStyle
import Testing
@testable import CreatorViewport

/// The host's overlay (the sketch editor's geometry, sketcher spec §8): drawn over the scene in the theme's sketch
/// colours, construction dashed, a plane grid in place of the ground grid, and redrawn when it changes.
@MainActor
struct OverlayTests {
    let top = CameraPose(target: .zero, distance: 100, pitch: .pi / 2, projection: .orthographic)
    let size = ViewportSize(width: 400, height: 300)

    @Test func eachTintTakesItsThemeRole() {
        let theme = ColorTheme.dracula
        let palette = ViewportPalette(theme)
        #expect(palette.color(.underConstrained) == theme.colors.sketchUnderConstrained.rgba)
        #expect(palette.color(.fullyConstrained) == theme.colors.sketchFullyConstrained.rgba)
        #expect(palette.color(.conflicting) == theme.colors.sketchConflicting.rgba)
        #expect(palette.color(.construction) == theme.colors.sketchConstruction.rgba)
        #expect(palette.color(.projected) == theme.colors.sketchProjected.rgba)
        #expect(palette.color(.selected) == theme.colors.profileHeader.rgba, "the Sketch node's header colour")
        #expect(palette.color(.hovered) == theme.colors.focus.rgba)
        #expect(palette.color(.preview).w < 1, "the rubber band is faded")
    }

    @Test func linesAndPointsBecomeInstancesInPointWidthsTimesTheScale() {
        let overlay = ViewportOverlay(lines: [OverlayLine(.zero, Vector3(10, 0, 0), tint: .conflicting, width: 2)],
                                      points: [OverlayPoint(Vector3(10, 0, 0), tint: .fullyConstrained, size: 6)])
        let instances = OverlayGeometry.instances(overlay, pose: top, size: size, gridSpacing: 10, scale: 2, palette: .dracula)
        #expect(instances.count == 2)
        #expect(instances[0].width == 4 && instances[0].color == ViewportPalette.dracula.sketchConflicting)
        #expect(instances[1].a == instances[1].b && instances[1].width == 12, "a point is a square knob")
    }

    @Test func dashedLinesAreCutIntoDashesAtTheCurrentZoom() {
        let pieces = OverlayGeometry.dashes(.zero, Vector3(25, 0, 0), millimetresPerPoint: 1)
        #expect(pieces.count == 3, "dashes start every 10 points: at 0, 10 and 20")
        #expect(pieces[0].1 == Vector3(6, 0, 0))
        #expect(pieces[2].0 == Vector3(20, 0, 0) && pieces[2].1 == Vector3(25, 0, 0), "the last dash stops at the end")
        #expect(OverlayGeometry.dashes(.zero, Vector3(1e6, 0, 0), millimetresPerPoint: 1e-3).count == 1,
                "a dash pattern far finer than the line is drawn solid")
    }

    @Test func thePlaneGridLiesOnThePlaneWithEveryTenthLineMajor() throws {
        let plane = Plane(origin: Vector3(0, 0, 5), normal: .unitZ, xAxis: .unitX)
        let lines = OverlayGeometry.gridLines(on: plane, pose: top, size: size, spacing: 1)
        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy { $0.a.z == 5 && $0.b.z == 5 }, "on the plane, not the ground")
        let throughOrigin = try #require(lines.first { $0.a.x == 0 && $0.b.x == 0 })
        #expect(throughOrigin.major)
        #expect(lines.first { $0.a.x == 1 && $0.b.x == 1 }?.major == false)
    }

    @Test func showingAnOverlayRedrawsAndReachesTheFrame() {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: top, clock: ManualClock())
        model.viewSize = size
        let before = model.renderKey
        let overlay = ViewportOverlay(lines: [OverlayLine(.zero, .unitX, tint: .underConstrained)], gridPlane: .xy)
        model.showOverlay(overlay)
        #expect(model.renderKey != before)
        #expect(model.frame(at: 0).overlay == overlay)
        let key = model.renderKey
        model.showOverlay(overlay)
        #expect(model.renderKey == key, "an equal overlay changes nothing")
    }
}
