import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorMCP
import CreatorNodes
import Foundation
import Testing

@MainActor struct EditToolTests {
    private func id(_ node: NodeID) -> JSONValue { .string(node.rawValue.uuidString) }

    private func operation(_ tool: String, _ arguments: [String: JSONValue]) -> JSONValue {
        .object(["tool": .string(tool), "arguments": .object(arguments)])
    }

    @Test func addNodeIsOneNamedStep() async throws {
        let fixture = try await SessionFixture()
        let before = fixture.document.graph.nodes.count
        let (result, isError) = try await fixture.call("add_node", .object(["type": .string("creator.revolve")]))
        #expect(!isError)
        #expect(fixture.document.undoName == "Add Revolve")
        #expect(fixture.document.graph.nodes.count == before + 1)
        let added = try #require(result["added"]?.array?.first?.string)
        let node = try #require(fixture.document.graph.nodes.values.first { $0.id.rawValue.uuidString == added })
        #expect(!fixture.document.graph.nodes.values.contains { $0.id != node.id && $0.position == node.position })
        let (_, unknown) = try await fixture.call("add_node", .object(["type": .string("creator.nope")]))
        #expect(unknown)
    }

    @Test func addNodeUnknownTypeSentence() async throws {
        let fixture = try await SessionFixture()
        let (text, isError) = try await fixture.call("add_node", .object(["type": .string("creator.nope")]))
        #expect(isError && text.string == "There's no node type “creator.nope”.")
    }

    @Test func addNodeNamesAndSetsInputsInOneStep() async throws {
        let fixture = try await SessionFixture()
        let arguments: JSONValue = .object([
            "type": .string("creator.extrude"), "name": .string("Pad"), "position": .array([.int(5), .int(6)]),
            "inputs": .object(["distance": .int(30)]),
        ])
        let (_, isError) = try await fixture.call("add_node", arguments)
        #expect(!isError)
        let pad = try #require(fixture.document.graph.nodes.values.first { $0.name == "Pad" })
        #expect(pad.inputValues["distance"] == .number(30) && pad.position == Vector2(5, 6))
        #expect(fixture.document.undoName == "Add Extrude")
        fixture.document.undo()
        #expect(!fixture.document.graph.nodes.values.contains { $0.name == "Pad" })
    }

    @Test func setInputsCoercesAndNames() async throws {
        let fixture = try await SessionFixture()
        let (_, isError) = try await fixture.call("set_inputs", .object([
            "node": .string("Extrude"), "values": .object(["distance": .int(25)]),
        ]))
        #expect(!isError)
        #expect(fixture.document.graph.nodes[fixture.extrude]?.inputValues["distance"] == .number(25))
        #expect(fixture.document.undoName == "Change Distance")
        _ = try await fixture.call("set_inputs", .object([
            "node": .string("Extrude"), "values": .object(["distance": .int(20), "reversed": .bool(true)]),
        ]))
        #expect(fixture.document.undoName == "Change Inputs")
    }

    @Test func segmentedTakesNameOrIndex() async throws {
        let fixture = try await SessionFixture()
        _ = try await fixture.call("set_inputs", .object(["node": .string("Extrude"), "values": .object(["mode": .string("symmetric")])]))
        let byName = fixture.document.graph.nodes[fixture.extrude]?.inputValues["mode"]
        _ = try await fixture.call("set_inputs", .object(["node": .string("Extrude"), "values": .object(["mode": .int(0)])]))
        _ = try await fixture.call("set_inputs", .object(["node": .string("Extrude"), "values": .object(["mode": .int(1)])]))
        #expect(byName == .integer(1) && fixture.document.graph.nodes[fixture.extrude]?.inputValues["mode"] == byName)
    }

    @Test func outOfRangeIsRefusedUnchanged() async throws {
        let fixture = try await SessionFixture()
        let before = fixture.document.content
        let (text, isError) = try await fixture.call("set_inputs", .object([
            "node": .string("Extrude"), "values": .object(["distance": .int(5000)]),
        ]))
        #expect(isError && text.string == "Distance must be between 0.1 and 200.")
        #expect(fixture.document.content == before)
    }

    @Test func textSettingsAreStoredAsText() async throws {
        let fixture = try await SessionFixture()
        _ = try await fixture.call("add_node", .object(["type": .string("creator.pathMapper"), "name": .string("Mapper")]))
        let (_, isError) = try await fixture.call("set_inputs", .object([
            "node": .string("Mapper"), "values": .object(["pathRule": .string("{A;B} → {B;A}")]),
        ]))
        #expect(!isError)
        let mapper = try #require(fixture.document.graph.nodes.values.first { $0.name == "Mapper" })
        #expect(mapper.inputValues["pathRule"] == .text("{A;B} → {B;A}"))
        let (_, wrong) = try await fixture.call("set_inputs", .object([
            "node": .string("Mapper"), "values": .object(["pathRule": .int(3)]),
        ]))
        #expect(wrong)
    }

    @Test func connectRefusesTypeMismatchInItsWords() async throws {
        let fixture = try await SessionFixture()
        let before = fixture.document.content
        let (mismatch, failed) = try await fixture.call("connect", .object([
            "from": .string("Rectangle.profile"), "to": .string("Output.solid"),
        ]))
        #expect(failed && mismatch.string == ConnectionProblem.typeMismatch(from: .profile, to: .solid).message)
        #expect(fixture.document.content == before)
    }

