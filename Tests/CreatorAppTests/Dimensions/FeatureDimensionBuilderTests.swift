import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorViewport
import Foundation
import Testing
@testable import CreatorApp

/// Which dimensions a selection and the pins show, how each is edited, and how it reads (DIM-3 Task 10).
struct FeatureDimensionBuilderTests {
    let geometry = DimensionGeometry.linear(from: .zero, to: Vector3(10, 0, 0), direction: Vector3(1, 0, 0),
                                            side: Vector3(0, 1, 0), placement: .standoff)

    func spec(_ socket: SocketName, _ value: Double, component: Int? = nil, count: Int? = nil,
              quantity: DimensionQuantity = .length) -> DimensionSpec {
        DimensionSpec(.input(socket), geometry, quantity, value: value, count: count, component: component)
    }

    func result(_ specs: [DimensionSpec]) -> NodeResult {
        NodeResult(state: .ok(duration: .zero), outputs: [:], dimensions: specs)
    }

    func build(_ graph: Graph, contextual: Set<NodeID> = [], pinned: [DimensionPin] = [],
               results: [NodeID: NodeResult], units: DocumentUnits = .millimetres) -> [FeatureDimension] {
        FeatureDimensionBuilder.dimensions(contextual: contextual, pinned: pinned, graph: graph,
                                           content: GraphContent(graph: graph), results: results,
                                           registry: BuiltInNodes.registry, units: units, style: .ansi)
    }

    @Test func aConstantIsDriving() throws {
        var b = GraphBuilder()
        let (_, extrude) = b.solid(distance: 10)
        let shown = build(b.graph, contextual: [extrude.id], results: [extrude.id: result([spec("distance", 10)])])
        let entry = try #require(shown.first)
        #expect(shown.count == 1 && entry.editing == .driving && !entry.isPinned)
        #expect(entry.overlay.tint == .dimensionDriving && entry.overlay.text == "10" && entry.overlay.id == entry.id)
        #expect(entry.node == extrude.id && entry.spec.value == 10)
    }

    @Test func aParameterWiredInputIsDrivingWithItsUses() throws {
        var b = GraphBuilder()
        let width = GraphParameter(name: "Width", type: .number, value: .number(20))
        b.graph.parameters = [width]
        let reader = b.add(GraphParameterNode.self, [NodeSetting.parameter: .parameter(width.id)])
        let first = b.add(RectangleNode.self)
        let second = b.add(RectangleNode.self)
        let third = b.add(ExtrudeNode.self)
        b.wire(reader, "number", to: first, "width")
        b.wire(reader, "number", to: second, "width")
        b.wire(reader, "number", to: third, "distance")
        let shown = build(b.graph, contextual: [first.id], results: [first.id: result([spec("width", 20)])])
        let entry = try #require(shown.first)
        #expect(entry.editing == .parameter(width.id, name: "Width", uses: 3))
        #expect(entry.overlay.tint == .dimensionDriving && entry.overlay.text == "20")
    }

    @Test func anOtherwiseWiredInputIsAReferenceNamingItsSource() throws {
        var b = GraphBuilder()
        var number = b.add(NumberNode.self, ["value": .number(10)])
        number.name = "width"
        b.replace(number)
        let (_, extrude) = b.solid()
        b.wire(number, "value", to: extrude, "distance")
        let shown = build(b.graph, contextual: [extrude.id], results: [extrude.id: result([spec("distance", 10)])])
        let entry = try #require(shown.first)
        #expect(entry.editing == .reference(source: "from Number “width”"))
        #expect(entry.overlay.tint == .dimensionReference && entry.overlay.text == "(10)")
    }

    @Test func aSourceStillNamedAfterItsTypeIsNamedByTheType() throws {
        var b = GraphBuilder()
        let number = b.add(NumberNode.self)
        let (_, extrude) = b.solid()
        b.wire(number, "value", to: extrude, "distance")
        let shown = build(b.graph, pinned: [DimensionPin(node: extrude.id, target: .input("distance"))],
                          results: [extrude.id: result([spec("distance", 10)])])
        #expect(shown.first?.editing == .reference(source: "from Number"))
    }

    @Test func perInstanceValuesAreReferences() throws {
        var b = GraphBuilder()
        let hole = b.add(HolePatternNode.self)
        let specs = [spec("diameter", 8), spec("diameter", 6)]
        let shown = build(b.graph, contextual: [hole.id], results: [hole.id: result(specs)])
        #expect(shown.count == 2)
        #expect(shown.allSatisfy { $0.editing == .reference(source: nil) && $0.overlay.tint == .dimensionReference })
        #expect(shown.map(\.overlay.text) == ["(8)", "(6)"])

        var wired = GraphBuilder()
        let number = wired.add(NumberNode.self)
        let other = wired.add(HolePatternNode.self)
        wired.wire(number, "value", to: other, "diameter")
        let shownWired = build(wired.graph, contextual: [other.id], results: [other.id: result(specs)])
        #expect(shownWired.map(\.editing) == Array(repeating: .reference(source: "from Number"), count: 2))
    }

