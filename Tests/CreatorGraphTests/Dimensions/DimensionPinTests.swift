import CreatorKernel
import Foundation
import Testing
@testable import CreatorGraph

/// Pinned dimensions (DIM-3 Task 2): a sorted, unique list on every graph, edited by two commands that change no result,
/// taken out with their node and brought back by its undo, and saved under format 10.
@MainActor
struct DimensionPinTests {
    let a = makeNode(ConstantNode.self, ["value": .number(1)])
    let b = makeNode(AddNode.self)

    var pinA: DimensionPin { DimensionPin(node: a.id, target: .input("value")) }
    var pinB: DimensionPin { DimensionPin(node: b.id, target: .input("a")) }

    func scene(pins: [DimensionPin] = []) -> Graph {
        var made = graph([a, b], [link(a, "value", b, "a")])
        made.dimensionPins = pins.sorted()  // As commands and decoding keep them.
        return made
    }

    func reopened(_ file: GraphFile) throws -> GraphFile {
        try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
    }

    func json(_ file: GraphFile) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: try GraphFileIO.encode(file)) as? [String: Any])
    }

    @Test func pinningKeepsTheListSortedAndUnique() throws {
        var g = scene()
        let (first, second) = pinA < pinB ? (pinA, pinB) : (pinB, pinA)
        try g.apply(.pinDimension(second), registry: testRegistry)
        try g.apply(.pinDimension(first), registry: testRegistry)
        #expect(g.dimensionPins == [first, second])
        let before = g
        #expect(throws: GraphError.invalidValue("That dimension is pinned already.")) {
            try g.apply(.pinDimension(first), registry: testRegistry)
        }
        #expect(g == before)
    }

    @Test func unpinningAPinThatIsntThereIsRefused() {
        var g = scene(pins: [pinA])
        #expect(throws: GraphError.invalidValue("That dimension isn't pinned.")) {
            try g.apply(.unpinDimension(pinB), registry: testRegistry)
        }
        #expect(g.dimensionPins == [pinA])
    }

    @Test func pinAndUnpinAreInversesAndChangeNoResult() throws {
        let start = scene(pins: [pinB])
        var g = start
        let inverse = try g.apply(.pinDimension(pinA), registry: testRegistry)
        #expect(inverse == .unpinDimension(pinA))
        #expect(g.dimensionPins.count == 2)
        try g.apply(inverse, registry: testRegistry)
        #expect(g == start)
        let undo = try g.apply(.unpinDimension(pinB), registry: testRegistry)
        #expect(undo == .pinDimension(pinB))
        #expect(g.dimensionPins.isEmpty)
        try g.apply(undo, registry: testRegistry)
        #expect(g == start)
        for command in [GraphCommand.pinDimension(pinA), .unpinDimension(pinA)] {
            #expect(command.affectsResults == false)
            #expect(command.touchedNodes.isEmpty)
        }
    }

    @Test func removingANodeTakesItsPinsAndUndoBringsThemBack() throws {
        let extra = DimensionPin(node: a.id, target: .input("other"))
        let start = scene(pins: [pinA, extra, pinB])
        var g = start
        let inverse = try g.apply(.removeNode(a.id), registry: testRegistry)
        #expect(g.dimensionPins == [pinB])
        try g.apply(inverse, registry: testRegistry)
        #expect(g == start)
    }

    @Test func pinsRoundTripAndAreOmittedWhenEmpty() throws {
        let file = GraphFile(graph: scene(pins: [pinA]))
        let written = try #require(try json(file)["graph"] as? [String: Any])
        let pins = try #require(written["dimensionPins"] as? [[String: Any]])
        #expect(pins.count == 1)
        #expect(pins.first?["node"] as? String == a.id.rawValue.uuidString)
        #expect(pins.first?["input"] as? String == "value")
        #expect(try reopened(file) == file)
        let none = try #require(try json(GraphFile(graph: scene()))["graph"] as? [String: Any])
        #expect(none["dimensionPins"] == nil)
    }

    @Test func aFileWithoutPinsOpensWithNone() throws {
        let text = #"{"formatVersion": 9, "graph": {"nodes": []}}"#
        let file = try GraphFileIO.decode(Data(text.utf8), registry: testRegistry)
        #expect(file.graph.dimensionPins.isEmpty)
    }

    @Test func pinsOnAMissingNodeAreKeptOnOpen() throws {
        let gone = DimensionPin(node: NodeID(), target: .input("distance"))
        var written = scene()
        written.dimensionPins = [gone, pinA, pinA]  // unsorted, repeated, one with no node
        let decoded = try reopened(GraphFile(graph: written)).graph
        #expect(decoded.dimensionPins == [gone, pinA].sorted(), "a dangling pin stays in the file (spec Errata)")
    }

    @Test func pinsInsideADefinitionAreSavedWithIt() throws {
        let doubler = Doubler()
        let pin = DimensionPin(node: doubler.add.id, target: .input("a"))
        let content = GraphContent(graph: Graph(), definitions: table([doubler.definition]))
        var edited = content
        let inverse = try edited.apply(.inDefinition(doubler.id, .pinDimension(pin)), registry: testRegistry)
        #expect(edited.definitions[doubler.id]?.graph.dimensionPins == [pin])
        #expect(inverse == .inDefinition(doubler.id, .unpinDimension(pin)))
        let file = GraphFile(graph: edited.graph, definitions: edited.definitions)
        #expect(try reopened(file) == file)
        #expect(try reopened(file).definitions[doubler.id]?.graph.dimensionPins == [pin])
    }

    @Test func pinningIsOneNamedUndoStep() throws {
        let document = DocumentModel(file: GraphFile(graph: scene()), registry: testRegistry, kernel: FakeKernel())
        let before = document.content
        try document.perform(.pinDimension(pinA), name: UndoName.pinDimension)
        #expect(document.undoName == "Pin Dimension")
        #expect(document.content != before, "a pin is a content change, so the document counts as edited")
        document.undo()
        #expect(document.content == before)
        document.redo()
        #expect(document.graph.dimensionPins == [pinA])
        try document.perform(.unpinDimension(pinA), name: UndoName.unpinDimension)
        #expect(document.undoName == "Unpin Dimension")
        #expect(UndoName.changeDimension == "Change Dimension")
    }
}
