import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// Comments are saved with their graph (canvas comments spec 2026-10-09 §7): sorted by ID, keys optional on decode,
/// under the current format version 5 that groups (C1) already bumped to.
@MainActor
struct CommentFileTests {
    func json(_ file: GraphFile) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: try GraphFileIO.encode(file)) as? [String: Any])
    }

    @Test func commentsRoundTripOnTheTopLevelAndInsideADefinition() throws {
        let doubler = Doubler()
        var definition = doubler.definition
        definition.graph.stickies[commentID(5)] = note(5, "Inside the group", at: Vector2(10, 20), accent: .pink)
        definition.graph.frames[commentID(6)] = box(6, "Inner frame", accent: .cyan)
        var top = graph([makeNode(ConstantNode.self)])
        top.stickies[commentID(1)] = note(1, "Line one\nLine two", accent: .yellow)
        top.frames[commentID(2)] = box(2, "Outer", at: Vector2(-50, -60), accent: .orange)
        let file = GraphFile(graph: top, definitions: table([definition]))
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
        #expect(decoded == file)
        #expect(decoded.definitions[definition.id]?.graph.stickies[commentID(5)]?.text == "Inside the group")
    }

    @Test func commentsAreWrittenSortedByID() throws {
        let ids = [7, 3, 9, 1, 5]
        var g = Graph()
        for n in ids {
            g.stickies[commentID(n)] = note(n)
            g.frames[commentID(n + 100)] = box(n + 100)
        }
        let written = try #require(try json(GraphFile(graph: g))["graph"] as? [String: Any])
        let notes = try #require(written["stickies"] as? [[String: Any]]).compactMap { $0["id"] as? String }
        let frames = try #require(written["frames"] as? [[String: Any]]).compactMap { $0["id"] as? String }
        #expect(notes == ids.sorted().map { commentID($0).rawValue.uuidString })
        #expect(frames == ids.sorted().map { commentID($0 + 100).rawValue.uuidString })
        #expect(try GraphFileIO.encode(GraphFile(graph: g)) == GraphFileIO.encode(GraphFile(graph: g)), "deterministic")
    }

    @Test func aGraphWithoutCommentsIsWrittenWithoutTheKeys() throws {
        let written = try #require(try json(GraphFile(graph: graph([makeNode(ConstantNode.self)])))["graph"] as? [String: Any])
        #expect(written["stickies"] == nil && written["frames"] == nil)
    }

    @Test func versionFourAndFiveFilesWithoutTheKeysOpenUnchanged() throws {
        let id = NodeID()
        for version in [4, 5] {
            let text = """
            {"formatVersion": \(version), "graph": {"nodes": [{"id": "\(id.rawValue.uuidString)", "typeID": "test.constant",
            "typeVersion": 1, "name": "Constant", "position": {"x": 0, "y": 0}, "isOutput": false,
            "inputValues": {"value": {"type": "number", "value": 2}}}]}}
            """
            let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
            #expect(file.graph.stickies.isEmpty && file.graph.frames.isEmpty, "version \(version)")
            #expect(file.graph.nodes[id]?.inputValues["value"] == .number(2), "version \(version)")
        }
    }

    @Test func commentsAddNoFormatBump() {
        #expect(GraphFile.currentFormatVersion == 5)
    }

    @Test func anUnknownAccentReadsAsMuted() throws {
        let text = """
        {"formatVersion": 5, "graph": {"nodes": [],
        "stickies": [{"id": "\(commentID(1).rawValue.uuidString)", "text": "Hi", "accent": "teal",
        "frame": {"origin": {"x": 1, "y": 2}, "size": {"x": 160, "y": 100}}}],
        "frames": [{"id": "\(commentID(2).rawValue.uuidString)", "title": "F", "accent": "teal",
        "frame": {"origin": {"x": 1, "y": 2}, "size": {"x": 300, "y": 200}}}]}}
        """
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.graph.stickies[commentID(1)]?.accent == .muted)
        #expect(file.graph.frames[commentID(2)]?.accent == .muted)
        #expect(file.graph.stickies[commentID(1)]?.frame.origin == Vector2(1, 2))
    }

    /// A hand-edited file may repeat an ID: the first one read wins, and a frame never takes a note's ID.
    @Test func aRepeatedIDKeepsTheFirstAndANoteBeatsAFrame() throws {
        let id = commentID(1).rawValue.uuidString
        let rect = #"{"origin": {"x": 0, "y": 0}, "size": {"x": 160, "y": 100}}"#
        let text = """
        {"formatVersion": 5, "graph": {"nodes": [],
        "stickies": [{"id": "\(id)", "text": "first", "frame": \(rect)}, {"id": "\(id)", "text": "second", "frame": \(rect)}],
        "frames": [{"id": "\(id)", "title": "clash", "frame": \(rect)}]}}
        """
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.graph.stickies[commentID(1)]?.text == "first")
        #expect(file.graph.frames.isEmpty)
    }

    /// A hand-edited file may give a comment a negative size; it reads as zero, so it can still be selected with ⌘A and
    /// deleted, and nothing downstream sees an inside-out rectangle.
    @Test func aNegativeSizeInAFileReadsAsZero() throws {
        let rect = #"{"origin": {"x": 5, "y": 6}, "size": {"x": -40, "y": 30}}"#
        let text = """
        {"formatVersion": 5, "graph": {"nodes": [],
        "stickies": [{"id": "\(commentID(1).rawValue.uuidString)", "text": "Odd", "frame": \(rect)}],
        "frames": [{"id": "\(commentID(2).rawValue.uuidString)", "title": "Odd", "frame": \(rect)}]}}
        """
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.graph.stickies[commentID(1)]?.frame == CanvasRect(origin: Vector2(5, 6), size: Vector2(0, 30)))
        #expect(file.graph.frames[commentID(2)]?.frame.size == Vector2(0, 30))
    }

    @Test func theDocumentSavesItsComments() throws {
        let document = DocumentModel(file: GraphFile(graph: Graph(stickies: [commentID(1): note(1, "Saved")])),
                                     registry: testRegistry, kernel: FakeKernel())
        let reopened = try GraphFileIO.decode(try document.fileData(), registry: testRegistry)
        #expect(reopened.graph.stickies[commentID(1)]?.text == "Saved")
    }

    @Test func graphEqualityIncludesComments() {
        var edited = Graph()
        edited.stickies[commentID(1)] = note(1)
        #expect(edited != Graph())
        #expect(edited.commentIDs == [commentID(1)])
    }
}
