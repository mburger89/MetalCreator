import CreatorGeometry
import Foundation
import Testing

@testable import CreatorDrawing
@testable import CreatorGraph

/// An assembly sheet in a DXF (DR-5 Task 6, R13): the logo's stand-in, balloons and tables on their layers.
@Suite struct DXFAssemblyTests {
    private let style = DrawingStyle.iso

    private func read(_ output: DXFOutput) throws -> DXFReader { try DXFReader(data: output.data) }

    private func assembly() -> DXFOutput { DXFWriter.sheet(DrawingFixtures.assemblySheet(), style: style) }

    @Test func theLogoIsARectangleOnFrame() throws {
        let output = assembly()
        #expect(output.leftOutImages)
        #expect(!DXFWriter.sheet(DrawingFixtures.a4Sheet(), style: style).leftOutImages)
        let entities = try read(output).sections["ENTITIES"] ?? []
        let logo = entities.filter { record in
            record.type == "LWPOLYLINE" && record.layer == "FRAME" && record.all(10) == ["30", "34", "34", "30", "30"]
                && record.all(20) == ["20", "20", "23", "23", "20"]
        }
        #expect(logo.count == 1)
    }

    @Test func balloonsOnDimensionTablesOnFrameAndText() throws {
        let entities = try read(assembly()).sections["ENTITIES"] ?? []
        let circles = entities.filter { $0.type == "CIRCLE" }
        #expect(circles.count == 3 && circles.allSatisfy { $0.layer == "DIMENSION" })
        let numbers = entities.filter { $0.type == "TEXT" && ["1", "2", "3"].contains($0.first(1) ?? "") && $0.layer == "DIMENSION" }
        #expect(numbers.count == 3)
        let solids = entities.filter { $0.type == "SOLID" }
        #expect(!solids.isEmpty && solids.allSatisfy { $0.layer == "DIMENSION" })
        let header = entities.first { $0.type == "TEXT" && $0.first(1) == "Item" }
        #expect(header?.layer == "FRAME")
        let cell = entities.first { $0.type == "TEXT" && $0.first(1) == "First issue" }
        #expect(cell?.layer == "TEXT")
    }

    @Test func assemblySheetDXFDigest() {
        #expect(assembly().data == assembly().data)
        let digest = SHA256.hash(assembly().data)
            .map { String($0, radix: 16).count == 1 ? "0" + String($0, radix: 16) : String($0, radix: 16) }.joined()
        #expect(digest == "18a4abd4f095c6f672963ea01b0454dd316b5ea403b57273d03121997e6e5fc6")
    }
}
