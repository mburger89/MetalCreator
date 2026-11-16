import CreatorGeometry
import Foundation
import Testing
@testable import CreatorPCB

struct KiCadVersionFormsTests {
    private func read(_ era: BoardFixtures.Era) throws -> KiCadBoard {
        try KiCadBoardReader.read(Data(BoardFixtures.rectangleWithFourM3(era).utf8))
    }

    private func close(_ a: Vector2, _ b: Vector2) -> Bool { (a - b).length < 1e-9 }

    private func same(_ a: EdgeItem.Shape, _ b: EdgeItem.Shape) -> Bool {
        switch (a, b) {
        case (.line(let a0, let a1), .line(let b0, let b1)): close(a0, b0) && close(a1, b1)
        case (.arc(let a0, let a1, let a2), .arc(let b0, let b1, let b2)): close(a0, b0) && close(a1, b1) && close(a2, b2)
        default: false
        }
    }

    @Test func everyVersionFormReadsTheSameGeometry() throws {
        let reference = try read(.kicad10)
        for era in BoardFixtures.Era.allCases {
            let board = try read(era)
            #expect(board.edgeItems.count == reference.edgeItems.count, "\(era)")
            for (left, right) in zip(board.edgeItems, reference.edgeItems) {
                #expect(same(left.shape, right.shape), "\(era)")
            }
            #expect(board.footprints.map(\.reference) == ["H1", "H2", "H3", "H4"], "\(era)")
            for (left, right) in zip(board.footprints, reference.footprints) {
                #expect(left.holes.count == 1, "\(era)")
                #expect(close(left.holes[0].center, right.holes[0].center), "\(era)")
                #expect(left.holes[0].diameter == 3.2 && !left.holes[0].isPlated, "\(era)")
            }
            #expect(board.thickness == 1.6 && board.copperLayers == 2, "\(era)")
        }
    }

    @Test func chainingToleranceFollowsTheVersion() {
        #expect(KiCadBoard(version: 4).chainingTolerance == 0.005)
        #expect(KiCadBoard(version: 20_171_130).chainingTolerance == 0.005)
        #expect(KiCadBoard(version: 20_171_131).chainingTolerance == 0.02)
        #expect(KiCadBoard(version: 20_221_017).chainingTolerance == 0.02)
        #expect(KiCadBoard(version: 20_221_018).chainingTolerance == 0.01)
        #expect(KiCadBoard(version: 20_261_031).chainingTolerance == 0.01)
    }

    @Test func versionsAndGeneratorsAreRead() throws {
        #expect(try read(.kicad4).version == 4)
        #expect(try read(.kicad11).version == 20_261_031)
        #expect(try read(.kicad4).generator == "pcbnew")
        #expect(try read(.kicad8).generator == "pcbnew")
    }

    @Test func aMissingVersionIs20201115() throws {
        let board = try KiCadBoardReader.read(Data("(kicad_pcb)".utf8))
        #expect(board.version == 20_201_115)
    }
}
