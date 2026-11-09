import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorMCP
import CreatorNodes
import Foundation
import Testing

@MainActor struct HistoryToolTests {
    private func addBox(_ fixture: SessionFixture) async throws -> String {
        let (result, isError) = try await fixture.call("add_node", .object(["type": .string("creator.implicitBox")]))
        #expect(!isError)
        return try #require(result["added"]?.array?.first?.string)
    }

    @Test func undoTakesBackTheClientStep() async throws {
        let fixture = try await SessionFixture()
        let added = try await addBox(fixture)
        let (result, isError) = try await fixture.call("undo")
        #expect(!isError)
        #expect(result["step"]?.string == "Add Box")
        #expect(result["changed"]?.array != nil)
        #expect(!fixture.document.graph.nodes.values.contains { $0.id.rawValue.uuidString == added })
    }

    @Test func undoRefusesThePersonsStep() async throws {
        let fixture = try await SessionFixture()
        _ = try await addBox(fixture)
        try fixture.document.perform(.move(fixture.rectangle, to: Vector2(500, 500)), name: UndoName.move)
        let (text, isError) = try await fixture.call("undo")
        #expect(isError && text.string == "The last step is yours, not mine: Undo Move.")
    }

    @Test func undoWithNothingToUndo() async throws {
        let fixture = try await SessionFixture()
        while fixture.document.canUndo { fixture.document.undo() }
        let (text, isError) = try await fixture.call("undo")
        #expect(isError && text.string == "There's nothing to undo.")
    }

    @Test func redoAfterUndo() async throws {
        let fixture = try await SessionFixture()
        let added = try await addBox(fixture)
        _ = try await fixture.call("undo")
        let (result, isError) = try await fixture.call("redo")
        #expect(!isError)
        #expect(result["step"]?.string == "Add Box")
        #expect(fixture.document.graph.nodes.values.contains { $0.id.rawValue.uuidString == added })
    }

    @Test func redoRefusedAfterThePersonUndoes() async throws {
        let fixture = try await SessionFixture()
        _ = try await addBox(fixture)
        fixture.document.undo()
        let (text, isError) = try await fixture.call("redo")
        #expect(isError && text.string == "The next step to redo is yours: Redo Add Box.")
    }

    @Test func undoRefusesAPersonsIdenticalRepeat() async throws {
        let fixture = try await SessionFixture()
        _ = try await fixture.call("set_inputs", .object(["node": .string("Extrude"), "values": .object(["distance": .int(5)])]))
        fixture.document.undo()
        try fixture.document.perform(.setInput(fixture.extrude, "distance", .number(5)), name: "Change Distance")
        let (text, isError) = try await fixture.call("undo")
        #expect(isError && text.string == "The last step is yours, not mine: Undo Change Distance.")
    }

    @Test func redoRefusesAPersonsIdenticalStep() async throws {
        let fixture = try await SessionFixture()
        _ = try await fixture.call("set_inputs", .object(["node": .string("Extrude"), "values": .object(["distance": .int(5)])]))
        _ = try await fixture.call("undo")
        try fixture.document.perform(.setInput(fixture.extrude, "distance", .number(5)), name: "Change Distance")
        fixture.document.undo()
        let (text, isError) = try await fixture.call("redo")
        #expect(isError && text.string == "The next step to redo is yours: Redo Change Distance.")
    }

    @Test func redoWithNothingToRedoAfterANewStep() async throws {
        let fixture = try await SessionFixture()
        _ = try await addBox(fixture)
        _ = try await fixture.call("undo")
        try fixture.document.perform(.move(fixture.rectangle, to: Vector2(9, 9)), name: UndoName.move)
        let (text, isError) = try await fixture.call("redo")
        #expect(isError && text.string == "There's nothing to redo.")
    }

    @Test func relativePathIsRefused() async throws {
        let fixture = try await SessionFixture()
        let (text, isError) = try await fixture.call("set_file", .object(["node": .string("Extrude"), "path": .string("pic.png")]))
        #expect(isError && text.string == "Paths must be absolute.")
    }

    @Test func absolutePathReachesTheSession() async throws {
        let fixture = try await SessionFixture()
        let (text, isError) = try await fixture.call("set_file", .object(["node": .string("Extrude"), "path": .string("/tmp/pic.png")]))
        #expect(isError && text.string == "That isn't available here.")
    }
}
