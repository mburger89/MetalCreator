import Testing
@testable import CreatorDrawing

struct RevisionLettersTests {
    @Test func theTwentyLetters() {
        let expected = Array("ABCDEFGHJKLMNPRTUVWY").map(String.init)
        for index in 0..<20 { #expect(RevisionLetters.letter(at: index) == expected[index]) }
        for bad in ["I", "O", "Q", "S", "X", "Z"] { #expect(!RevisionLetters.isValid(bad)) }
        for good in expected { #expect(RevisionLetters.isValid(good)) }
        #expect(RevisionLetters.isValid("AA"))
        #expect(!RevisionLetters.isValid(""))
        #expect(!RevisionLetters.isValid("AI"))
    }

    @Test func afterYComesAA() {
        #expect(RevisionLetters.letter(at: 20) == "AA")
        #expect(RevisionLetters.letter(at: 21) == "AB")
        #expect(RevisionLetters.letter(at: 39) == "AY")
        #expect(RevisionLetters.letter(at: 40) == "BA")
    }

    @Test func nextFollowsTheLastValidRow() {
        func row(_ letter: String) -> RevisionRow { RevisionRow(letter: letter, description: "", date: "", approved: "") }
        #expect(RevisionLetters.next(after: []) == "A")
        #expect(RevisionLetters.next(after: [row("A"), row("B")]) == "C")
        #expect(RevisionLetters.next(after: [row("A"), row("Q")]) == "B")
        #expect(RevisionLetters.next(after: [row("H")]) == "J")
        #expect(RevisionLetters.next(after: [row("Y")]) == "AA")
    }
}
