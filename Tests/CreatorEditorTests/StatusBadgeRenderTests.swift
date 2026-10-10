import CreatorGraph
import MetalUI
import Testing
@testable import CreatorEditor

/// The status badge draws MetalUI's `ProgressView` while a node evaluates (gap M5-j), and text otherwise. A headless
/// frame is one still frame at time zero, so the spinner's twelve spokes are the same on every run; its spin is a
/// human check (M5-11).
@MainActor
struct StatusBadgeRenderTests {
    func badge(_ state: NodeState?) -> Scene {
        renderHeadless { StatusBadgeView(state: state) }
    }

    @Test func anEvaluatingBadgeDrawsTheSpinnerAndNoText() {
        let scene = badge(.evaluating)
        #expect(scene.glyphs.isEmpty)
        #expect(scene.images.count == 12, "MetalUI's spinner draws twelve spokes")
    }

    @Test func theSpinnerStillFrameIsTheSameEveryTime() {
        let first = badge(.evaluating), second = badge(.evaluating)
        #expect(first.images.count == second.images.count)
        #expect(first.rects.map(\.bounds.size.width) == second.rects.map(\.bounds.size.width))
        #expect(first.images.map(\.bounds.origin.x) == second.images.map(\.bounds.origin.x))
    }

    @Test(arguments: [NodeState.ok(duration: .milliseconds(12)), .warning("w"), .error("e")])
    func everyOtherStateDrawsTextAndNoSpinner(_ state: NodeState) {
        let scene = badge(state)
        #expect(!scene.glyphs.isEmpty)
        #expect(scene.images.isEmpty)
    }

    @Test(arguments: [nil, NodeState.idle(nil)])
    func aQuietBadgeDrawsNothingVisible(_ state: NodeState?) {
        let scene = badge(state)
        #expect(scene.glyphs.isEmpty)
        #expect(scene.images.isEmpty)
    }

    @Test func theSpinnerFitsTheNodeHeader() throws {
        let capsule = try #require(badge(.evaluating).rects.first)
        #expect(Double(capsule.bounds.size.height) / 2 <= NodeLayout.headerHeight)
    }
}
