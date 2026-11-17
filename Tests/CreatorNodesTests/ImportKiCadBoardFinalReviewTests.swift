#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorOCCT
import Foundation
import Testing
@testable import CreatorNodes

/// The final review's fixes to Import KiCad Board: mounting hole rules and the outline's bounds.
struct ImportKiCadBoardFinalReviewTests {
    let folder = TempFolderForNodes()

    func run(_ text: String) async throws -> (EvaluationReport, Node) {
        let file = try folder.write(Data(text.utf8), to: "board.kicad_pcb")
        var h = Harness()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let board = h.add(ImportKiCadBoardNode.self, [NodeSetting.pcbFile: .pcbFile(reference)])
        return (try await h.run([board], kernel: OCCTKernel()), board)
    }

    @Test func aPadViaMountingHoleIsOnePlacementOfItsLargestHole() async throws {
        var part = "  (footprint \"MountingHole:MountingHole_3.2mm_M3_Pad_Via\" (layer \"F.Cu\") (at 50 40)\n"
        part += "    (property \"Reference\" \"H1\" (at 0 -4 0) (layer \"F.Cu\"))\n"
        part += "    (pad \"1\" thru_hole circle (at 0 0) (size 5.6 5.6) (drill 3.2) (layers \"*.Cu\" \"*.Mask\"))\n"
        for step in 0..<8 {
            let angle = Double(step) * .pi / 4
            part += "    (pad \"1\" thru_hole circle (at \(2.4 * cos(angle)) \(2.4 * sin(angle))) (size 0.9 0.9) (drill 0.6) "
                + "(layers \"*.Cu\" \"*.Mask\"))\n"
        }
        part += "  )\n"
        let (report, board) = try await run(KiCadBoardText.rectangle(parts: [], extra: part))
        #expect(report.isOK(board), "\(String(describing: report.state(board)))")
        #expect(report.value(board, "mounting hole diameters")?.numbers == [3.2])
        #expect(report.value(board, "mounting holes")?.planes?.count == 1)
    }

    @Test func aSurfaceMountPartWithOnePegHoleIsNotAMountingHole() async throws {
        var part = "  (footprint \"Connector:Thing\" (layer \"F.Cu\") (at 50 40)\n"
        part += "    (property \"Reference\" \"J1\" (at 0 -4 0) (layer \"F.Cu\"))\n"
        part += "    (pad \"\" np_thru_hole circle (at 0 0) (size 2 2) (drill 2) (layers \"*.Cu\" \"*.Mask\"))\n"
        part += "    (pad \"1\" smd rect (at 3 0) (size 1 1) (layers \"F.Cu\"))\n"
        part += "    (pad \"2\" smd rect (at 5 0) (size 1 1) (layers \"F.Cu\"))\n  )\n"
        let (report, board) = try await run(KiCadBoardText.rectangle(parts: [], extra: part))
        #expect(report.isOK(board))
        #expect(report.value(board, "mounting hole diameters")?.numbers == [])
    }

    @Test func aBezierEdgeIsBoundedByTheCurveNotItsPoles() async throws {
        // The curve bulges 22.5 mm (3/4 of its control points' 30 mm), so the board is 102.5 mm tall, not 110.
        var text = KiCadBoardText.header + "  (general (thickness 1.6))\n"
        text += "  (gr_curve (pts (xy 0 0) (xy 0 -30) (xy 100 -30) (xy 100 0)) \(KiCadBoardText.stroke(KiCadBoardText.uuid(1))))\n"
        for (index, line) in [(100, 0, 100, 80), (100, 80, 0, 80), (0, 80, 0, 0)].enumerated() {
            text += "  (gr_line (start \(line.0) \(line.1)) (end \(line.2) \(line.3)) "
                + "\(KiCadBoardText.stroke(KiCadBoardText.uuid(10 + index))))\n"
        }
        let (report, board) = try await run(text + ")\n")
        #expect(report.isOK(board), "\(String(describing: report.state(board)))")
        let facts = Dictionary(uniqueKeysWithValues: try #require(report.results[board.id]?.facts).map { ($0.label, $0.value) })
        #expect(facts["Size"] == "100 × 102.5 mm")
        let solid = try onlySolid(report, board, "board")
        // The box is centred on the board: half of 102.5 each way.
        #expect(abs(solid.bounds.min.y + 51.25) < 0.05 && abs(solid.bounds.max.y - 51.25) < 0.05)
    }

    @Test func aCancelledParseStops() async {
        var text = KiCadBoardText.header
        for index in 0..<10_000 {
            text += "(gr_line (start \(index) 0) (end \(index + 1) 0) (layer \"Edge.Cuts\"))\n"
        }
        let data = Data((text + ")").utf8)
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return await withTaskCancellationHandler { () -> Bool in
                do { _ = try ImportKiCadBoardNode.parse(data) } catch is CancellationError { return true } catch { return false }
                return false
            } onCancel: {}
        }
        task.cancel()
        #expect(await task.value)
    }
}
#endif
