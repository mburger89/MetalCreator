import CreatorGeometry
import Foundation
import MetalUI
import MetalUIText
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
        let placed = try #require(model.overlayLabels().first)
        #expect(placed.text == "12.5 mm")
        #expect(placed.size == PlacedLabel.size(of: "12.5 mm"))
        #expect(abs(centre(placed).x - 200) < 1e-6 && abs(centre(placed).y - 150) < 1e-6, "the target is the view's centre")
    }

    @Test func theBoxHoldsTheTextAtSevenPointsACharacter() {
        let box = PlacedLabel.size(of: "12.5 mm")
        #expect(box.width == 7 * 7 + 2 * PlacedLabel.padding)
        #expect(box.height == PlacedLabel.height)
        #expect(PlacedLabel.size(of: "").width == 2 * PlacedLabel.padding)
    }

    @Test func aNudgeMovesTheLabelSixteenPointsAlongTheDirectionAsItLooksOnScreen() throws {
        let anchor = try #require(makeModel([OverlayLabel("a", at: .zero)]).overlayLabels().first)
        let right = try #require(makeModel([OverlayLabel("a", at: .zero, nudge: .unitX)]).overlayLabels().first)
        let left = try #require(makeModel([OverlayLabel("a", at: .zero, nudge: -Vector3.unitX)]).overlayLabels().first)
        let (home, a, b) = (centre(anchor), centre(right), centre(left))
        #expect(abs(hypot(a.x - home.x, a.y - home.y) - OverlayLabel.nudgeDistance) < 1e-6)
        #expect(abs(a.x + b.x - 2 * home.x) < 1e-6 && abs(a.y + b.y - 2 * home.y) < 1e-6, "opposite nudges are opposite")
        let edgeOn = try #require(makeModel([OverlayLabel("a", at: .zero, nudge: .unitZ)]).overlayLabels().first)
        #expect(centre(edgeOn) == home, "a nudge along the line of sight has no direction on screen: no nudge")
    }

    @Test func labelsOutsideTheViewOrOfAnEmptyViewOrDuringAnAnimationAreLeftOut() {
        let model = makeModel([OverlayLabel("in", at: .zero), OverlayLabel("far", at: Vector3(1e6, 0, 0))])
        #expect(model.overlayLabels().map(\.text) == ["in"], "a box wholly outside the view is dropped")
        model.perform(.view(.front))
        #expect(model.isAnimating)
        #expect(model.overlayLabels().isEmpty, "labels can't follow a running animation (gap M4-b)")
        let blank = makeModel([OverlayLabel("in", at: .zero)])
        blank.viewSize = ViewportSize(width: 0, height: 0)
        #expect(blank.overlayLabels().isEmpty)
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

    @Test func theViewDrawsEachLabelsTextInsideItsBox() throws {
        let model = makeModel([OverlayLabel("12.5 mm", at: .zero)])
        let big = ViewportSize(width: 1400, height: 900)
        model.viewSize = big
        let placed = try #require(model.overlayLabels().first)
        let scene = renderFrame({ ZStack { ViewportView(model: model) } }, size: Size(width: Pixels(1400), height: Pixels(900)),
                                scaleFactor: 2, textSystem: CoreTextTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        let inside = scene.glyphs.filter { glyph in
            let x = Double(glyph.bounds.origin.x + glyph.bounds.size.width / 2) / 2
            let y = Double(glyph.bounds.origin.y + glyph.bounds.size.height / 2) / 2
            return x >= placed.origin.x && x <= placed.origin.x + placed.size.width
                && y >= placed.origin.y && y <= placed.origin.y + placed.size.height
        }
        #expect(inside.count == 6, "1 2 . 5 m m: the glyphs of the text, without its space")
    }
}
