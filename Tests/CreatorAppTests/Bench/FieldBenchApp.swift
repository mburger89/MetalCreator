#if canImport(CreatorOCCT)
// Test fixture file: the §7.2 bracket with field nodes beside it, for the field preview's benchmark (fields spec §7, row 4).
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// The bracket the other benchmarks measure (`makeBracketBenchApp`), and beside it two fields: a Remap of the signed distance
/// from the bracket's finished part (`remap`: 0 to `fromHigh` mm onto 0…1) and a Radial Gradient (`radial`). Neither feeds the
/// Output; selecting one tints the bracket in Final preview.
@MainActor
struct FieldBenchApp {
    let app: AppModel
    let bracket: AppBracket
    let distance: Node
    let remap: Node
    let radial: Node

    init() async throws {
        (app, bracket) = try await makeBracketBenchApp()
        distance = try Self.add(DistanceFieldNode.self, to: app)
        remap = try Self.add(FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(20), "toLow": .number(0), "toHigh": .number(1),
        ], to: app)
        radial = try Self.add(RadialGradientNode.self, ["center": .vector(Vector3(0, 0, 0)), "radius": .number(40)], to: app)
        try Self.wire(bracket.chamfer, "solid", distance, "target", in: app)
        try Self.wire(distance, "field", remap, "field", in: app)
        await app.settle()
    }

    func select(_ node: Node) {
        app.editor.selection = [node.id]
    }

    func setFromHigh(_ millimetres: Double) throws {
        try app.document.perform(.setInput(remap.id, "fromHigh", .number(millimetres)))
    }

    func setRadius(_ millimetres: Double) throws {
        try app.document.perform(.setInput(radial.id, "radius", .number(millimetres)))
    }

    private static func add(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:],
                            to app: AppModel) throws -> Node {
        var node = app.registry.makeNode(definition.typeID, at: Vector2(Double(app.document.graph.nodes.count) * 40, 200))
        node.inputValues.merge(values) { _, given in given }
        try app.document.perform(.addNode(node))
        return node
    }

    private static func wire(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName, in app: AppModel) throws {
        try app.document.perform(.connect(Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input))))
    }
}
#endif
