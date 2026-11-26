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
}
