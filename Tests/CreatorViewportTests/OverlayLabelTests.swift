import CreatorGeometry
import Foundation
import MetalUI
import Testing
@testable import CreatorViewport

/// Overlay labels (sketcher spec §8's dimension values): anchored in world space, projected every frame, nudged along a
/// world direction as it looks on screen, hidden while the camera animates, and drawn as text over the surface.
@MainActor
struct OverlayLabelTests {
    let top = CameraPose(target: .zero, distance: 100, pitch: .pi / 2, projection: .orthographic)
    let size = ViewportSize(width: 400, height: 300)

    func makeModel(_ labels: [OverlayLabel]) -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: top, clock: ManualClock())
        model.viewSize = size
        model.showOverlay(ViewportOverlay(labels: labels))
        return model
    }

    func centre(_ label: PlacedLabel) -> ScreenPoint {
        ScreenPoint(label.origin.x + label.size.width / 2, label.origin.y + label.size.height / 2)
    }

    @Test func aLabelIsCentredOnItsProjectedAnchor() throws {
        let model = makeModel([OverlayLabel("12.5 mm", at: .zero)])
        let placed = try #require(model.overlayLabels(measuring: .fake).first)
        #expect(placed.text == "12.5 mm")
        #expect(placed.size == PlacedLabel.box(of: "12.5 mm", measuring: .fake))
        #expect(abs(centre(placed).x - 200) < 1e-6 && abs(centre(placed).y - 150) < 1e-6, "the target is the view's centre")
    }

    @Test func theBoxIsTheMeasuredWidthPlusPaddingAtEachSide() {
        let box = PlacedLabel.box(of: "12.5 mm", measuring: .fake)
        #expect(box.width == 7 * 6 + 2 * PlacedLabel.padding, "the fake measure is 6 points a character")
        #expect(box.height == PlacedLabel.height)
        #expect(PlacedLabel.box(of: "", measuring: .fake).width == 2 * PlacedLabel.padding)
        let fractional = TextMeasure { _ in ViewportSize(width: 40.3, height: 12) }
        #expect(PlacedLabel.box(of: "x", measuring: fractional).width == 41 + 2 * PlacedLabel.padding,
                "rounded up: a laid-out frame is rounded, and the text must not wrap for want of a fraction")
    }

    /// The width comes from the measure, never from how many characters the text has.
    @Test func theBoxFollowsTheMeasureWhateverTheTextsLength() throws {
        let measure = TextMeasure { text in ViewportSize(width: text == "W" ? 90 : 3, height: 12) }
        let wide = try #require(makeModel([OverlayLabel("W", at: .zero)]).overlayLabels(measuring: measure).first)
        let narrow = try #require(makeModel([OverlayLabel("iiiiiiiiii", at: .zero)]).overlayLabels(measuring: measure).first)
        #expect(wide.size.width == 90 + 2 * PlacedLabel.padding)
        #expect(narrow.size.width == 3 + 2 * PlacedLabel.padding)
    }

    /// A box wholly outside the view is dropped by its measured extent: the same anchor, just left of the view, is in
    /// with a wide text and out with a narrow one.
    @Test func aWideTextReachingIntoTheViewIsKeptAndANarrowOneAtTheSameAnchorIsNot() throws {
        let probe = makeModel([])
        let origin = try #require(probe.projector.screenPoint(of: .zero))
        let tenUnits = try #require(probe.projector.screenPoint(of: Vector3(10, 0, 0)))
        let anchorX = (-50 - origin.x) / ((tenUnits.x - origin.x) / 10)
        let label = OverlayLabel("x", at: Vector3(anchorX, 0, 0))
        let wide = makeModel([label]).overlayLabels(measuring: TextMeasure { _ in ViewportSize(width: 200, height: 12) })
        let narrow = makeModel([label]).overlayLabels(measuring: TextMeasure { _ in ViewportSize(width: 20, height: 12) })
        #expect(wide.count == 1, "its box reaches into the view")
        #expect(narrow.isEmpty, "its box ends 34 points left of the view")
    }

    @Test func aNudgeMovesTheLabelSixteenPointsAlongTheDirectionAsItLooksOnScreen() throws {
        let anchor = try #require(makeModel([OverlayLabel("a", at: .zero)]).overlayLabels(measuring: .fake).first)
        let right = try #require(makeModel([OverlayLabel("a", at: .zero, nudge: .unitX)]).overlayLabels(measuring: .fake).first)
        let left = try #require(makeModel([OverlayLabel("a", at: .zero, nudge: -Vector3.unitX)]).overlayLabels(measuring: .fake).first)
        let (home, a, b) = (centre(anchor), centre(right), centre(left))
        #expect(abs(hypot(a.x - home.x, a.y - home.y) - OverlayLabel.nudgeDistance) < 1e-6)
        #expect(abs(a.x + b.x - 2 * home.x) < 1e-6 && abs(a.y + b.y - 2 * home.y) < 1e-6, "opposite nudges are opposite")
        let edgeOn = try #require(makeModel([OverlayLabel("a", at: .zero, nudge: .unitZ)]).overlayLabels(measuring: .fake).first)
        #expect(centre(edgeOn) == home, "a nudge along the line of sight has no direction on screen: no nudge")
    }

    @Test func labelsOutsideTheViewOrOfAnEmptyViewOrDuringAnAnimationAreLeftOut() {
        let model = makeModel([OverlayLabel("in", at: .zero), OverlayLabel("far", at: Vector3(1e6, 0, 0))])
        #expect(model.overlayLabels(measuring: .fake).map(\.text) == ["in"], "a box wholly outside the view is dropped")
        model.perform(.view(.front))
        #expect(model.isAnimating)
        #expect(model.overlayLabels(measuring: .fake).isEmpty, "labels can't follow a running animation (gap M4-b)")
        let blank = makeModel([OverlayLabel("in", at: .zero)])
        blank.viewSize = ViewportSize(width: 0, height: 0)
        #expect(blank.overlayLabels(measuring: .fake).isEmpty)
    }

    @Test func aLabelsTextTakesItsTintsRoleInTheTheme() {
        let model = makeModel([])
        let colors = model.theme.colors
        #expect(model.textColor(for: .conflicting) == colors.sketchConflicting.color)
        #expect(model.textColor(for: .fullyConstrained) == colors.sketchFullyConstrained.color)
        #expect(model.textColor(for: .construction) == colors.sketchConstruction.color)
        #expect(model.textColor(for: .selected) == colors.profileHeader.color)
    }

    @Test func labelsAreTheOverlaysToo() {
        let overlay = ViewportOverlay(labels: [OverlayLabel("a", at: .zero)])
        #expect(!overlay.isEmpty)
        let model = makeModel([])
        let before = model.renderKey
        model.showOverlay(overlay)
        #expect(model.renderKey != before)
    }

    #if canImport(Metal)
    @Test func theViewDrawsEachLabelsTextInsideItsBox() throws {
        let model = makeModel([OverlayLabel("12.5 mm", at: .zero)])
        let big = ViewportSize(width: 1400, height: 900)
        model.viewSize = big
        let placed = try #require(model.overlayLabels(measuring: .real()).first)
        let scene = renderFrame({ ZStack { ViewportView(model: model) } }, size: Size(width: Pixels(1400), height: Pixels(900)),
                                scaleFactor: 2, textSystem: testTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        let inside = scene.glyphs.filter { glyph in
            let x = Double(glyph.bounds.origin.x + glyph.bounds.size.width / 2) / 2
            let y = Double(glyph.bounds.origin.y + glyph.bounds.size.height / 2) / 2
            return x >= placed.origin.x && x <= placed.origin.x + placed.size.width
                && y >= placed.origin.y && y <= placed.origin.y + placed.size.height
        }
        #expect(inside.count == 6, "1 2 . 5 m m: the glyphs of the text, without its space")
    }
    #endif
}