    @Test func connectReplacesAndDisconnectRemoves() async throws {
        let fixture = try await SessionFixture()
        _ = try await fixture.call("add_node", .object(["type": .string("creator.rectangle"), "name": .string("Second")]))
        let (_, isError) = try await fixture.call("connect", .object([
            "from": .string("Second.profile"), "to": .string("Extrude.profile"),
        ]))
        #expect(!isError)
        #expect(fixture.document.graph.links.filter { $0.to == Endpoint(node: fixture.extrude, socket: "profile") }.count == 1)
        #expect(fixture.document.undoName == "Connect")
        _ = try await fixture.call("disconnect", .object(["to": .string("Extrude.profile")]))
        #expect(fixture.document.undoName == "Disconnect")
        let (text, again) = try await fixture.call("disconnect", .object(["to": .string("Extrude.profile")]))
        #expect(again && text.string == "Nothing is wired into Extrude.profile.")
    }

    @Test func editReportsChangedStates() async throws {
        let fixture = try await SessionFixture()
        let (result, isError) = try await fixture.call("disconnect", .object(["to": .string("Extrude.profile")]))
        #expect(!isError && result["still_evaluating"]?.bool == false)
        let changed = try #require(result["changed"]?.array)
        let extrude = try #require(changed.first { $0["name"]?.string == "Extrude" })
        #expect(extrude["state"]?.string != "ok" && extrude["message"]?.string != nil)
        #expect(result["step"]?.string == "Disconnect")
    }

    @Test func removeRenameOutputAndMove() async throws {
        let fixture = try await SessionFixture()
        _ = try await fixture.call("rename_node", .object(["node": .string("Extrude"), "name": .string("Pad")]))
        #expect(fixture.document.undoName == "Rename Node" && fixture.document.graph.nodes[fixture.extrude]?.name == "Pad")
        _ = try await fixture.call("set_output", .object(["node": .string("Pad"), "output": .bool(true)]))
        #expect(fixture.document.undoName == "Set Output" && fixture.document.graph.nodes[fixture.extrude]?.isOutput == true)
        _ = try await fixture.call("move_node", .object(["node": .string("Pad"), "position": .array([.int(1), .number(2.5)])]))
        #expect(fixture.document.undoName == "Move" && fixture.document.graph.nodes[fixture.extrude]?.position == Vector2(1, 2.5))
        _ = try await fixture.call("remove_nodes", .object(["nodes": .array([id(fixture.extrude), .string("Rectangle")])]))
        #expect(fixture.document.undoName == "Delete" && fixture.document.graph.nodes.count == 1)
    }

    @Test func batchIsOneStepOrNothing() async throws {
        let fixture = try await SessionFixture()
        let add = operation("add_node", ["type": .string("creator.rectangle"), "name": .string("Second")])
        let wire = operation("connect", ["from": .string("Second.profile"), "to": .string("Extrude.profile")])
        let (_, isError) = try await fixture.call("batch", .object(["operations": .array([add, wire])]))
        #expect(!isError)
        #expect(fixture.document.undoName == "Add Rectangle")
        #expect(fixture.document.graph.nodes.values.contains { $0.name == "Second" })
        fixture.document.undo()
        #expect(!fixture.document.graph.nodes.values.contains { $0.name == "Second" })
        #expect(fixture.document.graph.links.count == 2)

        let before = fixture.document.content
        let bad = operation("connect", ["from": .string("Second.profile"), "to": .string("Nope.x")])
        let (text, failed) = try await fixture.call("batch", .object(["operations": .array([add, bad])]))
        #expect(failed && (text.string ?? "").hasPrefix("Operation 2:"))
        #expect(fixture.document.content == before)
        let (other, notAllowed) = try await fixture.call("batch", .object([
            "operations": .array([.object(["tool": .string("get_document")])]),
        ]))
        #expect(notAllowed && (other.string ?? "").hasPrefix("Operation 1:"))
    }

    @Test func positionlessAddsInABatchDoNotOverlap() async throws {
        let fixture = try await SessionFixture()
        let add = operation("add_node", ["type": .string("creator.rectangle")])
        let (result, isError) = try await fixture.call("batch", .object(["operations": .array([add, add])]))
        #expect(!isError)
        let ids = try #require(result["added"]?.array).compactMap(\.string)
        let positions = fixture.document.graph.nodes.values.filter { ids.contains($0.id.rawValue.uuidString) }.map(\.position)
        #expect(positions.count == 2)
        let first = positions[0], second = positions[1]
        #expect(abs(first.x - second.x) >= 224 || abs(first.y - second.y) >= 1)
    }

    @Test func clientEditsNeverCoalesce() async throws {
        let fixture = try await SessionFixture()
        for value in [11, 12] {
            _ = try await fixture.call("set_inputs", .object(["node": .string("Extrude"), "values": .object(["distance": .int(value)])]))
        }
        fixture.document.undo()
        #expect(fixture.document.graph.nodes[fixture.extrude]?.inputValues["distance"] == .number(11))
        fixture.document.undo()
        #expect(fixture.document.graph.nodes[fixture.extrude]?.inputValues["distance"] != .number(11))
    }
}
