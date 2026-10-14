import CreatorGeometry
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The window is dragged by its top bar (spec §6.1, gap M6-c, MetalUI C22): a press-drag on the bar's empty space, or on
/// the strip above it, asks the platform window to move (`performWindowDrag`, counted by the headless window); a press
/// on a control never does, and the viewport beneath is as it was. Whether AppKit really moves the window is human
/// check AS-5.
@MainActor
struct WindowDragWindowTests {
    /// The gap between the name and the Preview picker, in the bar's middle.
    var gap: Point<Pixels> { Point(x: Pixels(600), y: Pixels(34)) }
    /// The margin above the bar, across the window.
    var strip: Point<Pixels> { Point(x: Pixels(600), y: Pixels(5)) }
    /// Above the graph panel with the default (bottom) dock: the viewport.
    var viewportSpot: Point<Pixels> { Point(x: Pixels(700), y: Pixels(300)) }

    @Test func aPressDragOnTheBarsEmptySpaceAsksThePlatformToMoveTheWindow() async throws {
        let app = try await AppWindow.open()
        #expect(app.windowDragRequests(draggingFrom: gap) == 1)
        #expect(app.windowDragRequests(draggingFrom: app.point(30, 34)) == 1, "and on the document's name")
    }

    @Test func aPressDragOnTheStripAboveTheBarAsksToo() async throws {
        let app = try await AppWindow.open()
        #expect(app.windowDragRequests(draggingFrom: strip) == 1)
        #expect(app.windowDragRequests(draggingFrom: app.point(600, Float(AppLayout.margin) + 3)) == 1, "over the glass's padding")
        let lastRow = Float(AppLayout.windowDragStripHeight) - 1
        #expect(app.windowDragRequests(draggingFrom: app.point(600, lastRow)) == 1, "down to where the controls start")
    }

    @Test func aPressDragOnABarControlNeverAsks() async throws {
        let app = try await AppWindow.open()
        let controls = try app.topBarControls()
        #expect(controls.count == 4, "Preview, Undo, Redo and Export")
        for control in controls {
            #expect(app.windowDragRequests(draggingFrom: app.centre(of: control)) == 0, "\(control.label ?? "a control")")
        }
    }

    #if canImport(Metal)
    @Test func thePaddingBelowTheControlsIsNotAHandle() async throws {
        // By design (User decision 1): handles sit beside the controls, so the 10-point glass padding under them is not a
        // handle either. A press-drag there reaches the viewport beneath, as it always did.
        let app = try await AppWindow.open()
        let pose = app.model.viewport.pose
        let below = app.point(600, Float(AppLayout.margin + AppLayout.topBarHeight) - 4)
        #expect(app.windowDragRequests(draggingFrom: below) == 0)
        #expect(app.model.viewport.pose != pose)
    }
    #endif

    @Test func aClickOnAControlStillClicks() async throws {
        let app = try await AppWindow.open()
        try app.window.click(try app.window.element(label: "Export"))
        #expect(app.window.platformWindow.presentedMenus.count == 1, "the Export menu opened")
        #expect(app.window.windowDrags == 0)
    }

    @Test func everyControlStartsBelowTheStrip() async throws {
        // A press on a control's top edge must not land in the strip, or it would drag the window.
        let app = try await AppWindow.open()
        let tops = try app.topBarControls().map(\.frame.origin.y.value)
        #expect(try #require(tops.min()) >= Float(AppLayout.windowDragStripHeight))
    }

    #if canImport(Metal)
    @Test func aDragBelowTheBarStillOrbitsTheViewportAndDoesNotAsk() async throws {
        let app = try await AppWindow.open()
        let pose = app.model.viewport.pose
        #expect(app.windowDragRequests(draggingFrom: viewportSpot) == 0)
        #expect(app.model.viewport.pose != pose, "the viewport's drag still moves the camera")
    }
    #endif

    @Test func aDragStartedInTheBarLeavesTheViewportAlone() async throws {
        let app = try await AppWindow.open()
        let pose = app.model.viewport.pose
        for start in [gap, strip] {
            #expect(app.windowDragRequests(draggingFrom: start) == 1)
        }
        #expect(app.model.viewport.pose == pose, "the camera did not move")
        #expect(!app.model.viewport.isPointerDown && app.model.viewport.activeDragMode == nil)
    }

    #if canImport(Metal)
    @Test func aClickInTheBandDoesNotReachTheViewportAndOneBelowDoes() async throws {
        let app = try await AppWindow.open()
        let tool = ModifierProbeTool()
        app.model.viewport.tool = tool
        app.window.click(at: gap)
        app.window.click(at: strip)
        #expect(tool.clicks.isEmpty, "the handle holds the press in the band")
        app.window.click(at: viewportSpot)
        #expect(tool.clicks.count == 1)
        #expect(app.window.windowDrags == 0, "a click is not a drag")
    }
    #endif

    @Test func aSecondaryPressOrADoubleClickDoesNotMoveOrZoomTheWindow() async throws {
        let app = try await AppWindow.open()
        app.window.rightClick(at: gap)
        app.window.doubleClick(at: gap)
        app.window.doubleClick(at: strip)
        #expect(app.window.windowDrags == 0)
        #expect(app.window.platformWindow.titleBarPresses.isEmpty, "the platform is not asked to zoom either")
    }

    @Test func theHiddenTitleBarStyleIsAppliedToTheWindow() async throws {
        let app = try await AppWindow.open()
        #expect(AppLayout.windowStyle == .hiddenTitleBar)
        #expect(app.window.platformWindow.titleBarStyles.last == .hidden)
    }

    /// SDL's answer (divergence 276): the platform declines to move the window, and the press is still held, so the
    /// viewport's drag does not start under the bar.
    @Test func whenThePlatformDeclinesThePressIsStillClaimed() async throws {
        let app = try await AppWindow.open(options: .init(performsWindowDrag: false))
        let pose = app.model.viewport.pose
        #expect(app.windowDragRequests(draggingFrom: gap) == 1)
        #expect(app.model.viewport.pose == pose)
    }
}
