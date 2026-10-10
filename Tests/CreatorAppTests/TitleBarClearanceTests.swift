import MetalUI
import Testing
@testable import CreatorApp

/// The top bar clears the window buttons under a hidden title bar (spec §6.1, gap M6-c). MetalUI sets the insets from
/// the real window, so the numbers are given here; where the buttons really sit is human check AS-4.
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
        let contentStart = AppLayout.margin + 10 + clearance
        #expect(contentStart == 69 + AppLayout.titleBarGap)
        #expect(clearance > 0)
    }

    @Test func aToolbarUnderTheBarWidensTheInsetsAndNeverMakesNegativeClearance() {
        #expect(AppLayout.topBarClearance(titleBarInsets: insets(left: 79)) > AppLayout.topBarClearance(titleBarInsets: insets(left: 69)))
        #expect(AppLayout.topBarClearance(titleBarInsets: insets(left: 4)) == 0, "buttons narrower than the margin")
    }
}
