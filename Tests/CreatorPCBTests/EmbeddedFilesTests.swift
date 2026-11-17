import Foundation
import Testing
@testable import CreatorPCB

struct EmbeddedFilesTests {
    private func board(version: Int = 20_260_206, body: String) throws -> KiCadBoard {
        try KiCadBoardReader.read(Data("(kicad_pcb (version \(version)) (generator \"pcbnew\")\n\(body))".utf8))
    }

    private func file(_ name: String, _ type: String, _ data: String) -> String {
        "(file (name \"\(name)\") (type \(type)) (data\n |\(data)|\n ) (checksum \"00\"))"
    }

    @Test func keepsModelsAndNotDatasheets() throws {
        let body = "(embedded_files " + file("a.step", "model", "QUJD\nREVG") + file("ds.pdf", "datasheet", "WFla")
            + file("b.wrl", "model", "R0g=") + ")"
        let result = try board(body: body)
        #expect(result.embeddedModels == [
            EmbeddedFile(name: "a.step", base64: "QUJD\nREVG"),
            EmbeddedFile(name: "b.wrl", base64: "R0g="),
        ])
    }

    @Test func footprintTableIsItsOwn() throws {
        let body = "(footprint \"X:Y\" (at 0 0) (embedded_files " + file("m.step", "model", "QQ==") + "))"
        let result = try board(body: body)
        #expect(result.footprints[0].embeddedModels == [EmbeddedFile(name: "m.step", base64: "QQ==")])
        #expect(result.embeddedModels.isEmpty)
    }

    @Test func emptyDataIsKeptEmpty() throws {
        let result = try board(body: "(embedded_files (file (name \"m.step\") (type model) (data)))")
        #expect(result.embeddedModels == [EmbeddedFile(name: "m.step", base64: "")])
    }

    @Test func olderVersionKeepsNone() throws {
        let result = try board(version: 20_240_705, body: "(embedded_files " + file("a.step", "model", "QUJD") + ")")
        #expect(result.embeddedModels.isEmpty)
    }

    @Test func fortyLargeModelsKeepOneCopyOfText() throws {
        let chunk = String(repeating: "QUJD", count: 512 * 1024) // 2 MiB of base64
        var body = "(embedded_files "
        for index in 0..<40 { body += file("m\(index).step", "model", chunk) }
        body += ")"
        let result = try board(body: body)
        #expect(result.embeddedModels.count == 40)
        #expect(result.embeddedModels.reduce(0) { $0 + $1.base64.utf8.count } == 40 * chunk.utf8.count)
    }
}
