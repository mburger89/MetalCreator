import CreatorEditor
import CreatorGeometry
import CreatorGraph
import MetalUI
import Testing
@testable import CreatorApp

/// The top bar clears the window buttons under a hidden title bar (spec §6.1, gap M6-c). MetalUI sets the insets from
/// the real window, so the numbers are given here; where the buttons really sit is human check AS-5.
struct TitleBarClearanceTests {
    func insets(left: Float) -> Edges<Pixels> {
        Edges(top: Pixels(32), right: Pixels(0), bottom: Pixels(0), left: Pixels(left))
    }

    @Test func aStandardWindowNeedsNoClearance() {
        #expect(AppLayout.topBarClearance(titleBarInsets: Edges(all: Pixels(0))) == 0)
    }

    @Test func theContentStartsRightOfTheButtons() {
        // The buttons end at 69 pt; the glass starts at the margin and pads its content, so the content needs the rest.
        let clearance = AppLayout.topBarClearance(titleBarInsets: insets(left: 69))
        let contentStart = AppLayout.margin + GraphPanelLayout.glassPadding + clearance
        #expect(contentStart == 69 + AppLayout.titleBarGap)
        #expect(clearance > 0)
    }

    @Test func aToolbarUnderTheBarWidensTheInsetsAndNeverMakesNegativeClearance() {
        #expect(AppLayout.topBarClearance(titleBarInsets: insets(left: 79)) > AppLayout.topBarClearance(titleBarInsets: insets(left: 69)))
        #expect(AppLayout.topBarClearance(titleBarInsets: insets(left: 4)) == 0, "buttons narrower than the margin")
    }

    // MARK: The two platform shapes (MetalUI S1, gap XP-G3)

    /// macOS: the traffic lights at the left, AppKit's 32-point band.
    var macInsets: Edges<Pixels> { insets(left: 69) }
    /// SDL with MetalUI's drawn buttons: a 32-point band and a 138-point cluster at the right.
    var sdlInsets: Edges<Pixels> { Edges(top: Pixels(32), right: Pixels(138), bottom: Pixels(0), left: Pixels(0)) }

    @Test func macClearsTheLeftAndNeverTheRight() {
        let expected = 69 + AppLayout.titleBarGap - AppLayout.margin - GraphPanelLayout.glassPadding
        #expect(AppLayout.topBarClearance(titleBarInsets: macInsets) == expected)
        #expect(AppLayout.topBarTrailingClearance(titleBarInsets: macInsets) == 0)
        #expect(AppLayout.buttonCluster(titleBarInsets: macInsets, windowWidth: 1440)
                == CanvasRect(origin: Vector2(0, 0), size: Vector2(69, 32)))
    }

    @Test func sdlClearsTheRightAndNeverTheLeft() {
        #expect(AppLayout.topBarClearance(titleBarInsets: sdlInsets) == 0)
        let trailing = AppLayout.topBarTrailingClearance(titleBarInsets: sdlInsets)
        #expect(trailing > 0)
        // The glass ends `margin` in, pads its content, and the content then stops `gap` short of the buttons' left edge.
        #expect(1440 - AppLayout.margin - GraphPanelLayout.glassPadding - trailing == 1440 - 138 - AppLayout.titleBarGap)
        #expect(AppLayout.buttonCluster(titleBarInsets: sdlInsets, windowWidth: 1440)
                == CanvasRect(origin: Vector2(1302, 0), size: Vector2(138, 32)))
    }

    @Test func aStandardWindowReservesNoTrailingSpaceAndNoCluster() {
        let none = Edges(all: Pixels(0))
        #expect(AppLayout.topBarTrailingClearance(titleBarInsets: none) == 0)
        #expect(AppLayout.buttonCluster(titleBarInsets: none, windowWidth: 1440) == nil)
        #expect(AppLayout.topBarTrailingClearance(titleBarInsets: insets(left: 69)) == 0, "macOS has no right edge")
        let narrow = Edges(top: Pixels(32), right: Pixels(4), bottom: Pixels(0), left: Pixels(0))
        #expect(AppLayout.topBarTrailingClearance(titleBarInsets: narrow) == 0)
    }

    @Test func theBandNeverPushesTheBarDown() {
        // The bar stands at the margin, inside the band, on macOS today and on SDL: only the content's sides clear the
        // buttons, so what sits at the window's top edge does not move. Everything else starts below the bar.
        #expect(AppLayout.margin < 32 && AppLayout.margin + AppLayout.topBarHeight > 32)
        #expect(AppLayout.margin * 2 + AppLayout.topBarHeight >= 32, "panels, the theme dock and the pick banner start below the band")
    }
}
