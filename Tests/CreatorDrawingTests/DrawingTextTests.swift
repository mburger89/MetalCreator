import Testing

@testable import CreatorDrawing

@Suite("Drawing text")
struct DrawingTextTests {
    @Test func widthIsTheSumOfAdvances() {
        let run = DrawingText.layout("H1", height: 3.5)
        #expect(abs(run.width - (722.0 + 556) / 1000 * 3.5 / 0.718) < 1e-12)
        #expect(!run.hasReplacements && run.shown == "H1")
    }

    @Test func offsetsAccumulate() {
        let run = DrawingText.layout("HiA", height: 3.5)
        let unit = 3.5 / 0.718 / 1000
        #expect(run.offsets.count == 3)
        #expect(run.offsets[0] == 0)
        #expect(abs(run.offsets[1] - 722 * unit) < 1e-12)
        #expect(abs(run.offsets[2] - (722 + 222) * unit) < 1e-12)
    }

    @Test func aCharacterOutsideWinAnsiLaysOutAsAQuestionMark() {
        let run = DrawingText.layout("Ω-Bracket →", height: 3.5)
        #expect(run.shown == "?-Bracket ?")
        #expect(run.hasReplacements)
        let reference = DrawingText.layout("?-Bracket ?", height: 3.5)
        #expect(abs(run.width - reference.width) < 1e-12)
        #expect(run.bytes == reference.bytes)
    }

    @Test func fittingShrinksThenCuts() {
        let title = String(repeating: "Bracket ", count: 7) + "assy"  // 60 characters
        #expect(title.count == 60)
        let shrunk = DrawingText.fitted(title, height: 7, width: 107)
        #expect(shrunk.height < 7 && shrunk.height >= 1.8)
        #expect(shrunk.run.width <= 107 + 1e-9)
        let long = String(repeating: "Bracket ", count: 50)
        let cut = DrawingText.fitted(long, height: 7, width: 107)
        #expect(cut.height == 1.8)
        #expect(cut.run.shown.hasSuffix("…"))
        #expect(cut.run.width <= 107 + 1e-9)
        let short = DrawingText.fitted("Plate", height: 7, width: 107)
        #expect(short.height == 7 && short.run.shown == "Plate")
    }
}
