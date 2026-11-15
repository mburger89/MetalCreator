import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorMCP
import Testing

@MainActor struct BatchNameTests {
    private func op(_ tool: String, _ arguments: [String: JSONValue]) -> JSONValue {
        .object(["tool": .string(tool), "arguments": .object(arguments)])
    }

    private func run(_ fixture: SessionFixture, _ operations: [JSONValue], stepName: JSONValue? = nil) async throws -> (JSONValue, Bool) {
        var arguments: [String: JSONValue] = ["operations": .array(operations)]
        if let stepName { arguments["step_name"] = stepName }
        return try await fixture.call("batch", .object(arguments))
    }

    private func add(_ name: String) -> JSONValue {
        op("add_node", ["type": .string("creator.rectangle"), "name": .string(name)])
    }

    @Test func batchOfAddsAndConnectsIsBuild() async throws {
        let fixture = try await SessionFixture()
        let (result, isError) = try await run(fixture, [
            add("Second"), op("connect", ["from": .string("Second.profile"), "to": .string("Extrude.profile")]),
        ])
        #expect(!isError && result["step"]?.string == "Build" && fixture.document.undoName == "Build")
    }

    @Test func singleOperationBatchKeepsItsOwnName() async throws {
        let fixture = try await SessionFixture()
        _ = try await run(fixture, [op("add_node", ["type": .string("creator.revolve")])])
        #expect(fixture.document.undoName == "Add Revolve")
    }

    @Test func connectOnlyBatchIsRewire() async throws {
        let fixture = try await SessionFixture()
        _ = try await run(fixture, [
            op("disconnect", ["to": .string("Extrude.profile")]),
            op("connect", ["from": .string("Rectangle.profile"), "to": .string("Extrude.profile")]),
        ])
        #expect(fixture.document.undoName == "Rewire")
    }

    @Test func moveOnlyBatchIsRearrange() async throws {
        let fixture = try await SessionFixture()
        _ = try await run(fixture, [
            op("move_node", ["node": .string("Extrude"), "position": .array([.int(1), .int(2)])]),
            op("move_node", ["node": .string("Rectangle"), "position": .array([.int(3), .int(4)])]),
        ])
        #expect(fixture.document.undoName == "Rearrange")
    }

    @Test func removeOnlyBatchIsDelete() async throws {
        let fixture = try await SessionFixture()
        _ = try await run(fixture, [
            op("remove_nodes", ["nodes": .array([.string("Output")])]),
            op("remove_nodes", ["nodes": .array([.string("Extrude")])]),
        ])
        #expect(fixture.document.undoName == "Delete")
    }

    @Test func mixedWithoutAddIsEditGraph() async throws {
        let fixture = try await SessionFixture()
        _ = try await run(fixture, [
            op("set_inputs", ["node": .string("Extrude"), "values": .object(["distance": .int(20)])]),
            op("rename_node", ["node": .string("Extrude"), "name": .string("Pad")]),
        ])
        #expect(fixture.document.undoName == "Edit Graph")
    }

    @Test func explicitStepNameWins() async throws {
        let fixture = try await SessionFixture()
        let (result, _) = try await run(fixture, [add("A"), add("B")], stepName: .string("Clean Up"))
        #expect(result["step"]?.string == "Clean Up" && fixture.document.undoName == "Clean Up")
    }

    @Test func unknownStepNameIsRefusedAndChangesNothing() async throws {
        let fixture = try await SessionFixture()
        let before = fixture.document.content
        let undoName = fixture.document.undoName
        let (text, isError) = try await run(fixture, [add("A")], stepName: .string("Make a plate"))
        #expect(isError)
        #expect(text.string == "The step name must be one of Build, Rewire, Rearrange, Clean Up, Delete or Edit Graph.")
        #expect(fixture.document.content == before && fixture.document.undoName == undoName)
    }

    @Test func nonStringStepNameIsRefused() async throws {
        let fixture = try await SessionFixture()
        let before = fixture.document.content
        let (_, isError) = try await run(fixture, [add("A")], stepName: .int(3))
        #expect(isError && fixture.document.content == before)
    }

    @Test func batchUndoRedoNamesMatch() async throws {
        let fixture = try await SessionFixture()
        _ = try await run(fixture, [add("A"), add("B")])
        let (undone, _) = try await fixture.call("undo")
        #expect(undone["step"]?.string == "Build" && fixture.document.redoName == "Build")
        let (redone, _) = try await fixture.call("redo")
        #expect(redone["step"]?.string == "Build" && fixture.document.undoName == "Build")
    }
}
