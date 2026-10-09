import CreatorGeometry
import CreatorSketch
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// S4: `ConstantValue.sketch` and `.facePick` are settings saved in `.mcgraph` files (format 4).
struct SketchSettingFileTests {
    func sampleSketch() -> Sketch {
        var sketch = Sketch(plane: .fixed(.xz))
        let a = sketch.addPoint(Vector2(0, 0)), b = sketch.addPoint(Vector2(30, 0)), c = sketch.addPoint(Vector2(0, 20))
        let bottom = sketch.addLine(from: a, to: b)
        sketch.addLine(from: b, to: c)
        sketch.addLine(from: c, to: a)
        sketch.add(.horizontal(bottom))
        sketch.addDimension(.length(bottom), value: 30)
        sketch.addCircle(center: Vector2(8, 5), radius: 2)
        return sketch
    }

    @Test func aSketchSettingRoundTripsThroughAFile() throws {
        let node = makeNode(ConstantNode.self, [NodeSetting.sketch: .sketch(sampleSketch())])
        let file = GraphFile(graph: graph([node]))
        let decoded = try GraphFileIO.decode(try GraphFileIO.encode(file), registry: testRegistry)
        #expect(decoded == file)
        #expect(decoded.graph.nodes[node.id]?.inputValues[NodeSetting.sketch] == .sketch(sampleSketch()))
    }

    @Test func aSavedSketchIsByteIdenticalWhenSavedAgain() throws {
        let node = makeNode(ConstantNode.self, [NodeSetting.sketch: .sketch(sampleSketch())])
        let data = try GraphFileIO.encode(GraphFile(graph: graph([node])))
        let reloaded = try GraphFileIO.decode(data, registry: testRegistry)
        #expect(try GraphFileIO.encode(reloaded) == data)
    }

    @Test func aFacePickSettingRoundTripsThroughAFile() throws {
        let plate = NodeID()
        let pick = FacePick(tags: [TopoTag(node: plate, item: 0, role: .endCap), TopoTag(node: plate, item: 1, role: .endCap)])
        let node = makeNode(ConstantNode.self, [NodeSetting.face: .facePick(pick)])
        let data = try GraphFileIO.encode(GraphFile(graph: graph([node])))
        #expect(try #require(String(bytes: data, encoding: .utf8)).contains(#""type" : "facePick""#))
        let decoded = try GraphFileIO.decode(data, registry: testRegistry)
        #expect(decoded.graph.nodes[node.id]?.inputValues[NodeSetting.face] == .facePick(pick))
    }

    @Test func sketchesAndFacePicksAreSettingsWithNoRuntimeValue() {
        #expect(Scalar(.sketch(sampleSketch())) == nil)
        #expect(Scalar(.facePick(FacePick(tags: []))) == nil)
    }

    @Test func aNonFiniteSketchIsRefused() {
        var broken = sampleSketch()
        broken.addPoint(Vector2(.nan, 0))
        let node = makeNode(ConstantNode.self)
        var target = graph([node])
        #expect(throws: GraphError.invalidValue("Enter a finite number.")) {
            try target.apply(.setInput(node.id, NodeSetting.sketch, .sketch(broken)), registry: testRegistry)
        }
    }

    @Test func projectionSettingsAreNamedAfterTheirReference() {
        #expect(NodeSetting.projection("p1") == "projection.p1")
        #expect(NodeSetting.all.isSuperset(of: [NodeSetting.sketch, NodeSetting.face]))
    }

    @Test func versionThreeFilesStillLoad() throws {
        let id = NodeID()
        let json = """
        {"formatVersion": 3, "graph": {"nodes": [{"id": "\(id.rawValue.uuidString)", "typeID": "test.constant",
        "typeVersion": 1, "name": "Constant", "inputValues": {"value": {"type": "number", "value": 3}},
        "position": {"x": 0, "y": 0}, "isOutput": false}]}}
        """
        let file = try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        #expect(file.graph.nodes[id]?.inputValues["value"] == .number(3))
    }
}
