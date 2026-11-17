import Foundation
import Testing
@testable import CreatorPCB

struct SExpressionReaderTests {
    private func read(_ text: String, limits: KiCadLimits = .standard, isCancelled: () -> Bool = { false }) throws -> SExpression {
        try SExpressionReader.read(Data(text.utf8), limits: limits, isCancelled: isCancelled)
    }

    private func message(_ text: String, limits: KiCadLimits = .standard) -> String? {
        do {
            _ = try read(text, limits: limits)
            return nil
        } catch let problem as KiCadProblem {
            return problem.message
        } catch {
            return "other"
        }
    }

    @Test func readsNestedLists() throws {
        let tree = try read("(a (b \"c d\") 1.5 -2)")
        #expect(tree == .list([.atom("a"), .list([.atom("b"), .string("c d")]), .atom("1.5"), .atom("-2")]))
    }

    @Test func decodesStringEscapes() throws {
        let tree = try read(#"(a "x\"y\\z\nw")"#)
        #expect(tree.text(at: 1) == "x\"y\\z\nw")
    }

    @Test func readsBarDelimitedData() throws {
        let tree = try read("(data |QUJD\nREVG|)")
        #expect(tree == .list([.atom("data"), .string("QUJD\nREVG")]))
    }

    @Test func refusesUnbalanced() {
        #expect(message("(a (b)") == "The board file is damaged: a list isn't closed.")
    }

    @Test func refusesExtraClose() {
        #expect(message("(a))") != nil)
        #expect(message(")") != nil)
    }

    @Test func refusesTooDeep() {
        let text = String(repeating: "(", count: 65) + String(repeating: ")", count: 65)
        #expect(message(text)?.contains("64") == true)
        let ok = String(repeating: "(", count: 64) + String(repeating: ")", count: 64)
        #expect(message(ok) == nil)
    }

    @Test func refusesHugeString() {
        let text = "(a \"" + String(repeating: "x", count: (1 << 20) + 1) + "\")"
        #expect(message(text)?.contains("1 MB") == true)
    }

    @Test func refusesEmptyAndBinary() {
        #expect(message("") == "This isn't a KiCad board file.")
        #expect(message("   \n") == "This isn't a KiCad board file.")
        #expect(message("atom") == "This isn't a KiCad board file.")
        #expect(message("\u{1}\u{2}\u{0}junk") == "This isn't a KiCad board file.")
    }

    @Test func cancels() {
        let text = "(a " + String(repeating: "1 ", count: 200_000) + ")"
        #expect(throws: CancellationError.self) { try read(text, isCancelled: { true }) }
    }

    @Test func childLookups() throws {
        let tree = try read("(board (at 1.5 -2 90) (pad \"1\") (pad 2) (hide) (locked yes) (off no) flat)")
        #expect(tree.keyword == "board")
        #expect(tree.child("at")?.number(at: 2) == -2)
        #expect(tree.child("at")?.number(at: 9) == nil)
        #expect(tree.children("pad").count == 2)
        #expect(tree.children("pad").first?.text(at: 1) == "1")
        #expect(tree.child("nope") == nil)
        #expect(tree.hasFlag("hide") && tree.hasFlag("locked") && tree.hasFlag("flat"))
        #expect(!tree.hasFlag("off") && !tree.hasFlag("missing"))
    }

    @Test func refusesLargeFileAndLongTokens() {
        var tiny = KiCadLimits()
        tiny.maxFileBytes = 8
        #expect(message("(a 1 2 3 4 5)", limits: tiny)?.contains("larger than") == true)
        var short = KiCadLimits()
        short.maxStringBytes = 4
        #expect(message("(a abcdefgh)", limits: short)?.contains("longer than") == true)
        #expect(message("(a |abcdefgh|)", limits: short) == nil) // a data block is bounded by the file size alone
    }
}
