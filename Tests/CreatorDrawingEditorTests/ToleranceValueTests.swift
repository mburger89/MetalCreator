import MetalUI
import MetalUITesting
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// A tolerance's two values are typed separately (R10).
@MainActor
@Suite("Tolerance values")
struct ToleranceValueTests {
    private typealias Scene = SelectionScene

    @Test func theOtherToleranceValueIsNeverReRounded() {
        let s = Scene.make([.horizontal])
        let m = s.h.model
        m.setTolerance(.deviation(upper: 0.123456, lower: -0.987654), of: Scene.horizontal)
        m.setToleranceUpper(text: "0.2", of: Scene.horizontal)
        #expect(s.dimension(Scene.horizontal)?.tolerance == .deviation(upper: 0.2, lower: -0.987654))
        m.setToleranceLower(text: "-0.3", of: Scene.horizontal)
        #expect(s.dimension(Scene.horizontal)?.tolerance == .deviation(upper: 0.2, lower: -0.3))
        m.setTolerance(.limits(upper: 0.123456, lower: -0.987654), of: Scene.horizontal)
        m.setToleranceLower(text: "-1", limits: true, of: Scene.horizontal)
        #expect(s.dimension(Scene.horizontal)?.tolerance == .limits(upper: 0.123456, lower: -1))
    }

    /// Typing into the inspector's rendered Upper field commits through the code the field calls, leaving Lower as stored.
    @Test func theRenderedUpperFieldKeepsTheLowerValue() async throws {
        let s = Scene.make([.horizontal])
        s.h.model.setTolerance(.deviation(upper: 0.123456, lower: -0.987654), of: Scene.horizontal)
        s.h.model.selectedAnnotations = [Scene.horizontal]
        let window = try await DrawingWindow.open(size: Size(width: Pixels(400), height: Pixels(900)), scaleFactor: 1) {
            DrawingInspector(model: s.h.model)
        }
        let upper = try #require(try window.window.elements(role: .textField).first { $0.value == "0.1235" })
        window.window.click(at: Point(x: upper.frame.origin.x + 4, y: upper.frame.origin.y + 4))
        try await window.window.runUntilIdle()
        window.window.typeText("5")
        window.window.typeKey(.return)
        try await window.window.runUntilIdle()
        guard case .deviation(let newUpper, let lower)? = s.dimension(Scene.horizontal)?.tolerance else {
            Issue.record("not a deviation")
            return
        }
        #expect(newUpper != 0.123456, "the typed value was committed")
        #expect(lower == -0.987654, "Lower keeps full precision")
    }
}
