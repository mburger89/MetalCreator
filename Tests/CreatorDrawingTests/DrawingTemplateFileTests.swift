import CreatorDrawing
import Foundation
import Testing

/// DR-5 R10: the template model and its file.
struct DrawingTemplateFileTests {
    static func sheet() -> DrawingSheet {
        DrawingSheet(
            name: "Sheet 1", size: .a2, orientation: .portrait,
            titleBlock: TitleBlock(
                owner: "Acme", title: "Bracket", drawingNumber: "B-1", revision: "C", material: "Steel", drawnBy: "MB", date: "2026-11-26",
                density: 7.85, logo: String(repeating: "a", count: 64)))
    }

    static func template(logo: Data? = nil) -> DrawingTemplate {
        .made(from: sheet(), standard: .asme, logo: logo, name: "Acme", id: "T-1")
    }

    static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static var good: [String: Any] { ["version": 1, "name": "N", "size": "a3", "orientation": "landscape", "standard": "iso"] }

    @Test func aTemplateRoundTrips() throws {
        for logo in [nil, Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])] {
            let template = Self.template(logo: logo)
            let data = DrawingTemplateFile.encode(template)
            #expect(try DrawingTemplateFile.decode(data, id: "T-1") == template)
            #expect(DrawingTemplateFile.encode(template) == data)
        }
        let text = String(bytes: DrawingTemplateFile.encode(Self.template(logo: Data([1, 2, 3]))), encoding: .utf8) ?? ""
        #expect(text.contains("\"logo\""))
        #expect(text.contains("AQID"))
        let names = ["logo", "name", "orientation", "size", "standard", "titleBlock", "version"]
        let keys = names.compactMap { text.range(of: "\"\($0)\"")?.lowerBound }
        #expect(keys.count == 7 && keys == keys.sorted())
    }

    @Test func onlyTheDefaultsAreKept() {
        let template = Self.template(logo: Data([1]))
        #expect(template.titleBlock == TitleBlock(owner: "Acme", material: "Steel", drawnBy: "MB", density: 7.85))
        #expect(template.size == .a2 && template.orientation == .portrait && template.standard == .asme)
        #expect(template.id == "T-1" && template.name == "Acme")
    }

    @Test func badTemplatesAreSkippedInWords() throws {
        func message(_ data: Data) -> String? {
            do { _ = try DrawingTemplateFile.decode(data, id: "x"); return nil } catch { return error.message }
        }
        #expect(message(Data("not json".utf8)) == "it isn't a drawing template.")
        var noSize = Self.good
        noSize["size"] = nil
        #expect(try message(Self.json(noSize)) == "it isn't a drawing template.")
        var newer = Self.good
        newer["version"] = 2
        #expect(try message(Self.json(newer)) == "it was saved by a newer MetalCreator.")
        var big = Self.good
        big["logo"] = Data(count: 2_500_000).base64EncodedString()
        #expect(try message(Self.json(big)) == "its logo is larger than 2 MB.")
        var badLogo = Self.good
        badLogo["logo"] = "!!!not base64!!!"
        #expect(try message(Self.json(badLogo)) == "its logo isn't readable.")
        #expect(try message(Self.json(Self.good)) == nil)
    }

    @Test func unknownKeysAreIgnored() throws {
        var object = Self.good
        object["future"] = ["a": 1]
        object["titleBlock"] = ["owner": "Acme", "mystery": true]
        let template = try DrawingTemplateFile.decode(Self.json(object), id: "x")
        #expect(template.titleBlock.owner == "Acme")
    }

    @Test func theLimitIsThreeMebibytes() {
        #expect(DrawingTemplateLimits.maximumFileBytes == 3_145_728)
    }
}
