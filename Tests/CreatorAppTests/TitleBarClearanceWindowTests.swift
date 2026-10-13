import CreatorEditor
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// Under the hidden title bar the window buttons sit over the top bar's left end (spec §6.1, gap M6-c); the app's own
/// window, given the platform's insets, starts the bar's content clear of them. `TitleBarClearanceTests` pins the numbers,
/// `TopBarClearanceRenderTests` the padding; these run the real root. Where the buttons really are is human check AS-5.
@MainActor
struct TitleBarClearanceWindowTests {
    /// Where the bar's first content starts in a standard window: the margin and the glass's padding.
    let flush = Float(AppLayout.margin + GraphPanelLayout.glassPadding)

    @Test func withNoInsetsTheBarStartsAtTheGlassPadding() async throws {
        let app = try await AppWindow.open()
        #expect(abs(try app.topBarLabel().frame.origin.x.value - flush) < 0.5)
    }

    @Test func theNameStartsClearOfTheWindowButtons() async throws {
        let app = try await AppWindow.open()
        app.setTitleBarInsets(AppWindow.standardButtonInsets)
        let start = try app.topBarLabel().frame.origin.x.value
        #expect(abs(start - Float(69 + AppLayout.titleBarGap)) < 0.5, "the buttons end at 69, the gap is 8: \(start)")
    }

    @Test func fullScreenMovesTheContentBackAndLeavingItClearsTheButtonsAgain() async throws {
        let app = try await AppWindow.open()
        app.setTitleBarInsets(AppWindow.standardButtonInsets)
        let cleared = try app.topBarLabel().frame.origin.x.value
        app.setTitleBarInsets(Edges(all: Pixels(0)))
        #expect(abs(try app.topBarLabel().frame.origin.x.value - flush) < 0.5, "full screen: the buttons left")
        app.setTitleBarInsets(AppWindow.standardButtonInsets)
        #expect(try app.topBarLabel().frame.origin.x.value == cleared)
    }

    @Test func aStandardTitleBarNeedsNoClearanceEvenWithInsetsReported() async throws {
        let app = try await AppWindow.open(windowStyle: .automatic)
        app.setTitleBarInsets(AppWindow.standardButtonInsets)
        #expect(abs(try app.topBarLabel().frame.origin.x.value - flush) < 0.5, "MetalUI zeroes the insets of a standard window")
    }

    @Test func theSketchToolbarClearsTheButtonsToo() async throws {
        var builder = GraphBuilder()
        let box = builder.sketchedBox(rectangleSketch())
        let app = try await AppWindow.open(builder.graph)
        app.setTitleBarInsets(AppWindow.standardButtonInsets)
        app.model.beginSketch(for: box.sketch.id)
        await app.model.settle()
        app.redraw()
        #expect(abs(try app.topBarLabel().frame.origin.x.value - Float(69 + AppLayout.titleBarGap)) < 0.5)
    }

    @Test func nothingOverlapsAtTheMinimumWindowWidth() async throws {
        let app = try await AppWindow.open()
        app.setTitleBarInsets(AppWindow.standardButtonInsets)
        app.window.resize(to: Size(width: Pixels(1000), height: Pixels(640)))
        let label = try app.topBarLabel()
        let controls = try app.topBarControls().sorted { $0.frame.origin.x.value < $1.frame.origin.x.value }
        #expect(controls.count == 4)
        var edge = label.frame.origin.x.value + label.frame.size.width.value
        for control in controls {
            #expect(control.frame.origin.x.value >= edge, "\(control.label ?? "a control") starts after what is left of it")
            edge = control.frame.origin.x.value + control.frame.size.width.value
        }
        #expect(edge <= 1000 - Float(AppLayout.margin), "and the last ends inside the window")
    }

    @Test func theStripStillMovesTheWindowOverTheButtonsBand() async throws {
        let app = try await AppWindow.open()
        app.setTitleBarInsets(AppWindow.standardButtonInsets)
        #expect(app.windowDragRequests(draggingFrom: app.point(30, 5)) == 1)
        #expect(app.windowDragRequests(draggingFrom: app.point(600, 34)) == 1)
    }
}
