import CreatorGeometry
import CreatorSketch
import Foundation
import Testing
@testable import CreatorGraph

/// G-c: sketch splines are saved in format 11; files of format 10 and before open unchanged.
struct SplineSketchFileTests {
    func splineSketch() -> Sketch {
        var sketch = Sketch(plane: .fixed(.xz))
        let start = sketch.addPoint(Vector2(0, 0))
        let joint = sketch.addPoint(Vector2(10, 0))
        let line = sketch.addLine(from: start, to: joint)
        let far = sketch.addPoint(Vector2(20, 3))
        let spline = sketch.addSpline(through: [joint, far])
        sketch.activateSplineHandle(spline, at: 0, .tangent)
        sketch.activateSplineHandle(spline, at: 0, .curvature)
        sketch.add(.curvature(line, spline))
        sketch.remember(SketchSolver.solve(sketch))
        return sketch
    }

    @Test func formatElevenRoundTrips() throws {
        #expect(GraphFile.currentFormatVersion == 11)
        let node = makeNode(ConstantNode.self, [NodeSetting.sketch: .sketch(splineSketch())])
        let file = GraphFile(graph: graph([node]))
        let data = try GraphFileIO.encode(file)
        let text = try #require(String(bytes: data, encoding: .utf8))
        #expect(text.contains(#""formatVersion" : 11"#) && text.contains("spline") && text.contains("curvature"))
        let decoded = try GraphFileIO.decode(data, registry: testRegistry)
        #expect(decoded == file)
        #expect(decoded.graph.nodes[node.id]?.inputValues[NodeSetting.sketch] == .sketch(splineSketch()))
        #expect(try GraphFileIO.encode(decoded) == data)
    }

    @Test func formatTenOpensUnchanged() throws {
        let node = makeNode(ConstantNode.self, [NodeSetting.sketch: .sketch(SketchSettingFileTests().sampleSketch())])
        let current = try GraphFileIO.encode(GraphFile(graph: graph([node])))
        var object = try #require(JSONSerialization.jsonObject(with: current) as? [String: Any])
        object["formatVersion"] = 10
        let older = try JSONSerialization.data(withJSONObject: object)
        let file = try GraphFileIO.decode(older, registry: testRegistry)
        #expect(file.formatVersion == 10)
        #expect(file.graph.nodes[node.id]?.inputValues[NodeSetting.sketch] == .sketch(SketchSettingFileTests().sampleSketch()))
        let resaved = GraphFile(graph: file.graph, definitions: file.definitions, viewState: file.viewState)
        #expect(try GraphFileIO.decode(try GraphFileIO.encode(resaved), registry: testRegistry).formatVersion == 11)
    }

    @Test func aNewerFileThanThisBuildIsRefused() {
        let text = #"{"formatVersion": 12, "graph": {"nodes": []}}"#
        #expect(throws: (any Error).self) { try GraphFileIO.decode(Data(text.utf8), registry: testRegistry) }
    }
}
