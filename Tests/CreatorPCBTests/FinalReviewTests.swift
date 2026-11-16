import CreatorGeometry
import Foundation
import Testing
@testable import CreatorPCB

/// The final review's fixes for KI-1: limits, slots, pad counts, hostile input and skipped subtrees.
struct FinalReviewTests {
    private func read(_ text: String, limits: KiCadLimits = .standard) throws -> KiCadBoard {
        try KiCadBoardReader.read(Data(text.utf8), limits: limits)
    }

    @Test func aDataBlockOverTheStringLimitReads() throws {
        let block = String(repeating: "A", count: (1 << 20) + 10)
        let tree = try SExpressionReader.read(Data("(kicad_pcb (data |\(block)|))".utf8))
        #expect(tree.child("data")?.text(at: 1)?.count == block.count)
    }

    @Test func aQuotedStringOverTheLimitStillFails() {
        let text = "(kicad_pcb (x \"\(String(repeating: "A", count: (1 << 20) + 10))\"))"
        #expect(throws: KiCadProblem.self) { try SExpressionReader.read(Data(text.utf8)) }
    }

    @Test func anEqualSidedOvalReadsItsHeightAsItsWidth() throws {
        let board = try read("""
        (kicad_pcb (version 20260206) (footprint "L:F" (at 0 0)
          (pad "1" thru_hole oval (at 0 0) (size 2 2) (drill oval 1.0))))
        """)
        let hole = try #require(board.footprints.first?.holes.first)
        #expect(hole.diameter == 1 && hole.slotLength == nil)
    }

    @Test func padCountIncludesSMDPads() throws {
        let board = try read("""
        (kicad_pcb (version 20260206) (footprint "L:F" (at 0 0)
          (pad "" np_thru_hole circle (at 0 0) (size 2 2) (drill 2))
          (pad "1" smd rect (at 3 0) (size 1 1)) (pad "2" smd rect (at 5 0) (size 1 1))))
        """)
        let footprint = try #require(board.footprints.first)
        #expect(footprint.holes.count == 1 && footprint.padCount == 3)
    }

    @Test func skippedChildrenAreNeverBuilt() throws {
        var points = ""
        for index in 0..<20_000 { points += "(xy \(index) 0) " }
        let text = """
        (kicad_pcb (version 20260206) (net 0 "") (zone (net 1) (polygon (pts \(points))) (name "a)b"))
          (segment (start 0 0) (end 1 1)) (gr_text "x" (at 0 0)) (gr_line (start 0 0) (end 1 0) (layer "Edge.Cuts")))
        """
        let tree = try SExpressionReader.read(Data(text.utf8), skipping: KiCadBoardReader.skipped)
        guard case .list(let items) = tree else { Issue.record("not a list"); return }
        #expect(items.compactMap(\.keyword) == ["version", "gr_line"])
        #expect(tree.child("zone") == nil && tree.child("net") == nil && tree.child("segment") == nil)
        #expect(try read(text).edgeItems.count == 1)
    }

    @Test func aSkippedListStillHonoursItsClosingAndDepth() {
        #expect(throws: KiCadProblem.self) {
            try SExpressionReader.read(Data("(kicad_pcb (zone (a (b)".utf8), skipping: ["zone"])
        }
        let deep = "(kicad_pcb (zone " + String(repeating: "(", count: 100) + String(repeating: ")", count: 100) + "))"
        #expect(throws: KiCadProblem.self) { try SExpressionReader.read(Data(deep.utf8), skipping: ["zone"]) }
    }

    @Test func tooManyOutlinePiecesIsRefused() {
        var limits = KiCadLimits()
        limits.maxEdgeItems = 3
        var text = "(kicad_pcb (version 20260206)"
        for index in 0..<4 { text += " (gr_line (start \(index) 0) (end \(index) 1) (layer \"Edge.Cuts\"))" }
        #expect(throws: KiCadProblem("This board has more than 3 outline pieces.")) { try read(text + ")", limits: limits) }
        #expect(KiCadLimits.standard.maxEdgeItems == 100_000)
    }

    @Test func manyEdgeItemsSharingOneIdentityGetKeysQuickly() throws {
        let items = (0..<20_000).map { _ in EdgeItem(shape: .line(.zero, Vector2(1, 0)), identity: "edge:same") }
        var board = KiCadBoard(edgeItems: items)
        try KeyAssigner.assign(&board)
        #expect(board.edgeItems[0].identity == "edge:same" && board.edgeItems[19_999].identity == "edge:same#20000")
        #expect(Set(board.edgeItems.map { $0.identity }).count == 20_000)
    }

    @Test func assigningCanBeCancelled() {
        let items = (0..<10_000).map { EdgeItem(shape: .line(.zero, Vector2(1, 0)), identity: "edge:\($0)") }
        var board = KiCadBoard(edgeItems: items)
        #expect(throws: CancellationError.self) { try KeyAssigner.assign(&board, isCancelled: { true }) }
    }

    @Test func chainingCanBeCancelled() {
        var items: [EdgeItem] = []
        for index in 0..<10_000 {
            let a = Vector2(Double(index), 0), b = Vector2(Double(index + 1), 0)
            items.append(EdgeItem(shape: .line(a, b), identity: "edge:\(index)"))
        }
        #expect(throws: CancellationError.self) { try OutlineChainer.chain(items, tolerance: 0.01, isCancelled: { true }) }
    }

    @Test func aBarInsideAnAtomOfASkippedListIsNotADataBlock() throws {
        let text = """
        (kicad_pcb (version 20260206) (zone (name /RX|TX) (filled "x")) (gr_line (start 0 0) (end 1 0) (layer "Edge.Cuts")))
        """
        #expect(try read(text).edgeItems.count == 1)
    }
}
