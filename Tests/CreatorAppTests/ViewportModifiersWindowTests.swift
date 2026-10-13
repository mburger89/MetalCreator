import CreatorGeometry
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// Modifier keys over the viewport, through the app's real window (MetalUI C16, gaps GI-a and S5-a): a tap carries the
/// modifiers held at its press, and ⌘ held over a pointer that doesn't move reaches the tool, which is how the sketch
/// editor's rubber band drops its inference glyphs (sketcher spec §8) with no mouse move.
@MainActor
struct ViewportModifiersWindowTests {
    /// Above the graph panel with the default (bottom) dock: the viewport.
    let spot = Point(x: Pixels(700), y: Pixels(300))
    var screenSpot: ScreenPoint { ScreenPoint(700, 300) }

    func open() async throws -> (app: AppWindow, tool: ModifierProbeTool) {
        let app = try await AppWindow.open()
        let tool = ModifierProbeTool()
        app.model.viewport.tool = tool
        return (app, tool)
    }

    @Test func commandPressedOverAStillPointerReachesTheToolAndReleasingItDoesToo() async throws {
        let (app, tool) = try await open()
        app.window.hover(at: spot)
        let hovers = tool.hovers.count
        app.window.pressModifiers(.command)
        #expect(tool.hovers.count == hovers + 1, "one replay, with the pointer not moved")
        #expect(tool.hovers.last == .init(point: screenSpot, modifiers: .command))
        app.window.pressModifiers([])
        #expect(tool.hovers.last == .init(point: screenSpot, modifiers: []))
    }

    @Test func aMoveWhileCommandIsHeldCarriesIt() async throws {
        let (app, tool) = try await open()
        app.window.pressModifiers(.command)
        app.window.hover(at: spot)
        #expect(tool.hovers.last == .init(point: screenSpot, modifiers: .command))
    }

    /// Only ⌘ is watched: other modifiers neither reach the tool nor wake the window.
    @Test func shiftAndOptionAreNotWatched() async throws {
        let (app, tool) = try await open()
        app.window.hover(at: spot)
        let hovers = tool.hovers.count
        app.window.pressModifiers([.shift, .option])
        #expect(tool.hovers.count == hovers)
        #expect(app.model.viewport.heldModifiers == [])
    }

    /// Review Focus 2: the window losing key status releases every key (MetalUI reports it as a change), so a ⌘ held while
    /// switching away doesn't leave the rubber band suppressed.
    @Test func losingKeyReleasesCommandAtTheTool() async throws {
        let (app, tool) = try await open()
        app.window.hover(at: spot)
        app.window.pressModifiers(.command)
        #expect(tool.hovers.last?.modifiers == .command)
        app.window.setControlActiveState(.inactive)
        #expect(tool.hovers.last == .init(point: screenSpot, modifiers: []))
    }

    @Test func aCommandClickReachesTheToolWithCommandAndAPlainOneWithout() async throws {
        let (app, tool) = try await open()
        app.window.click(at: spot, modifierFlags: .command)
        app.window.click(at: spot)
        #expect(tool.clicks == [.command, []])
    }

    @Test func aShiftClickCarriesShift() async throws {
        let (app, tool) = try await open()
        app.window.click(at: spot, modifierFlags: .shift)
        #expect(tool.clicks == [.shift])
    }
}
