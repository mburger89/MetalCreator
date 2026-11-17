import CreatorGeometry
import Foundation
import Testing
@testable import CreatorPCB

struct SExpressionFuzzTests {
    private static func board() -> [UInt8] {
        var text = "(kicad_pcb (version 20240108) (generator \"pcbnew\")\n"
        var index = 0
        while text.utf8.count < 2_000 {
            text += "  (footprint \"R_\(index)\" (layer \"F.Cu\") (at \(index).5 -3 90)\n"
            text += "    (pad \"1\" smd rect (at 0 0) (size 1 1) (layers \"F.Cu\")) (data |QUJD|))\n"
            index += 1
        }
        return Array((text + ")").utf8)
    }

    @Test func randomMutationsNeverCrash() {
        var random = SeededRandom(seed: 7)
        let original = Self.board()
        let inserts: [UInt8] = [UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "\""), UInt8(ascii: "|"), 0, 0xFF]
        for _ in 0..<5_000 {
            var bytes = original
            let kind = Int(random.next() % 3)
            let place = Int(random.next() % UInt64(bytes.count))
            switch kind {
            case 0:
                for _ in 0..<(1 + Int(random.next() % 4)) {
                    bytes[Int(random.next() % UInt64(bytes.count))] = UInt8(truncatingIfNeeded: random.next())
                }
            case 1:
                bytes = Array(bytes[..<place])
            default:
                bytes.insert(inserts[Int(random.next() % UInt64(inserts.count))], at: place)
            }
            do {
                _ = try SExpressionReader.read(Data(bytes))
            } catch is KiCadProblem {
            } catch {
                Issue.record("unexpected error \(error)")
            }
        }
    }
}
