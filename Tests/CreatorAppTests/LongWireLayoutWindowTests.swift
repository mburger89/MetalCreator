import CreatorEditor
import CreatorGeometry
import CreatorGraph
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// A wire that runs far off the panel's bottom (left dock) must not make the panel, or the viewport beside it, taller
/// than the window.
@MainActor
struct LongWireLayoutWindowTests {
    func longWire() -> Graph {
        var builder = GraphBuilder()
        let box = builder.box(at: Vector2(600, 0))
        var output = box.output
        output.position = Vector2(2500, 0)
        builder.replace(output)
        return builder.graph
    }

    @Test func aLongWireLeavesThePanelAndTheViewportInsideTheWindow() async throws {
        let app = try await AppWindow.open(longWire(), dock: .left)
        let placement = try #require(app.model.panelPlacement)
        #expect(placement.panel.origin.y + placement.panel.size.y <= placement.window.y + 0.5,
                "panel bottom \(placement.panel.origin.y + placement.panel.size.y) in a window \(placement.window.y) high")
        let height = Float(app.size.y)
        // The viewport's status line ("mm · grid 1 mm") sits at its bottom; text a clip hides has no visible height.
        let outside = try app.window.elements { $0.role == .staticText && $0.visibleFrame.size.height.value > 0
            && $0.frame.origin.y.value + $0.frame.size.height.value > height + 0.5 }
        let status = try #require(try app.window.elements { $0.value?.hasPrefix("mm · grid") == true }.first)
        #expect(status.frame.origin.y.value + status.frame.size.height.value <= height, "the status line is inside the window")
        #expect(outside.isEmpty, "text below the window: \(outside.compactMap(\.value))")
    }
}
