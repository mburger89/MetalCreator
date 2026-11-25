import CreatorGeometry
import Testing

@testable import CreatorDrawing

@Suite("Replaced texts")
struct ReplacedTextsTests {
    private func text(_ original: String) -> SheetText {
        SheetText(run: DrawingText.layout(original, height: 3.5), original: original, origin: .zero, height: 3.5)
    }

    @Test func eachOriginalOnce() {
        let texts = [text("Ω-Bracket"), text("Plain"), text("→ arrow"), text("Ω-Bracket")]
        #expect(ReplacedTexts.collect(texts) == ["Ω-Bracket", "→ arrow"])
        #expect(ReplacedTexts.collect([text("Plain")]).isEmpty)
    }
}
