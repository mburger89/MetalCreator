import CreatorGraph
import Foundation
import Testing
@testable import CreatorImplicit

/// The XML scanner under the 3MF reader: elements, attributes as byte ranges, what it skips and what it refuses.
@Suite("XMLScanner")
struct XMLScannerTests {
    /// The events of `bytes` as text: `<name a=b c=d>` and `</name>`, attribute values with entities resolved.
    static func events(_ bytes: [UInt8]) throws -> [String] {
        try bytes.withUnsafeBytes { raw in
            var scanner = XMLScanner(bytes: raw)
            var out: [String] = []
            while let event = try scanner.next() {
                switch event {
                case .start(let tag):
                    var line = "<" + scanner.text(tag.name)
                    for attribute in scanner.attributes(of: tag) {
                        line += " " + scanner.text(attribute.name) + "=" + (try scanner.decoded(attribute.value))
                    }
                    out.append(line + ">")
                case .end(let name):
                    out.append("</" + scanner.text(name) + ">")
                }
            }
            return out
        }
    }

    static func events(_ text: String) throws -> [String] { try events(Array(text.utf8)) }

    @Test func elementsAndAttributesComeInOrder() throws {
        let found = try Self.events("<a x=\"1\" y='two'><b/><c  z = \"3\" ></c></a>")
        #expect(found == ["<a x=1 y=two>", "<b>", "</b>", "<c z=3>", "</c>", "</a>"])
    }

    @Test func namespacesAreLiteralPrefixes() throws {
        let found = try Self.events("<m:model xmlns:m=\"urn:x\" m:a=\"1\"><m:vertex/></m:model>")
        #expect(found == ["<m:model xmlns:m=urn:x m:a=1>", "<m:vertex>", "</m:vertex>", "</m:model>"])
    }

    @Test func commentsInstructionsAndCDATAAreSkipped() throws {
        let text = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><!-- a <b> comment --><a><?pi data?><![CDATA[ <not> a tag ]]>text<b/></a>"
        #expect(try Self.events(text) == ["<a>", "<b>", "</b>", "</a>"])
    }

    @Test func aByteOrderMarkIsSkipped() throws {
        #expect(try Self.events([0xEF, 0xBB, 0xBF] + Array("<a/>".utf8)) == ["<a>", "</a>"])
    }

    @Test func entitiesAreResolved() throws {
        let found = try Self.events("<a v=\"&lt;&gt;&amp;&quot;&apos; &#65;&#x42;&#x1F600;\"/>")
        #expect(found.first == "<a v=<>&\"' AB\u{1F600}>")
    }

    @Test func aGreaterThanInsideAValueDoesNotEndTheTag() throws {
        #expect(try Self.events("<a v=\"1>2\" w='3/>'/>") == ["<a v=1>2 w=3/>>", "</a>"])
    }

    @Test(arguments: [
        "<!DOCTYPE a [<!ENTITY x \"y\">]><a/>", "<?xml version=\"1.0\"?><!DOCTYPE a><a/>",
    ])
    func aDoctypeIsRefused(_ text: String) {
        let problem = #expect(throws: MeshImportProblem.self) { try Self.events(text) }
        #expect(problem?.message.contains("DOCTYPE") == true)
    }

    @Test(arguments: [
        "<a><b></a></b>", "<a>", "<a></b>", "</a>", "<a/><b/>", "<a x=1/>", "<a x=\"1/>", "<a x></a>", "<a x=\"<\"/>", "<a",
        "<!-- never", "<a><![CDATA[ never", "", "   ", "text<a/>", "<a/>text", "<a v=\"&nope;\"/>", "<a v=\"&#0;\"/>",
        "<a v=\"&#xD800;\"/>",
        "<a v=\"& \"/>", "<a v=\"&#99999999999;\"/>", "<>", "<a><?pi never</a>",
    ])
    func malformedDocumentsAreRefused(_ text: String) {
        #expect(throws: MeshImportProblem.self) { try Self.events(text) }
    }

    @Test func aSixteenBitDocumentIsRefused() {
        #expect(throws: MeshImportProblem.self) {
            try Self.events("<?xml version=\"1.0\" encoding=\"UTF-16\"?><a/>")
        }
    }

    @Test func nestingIsLimited() throws {
        let deep = String(repeating: "<a>", count: XMLScanner.maximumDepth) + String(repeating: "</a>", count: XMLScanner.maximumDepth)
        #expect(try Self.events(deep).count == 2 * XMLScanner.maximumDepth)
        let deeper = "<a>" + deep + "</a>"
        #expect(throws: MeshImportProblem.self) { try Self.events(deeper) }
    }

    @Test func rangesPointIntoTheDocument() throws {
        let text = Array("<a n=\"12\" s=\"x\"></a>".utf8)
        try text.withUnsafeBytes { raw in
            var scanner = XMLScanner(bytes: raw)
            guard case .start(let tag)? = try scanner.next() else { Issue.record("no start"); return }
            let all = Array(scanner.attributes(of: tag))
            #expect(all.count == 2)
            #expect(scanner.equals(all[0].name, "n") && scanner.integer(all[0].value) == 12)
            #expect(scanner.equals(all[1].name, "s") && scanner.integer(all[1].value) == nil)
            #expect(scanner.depth == 1)
        }
    }

    @Test func integersAreStrict() throws {
        let text = Array("<a v=\"-1\" w=\"1.5\" x=\"\" y=\"+3\" z=\"007\" big=\"99999999999999999999\"/>".utf8)
        text.withUnsafeBytes { raw in
            var scanner = XMLScanner(bytes: raw)
            guard case .start(let tag)? = try? scanner.next() else { Issue.record("no start"); return }
            let values = scanner.attributes(of: tag).map { scanner.integer($0.value) }
            #expect(values == [nil, nil, nil, nil, 7, nil])
        }
    }
}

extension XMLScannerTests {
    @Test func aDeclarationIsReadOnlyForItsFirstBytes() throws {
        let padding = String(repeating: " ", count: 1_000_000)
        #expect(try Self.events("<?xml version=\"1.0\"\(padding)encoding=\"UTF-16\"?><a/>") == ["<a>", "</a>"])
        #expect(try Self.events("<?xml version=\"1.0\" encoding=\"UTF-8\"\(padding)?><a/>") == ["<a>", "</a>"])
        #expect(throws: MeshImportProblem.self) { try Self.events("<?xml version=\"1.0\" encoding=\"UTF-16\"\(padding)?><a/>") }
    }
}
