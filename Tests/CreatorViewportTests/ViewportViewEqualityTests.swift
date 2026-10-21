#if canImport(Metal)
import CreatorKernel
import Testing
@testable import CreatorViewport

/// `ViewportView.==` compares the model by identity, as the panels do (`PanelEqualityTests`).
@MainActor
struct ViewportViewEqualityTests {
    @Test func aViewportViewIsEqualOnlyForTheSameModel() {
        let model = ViewportModel(kernel: FakeKernel())
        let other = ViewportModel(kernel: FakeKernel())
        #expect(ViewportView(model: model) == ViewportView(model: model))
        #expect(ViewportView(model: model) != ViewportView(model: other))
    }
}
#endif
