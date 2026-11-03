#if canImport(Metal) && canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// Row `loft-ends-1`: a 20 x 20 x 10 box's top face lofted to a 12 x 12 square 10 mm above it at Curvature (G2). Each step edits
/// the square's width to a value the evaluator has not cached, then waits for the evaluation, the scene and its meshes: edit
/// to preview. Release; prints `BENCH loft-ends-1 …`. Recorded, not gated.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct LoftEndsBench {
    @Test func aBoxFaceToASquareAtG2() async throws {
        guard Bench.requireRelease() else { return }
        let app = AppModel(kernel: OCCTKernel())
        func add(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:]) throws -> Node {
            var node = app.registry.makeNode(definition.typeID, at: Vector2(Double(app.document.graph.nodes.count) * 40, 0))
            node.inputValues.merge(values) { _, given in given }
            try app.document.perform(.addNode(node))
            return node
        }
        func wire(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) throws {
            let link = Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input))
            try app.document.perform(.connect(link))
        }
        let base = try add(RectangleNode.self, ["width": .number(20), "height": .number(20)])
        let box = try add(ExtrudeNode.self, ["distance": .number(10)])
        try wire(base, "profile", box, "profile")
        let square = try add(RectangleNode.self, ["width": .number(12), "height": .number(12),
                                                  "plane": .plane(.through(Vector3(0, 0, 20))),
        ])
        let pick = FacePick(tags: [TopoTag(node: box.id, item: 0, role: .endCap)])
        let loft = try add(LoftNode.self, [NodeSetting.startFace: .facePick(pick), "startContinuity": .integer(2)])
        try wire(square, "profile", loft, "sections")
        try wire(box, "solid", loft, "solid")
        let union = try add(BooleanNode.self)
        try wire(box, "solid", union, "target")
        try wire(loft, "solid", union, "tools")
        let output = try add(OutputNode.self)
        try wire(union, "solid", output, "solid")
        await app.settle()
        expectAllOK(app, "the box-to-square loft at G2")
        var samples = BenchSamples("loft-ends-1 box top face to 12 mm square at G2, edit to preview")
        let clock = ContinuousClock()
        for step in 0..<40 {
            let begin = clock.now
            try app.document.perform(.setInput(square.id, "width", .number(12 + Double(step) * 0.02)))
            await app.settle()
            if step >= 5 { samples.append(from: begin, to: clock.now) }
        }
        expectAllOK(app, "after the edits")
        print(samples.line())
    }
}
#endif
