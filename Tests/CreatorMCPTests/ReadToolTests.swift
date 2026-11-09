import CreatorGraph
import CreatorKernel
import CreatorMCP
import CreatorNodes
import Foundation
import Testing

@MainActor struct ReadToolTests {
    @Test func documentListsNodesLinksAndStates() async throws {
        let fixture = try await SessionFixture()
        let (document, isError) = try await fixture.call("get_document")
        #expect(!isError)
        let nodes = try #require(document["nodes"]?.array)
        #expect(nodes.count == 3)
        #expect(nodes.allSatisfy { $0["state"]?.string == "ok" })
        let links = try #require(document["links"]?.array)
        #expect(links.count == 2)
        #expect(links.contains { $0["from"]?.string == "Rectangle.profile" && $0["to"]?.string == "Extrude.profile" })
        #expect(document["name"]?.string == "Untitled")
        #expect(document["next_cursor"] == nil)
    }

    @Test func nodesReportTheirOutputFlag() async throws {
        let fixture = try await SessionFixture()
        let (document, _) = try await fixture.call("get_document")
        let nodes = try #require(document["nodes"]?.array)
        let flags = Dictionary(uniqueKeysWithValues: nodes.compactMap { node in
            node["name"]?.string.map { ($0, node["is_output"]?.bool) }
        })
        #expect(flags == ["Rectangle": false, "Extrude": false, "Output": true])
        let rectangle = try #require(nodes.first { $0["name"]?.string == "Rectangle" })
        #expect(rectangle["output"] == nil)
        #expect(rectangle["outputs"]?.object?["profile"]?.string != nil)
        let (output, _) = try await fixture.call("get_node", .object(["node": .string("Output")]))
        #expect(output["is_output"]?.bool == true)
        let (extrude, _) = try await fixture.call("get_node", .object(["node": .string("Extrude")]))
        #expect(extrude["is_output"]?.bool == false)
    }

    @Test func documentPagesAt200() async throws {
        let fixture = try await SessionFixture()
        let numbers = (0..<450).map { index in
            var node = fixture.document.registry.makeNode("creator.number", at: .init(Double(index), 0))
            node.name = "N\(index)"
            return GraphCommand.addNode(node)
        }
        try fixture.document.perform(.batch(numbers), name: "Add Node")
        var sizes: [Int] = []
        var cursor: Int?
        var cursors: [Int?] = []
        repeat {
            let arguments: JSONValue = cursor.map { .object(["cursor": .int($0)]) } ?? .object([:])
            let (page, _) = try await fixture.call("get_document", arguments)
            sizes.append(try #require(page["nodes"]?.array).count)
            cursor = page["next_cursor"]?.int
            cursors.append(cursor)
        } while cursor != nil
        #expect(sizes == [200, 200, 53])
        #expect(cursors == [200, 400, nil])
    }

    @Test func nodeShowsValuesWiresAndSummaries() async throws {
        let fixture = try await SessionFixture()
        let (node, isError) = try await fixture.call("get_node", .object(["node": .string("Extrude")]))
        #expect(!isError)
        let inputs = try #require(node["inputs"]?.array)
        let height = try #require(inputs.first { $0["name"]?.string == "distance" })
        #expect(height["value"]?.int == 10)
        #expect(height["unit"]?.string == "millimetres")
        let profile = try #require(inputs.first { $0["name"]?.string == "profile" })
        #expect(profile["wired_from"]?.string == "Rectangle.profile")
        let outputs = try #require(node["outputs"]?.array)
        #expect(outputs.first?["summary"]?.string == "solid")
        #expect(node["state"]?.string == "ok")
    }

    @Test func typesFilterByCategoryAndSearch() async throws {
        let fixture = try await SessionFixture()
        let (solids, _) = try await fixture.call("list_node_types", .object(["category": .string("solid")]))
        let list = try #require(solids["types"]?.array)
        #expect(!list.isEmpty)
        #expect(list.allSatisfy { $0["category"]?.string == "solid" })
        let (found, _) = try await fixture.call("list_node_types", .object(["search": .string("EXTR")]))
        #expect(try #require(found["types"]?.array).contains { $0["type"]?.string == "creator.extrude" })
        let (bad, isError) = try await fixture.call("list_node_types", .object(["category": .string("zzz")]))
        #expect(isError)
        #expect(bad.string?.hasPrefix("There's no category called “zzz”.") == true)
    }

    @Test func describeGivesDefaultsRangesOptions() async throws {
        let fixture = try await SessionFixture()
        let (type, _) = try await fixture.call("describe_node_type", .object(["type": .string("creator.extrude")]))
        let inputs = try #require(type["inputs"]?.array)
        let mode = try #require(inputs.first { $0["name"]?.string == "mode" })
        #expect(mode["options"] == .array([.string("One side"), .string("Symmetric")]))
        let distance = try #require(inputs.first { $0["name"]?.string == "distance" })
        #expect(distance["range"]?.array?.count == 2)
        #expect(distance["default"]?.int == 10)
        #expect(distance["unit"]?.string == "millimetres")
        #expect(type["outputs"]?.array?.first?["name"]?.string == "solid")
    }

    @Test func documentResourceMatchesTheTool() async throws {
        let fixture = try await SessionFixture()
        let request = #"{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"metalcreator://document"}}"#
        let sent = Collected()
        await fixture.core.handle(line: Data(request.utf8)) { sent.add($0) }
        let reply = try JSONValue.parse(try #require(sent.all.last))
        let text = try #require(reply["result"]?["contents"]?.array?.first?["text"]?.string)
        let (tool, _) = try await fixture.call("get_document")
        #expect(try JSONValue.parse(Data(text.utf8)) == tool)
    }

    @Test func summaryDescribesASocketList() {
        #expect(NodeDescriptions.summary(of: ExtrudeNode.self)
            == "Extrude: inputs profile, distance, mode, reversed → outputs solid")
    }
}
