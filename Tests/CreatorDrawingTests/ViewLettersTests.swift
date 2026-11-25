import CreatorGeometry
import CreatorKernel
import Foundation
import Testing

@testable import CreatorDrawing

struct ViewLettersTests {
    private func derived(_ letter: String?, id: ViewID = ViewID()) -> DrawingView {
        let parent = ViewID()
        return DrawingView(
            id: id, kind: .detail, source: NodeID(), orientation: .standard(.front), center: .zero,
            derivation: .detail(DetailCircle(parent: parent, center: .zero, radius: 1)), letter: letter)
    }

    @Test func skipsIOQ() {
        let letters = (0..<23).map(ViewLetters.letter(at:))
        #expect(letters.joined() == "ABCDEFGHJKLMNPRSTUVWXYZ")
        #expect(ViewLetters.letter(at: 7) == "H")
        #expect(ViewLetters.letter(at: 8) == "J")
        #expect(ViewLetters.letter(at: 22) == "Z")
    }

    @Test func doubleLettersFollowZ() {
        #expect(ViewLetters.letter(at: 23) == "AA")
        #expect(ViewLetters.letter(at: 24) == "AB")
        #expect(ViewLetters.letter(at: 23 + 23) == "BA")
    }

    @Test func nextIsTheFirstFree() {
        let sheet = DrawingSheet(name: "S", views: [derived("A"), derived("C")])
        #expect(ViewLetters.next(on: sheet) == "B")
    }

    @Test func lettersRepairOnDecode() throws {
        let low = ViewID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000001") ?? UUID())
        let high = ViewID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000002") ?? UUID())
        let none = ViewID(rawValue: UUID(uuidString: "00000000-0000-4000-8000-000000000003") ?? UUID())
        let sheet = DrawingSheet(name: "S", views: [derived("A", id: high), derived("A", id: low), derived(nil, id: none)])
        let back = try JSONDecoder().decode(DrawingSheet.self, from: JSONEncoder().encode(sheet))
        #expect(back.view(low)?.letter == "A")
        #expect(back.view(high)?.letter == "B")
        #expect(back.view(none)?.letter == "C")
    }
}