    func sketchNode(_ b: inout GraphBuilder) -> (node: Node, width: DimensionID, height: DimensionID) {
        var sketch = Sketch()
        let start = sketch.addPoint(Vector2(0, 0))
        let end = sketch.addPoint(Vector2(60, 0))
        let top = sketch.addPoint(Vector2(0, 40))
        let bottom = sketch.addLine(from: start, to: end)
        let side = sketch.addLine(from: start, to: top)
        let width = sketch.addDimension(.length(bottom), value: 60)
        let height = sketch.addDimension(.length(side), value: 40, isDriving: false)
        sketch.dimensions[width]?.name = "width"
        sketch.dimensions[width]?.isExposed = true
        return (b.add(SketchNode.self, [NodeSetting.sketch: .sketch(sketch)]), width, height)
    }

    @Test func sketchReferenceAndExposedDimensions() throws {
        var b = GraphBuilder()
        let (node, width, height) = sketchNode(&b)
        let specs = [
            DimensionSpec(.sketchDimension(width), geometry, .length, value: 60),
            DimensionSpec(.sketchDimension(height), geometry, .length, value: 40),
        ]
        let shown = build(b.graph, contextual: [node.id], results: [node.id: result(specs)])
        #expect(shown.map(\.overlay.text) == ["width = 60", "(40)"])
        #expect(shown.map(\.editing) == [.driving, .reference(source: nil)])

        let number = b.add(NumberNode.self)
        b.wire(number, "value", to: node, "width")
        let wired = build(b.graph, contextual: [node.id], results: [node.id: result(specs)])
        #expect(wired.first?.editing == .reference(source: "from Number"))
        #expect(wired.first?.overlay.text == "(width = 60)")
    }

    @Test func aPinShowsWithoutSelectionAndOnceWithIt() throws {
        var b = GraphBuilder()
        let (_, extrude) = b.solid()
        let results = [extrude.id: result([spec("distance", 10)])]
        let pin = DimensionPin(node: extrude.id, target: .input("distance"))
        let pinnedOnly = build(b.graph, pinned: [pin], results: results)
        #expect(pinnedOnly.count == 1 && pinnedOnly[0].isPinned && pinnedOnly[0].overlay.isPinned)
        let both = build(b.graph, contextual: [extrude.id], pinned: [pin], results: results)
        #expect(both.count == 1 && both[0].isPinned)
        #expect(build(b.graph, contextual: [extrude.id], results: results)[0].isPinned == false)
    }

    @Test func aDanglingPinShowsNothing() {
        var b = GraphBuilder()
        let (_, extrude) = b.solid()
        let results = [extrude.id: result([spec("distance", 10)])]
        let gone = DimensionPin(node: extrude.id, target: .input("gone"))
        let missingNode = DimensionPin(node: NodeID(), target: .input("distance"))
        #expect(build(b.graph, pinned: [gone, missingNode], results: results).isEmpty)
        #expect(build(b.graph, pinned: [DimensionPin(node: extrude.id, target: .input("distance"))], results: [:]).isEmpty)
    }

    @Test func idsAreStableAndDistinct() throws {
        var b = GraphBuilder()
        let box = b.add(ImplicitBoxNode.self)
        let specs = (0..<3).map { spec("size", Double(10 + $0), component: $0) }
        let shown = build(b.graph, contextual: [box.id], results: [box.id: result(specs)])
        let prefix = "feature/\(box.id.rawValue.uuidString)/input/size"
        #expect(shown.map(\.id.rawValue) == ["\(prefix).0/0", "\(prefix).1/0", "\(prefix).2/0"])
        #expect(shown.allSatisfy { $0.editing == .driving })

        let hole = b.add(HolePatternNode.self)
        let holes = build(b.graph, contextual: [hole.id], results: [hole.id: result([spec("diameter", 8), spec("diameter", 6)])])
        let holePrefix = "feature/\(hole.id.rawValue.uuidString)/input/diameter"
        #expect(holes.map(\.id.rawValue) == ["\(holePrefix)/0", "\(holePrefix)/1"])

        let (sketch, width, _) = sketchNode(&b)
        let sketchSpec = DimensionSpec(.sketchDimension(width), geometry, .length, value: 60)
        let sketchShown = build(b.graph, contextual: [sketch.id], results: [sketch.id: result([sketchSpec])])
        let expected = FeatureDimension.overlayID(node: sketch.id, target: .sketchDimension(width))
        #expect(sketchShown.first?.id == expected)
        #expect(expected.rawValue == "feature/\(sketch.id.rawValue.uuidString)/sketch/\(width.rawValue)/0")
    }

    @Test func theChainsDimensionsFollowTheSelectedFeatures() throws {
        var b = GraphBuilder()
        let (rectangle, extrude) = b.solid()
        let results = [rectangle.id: result([spec("width", 20)]), extrude.id: result([spec("distance", 10)])]
        let shown = build(b.graph, contextual: [extrude.id], results: results)
        #expect(shown.map(\.node) == [extrude.id, rectangle.id])
    }

    @Test func inchesChangeTheText() throws {
        var b = GraphBuilder()
        let (_, extrude) = b.solid()
        let shown = build(b.graph, contextual: [extrude.id], results: [extrude.id: result([spec("distance", 25.4)])],
                          units: DocumentUnits(length: .inches))
        #expect(shown.first?.overlay.text == "1.00")
    }
}
