import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

struct CanvasGeometryTests {
    @Test func screenAndCanvasRoundTrip() {
        let transform = CanvasTransform(offset: Vector2(30, -12), zoom: 2)
        let point = Vector2(7, 9)
        #expect(transform.toScreen(point) == Vector2(44, 6))
        #expect(transform.toCanvas(transform.toScreen(point)) == point)
    }

    @Test func zoomKeepsThePointUnderTheAnchorStill() {
        let transform = CanvasTransform(offset: Vector2(10, 20), zoom: 1)
        let anchor = Vector2(100, 50)
        let before = transform.toCanvas(anchor)
        let zoomed = transform.zoomed(by: 1.25, around: anchor)
        #expect(zoomed.zoom == 1.25)
        let after = zoomed.toCanvas(anchor)
        #expect(abs(after.x - before.x) < 1e-9 && abs(after.y - before.y) < 1e-9)
    }

    @Test func zoomIsClampedAndNonFiniteFactorsAreIgnored() {
        #expect(CanvasTransform(zoom: 100).zoom == CanvasTransform.zoomRange.upperBound)
        #expect(CanvasTransform(zoom: 0.001).zoom == CanvasTransform.zoomRange.lowerBound)
        #expect(CanvasTransform(zoom: .nan).zoom == 1)
        let transform = CanvasTransform(offset: Vector2(1, 2), zoom: 1.5)
        #expect(transform.zoomed(by: .infinity, around: .zero) == transform)
        #expect(transform.zoomed(by: 0, around: .zero) == transform)
    }

    @Test func leftDockTransposesAndSwitchingIsLossless() {
        let stored = Vector2(120, -35.5)
        #expect(CanvasFlow(.left).display(stored) == Vector2(-35.5, 120))
        #expect(CanvasFlow(.bottom).display(stored) == stored)
        #expect(CanvasFlow(.hidden) == .vertical)
        for flow in [CanvasFlow.horizontal, .vertical] {
            #expect(flow.stored(flow.display(stored)) == stored)
        }
    }

    @Test func horizontalSocketsSitOnTheSideEdgesBesideTheirRows() {
        let shape = NodeShape(title: "Add", category: .value,
                              inputs: [.init(name: "a", type: .number), .init(name: "b", type: .number)],
                              outputs: [.init(name: "sum", type: .number)])
        #expect(NodeLayout.size(shape) == Vector2(168, 24 + 12 + 60))
        #expect(NodeLayout.socketOffset("a", isInput: true, in: shape, flow: .horizontal) == Vector2(0, 40))
        #expect(NodeLayout.socketOffset("b", isInput: true, in: shape, flow: .horizontal) == Vector2(0, 60))
        #expect(NodeLayout.socketOffset("sum", isInput: false, in: shape, flow: .horizontal) == Vector2(168, 80))
        #expect(NodeLayout.socketOffset("sum", isInput: true, in: shape, flow: .horizontal) == nil)
    }

    @Test func verticalSocketsSpreadAlongTheTopAndBottomEdges() {
        let shape = NodeShape(title: "Add", category: .value,
                              inputs: [.init(name: "a", type: .number), .init(name: "b", type: .number)],
                              outputs: [.init(name: "sum", type: .number)])
        #expect(NodeLayout.socketOffset("a", isInput: true, in: shape, flow: .vertical) == Vector2(56, 0))
        #expect(NodeLayout.socketOffset("b", isInput: true, in: shape, flow: .vertical) == Vector2(112, 0))
        #expect(NodeLayout.socketOffset("sum", isInput: false, in: shape, flow: .vertical) == Vector2(84, 96))
    }

    @Test func rectsFromCornersInAnyOrder() {
        let rect = CanvasRect(corner: Vector2(10, 40), Vector2(-5, 0))
        #expect(rect == CanvasRect(origin: Vector2(-5, 0), size: Vector2(15, 40)))
        #expect(rect.contains(Vector2(0, 20)))
        #expect(!rect.contains(Vector2(11, 20)))
        #expect(rect.intersects(CanvasRect(origin: Vector2(10, 40), size: Vector2(5, 5))))
        #expect(!rect.intersects(CanvasRect(origin: Vector2(11, 0), size: Vector2(5, 5))))
    }

    @Test func missingNodesKeepTheSocketsTheirWiresName() {
        let known = testNode(NumberTestNode.self, id: 1, at: .zero)
        var missing = Node(id: nodeID(2), typeID: "plugin.gone", name: "Gone")
        missing.position = Vector2(200, 0)
        let graph = Graph(nodes: [known.id: known, missing.id: missing],
                          links: [wire(known, "value", missing, "input")])
        let shape = NodeShape(missing, in: graph, registry: editorTestRegistry)
        #expect(shape.isMissing)
        #expect(shape.inputs == [.init(name: "input", type: nil)])
        #expect(shape.outputs.isEmpty)
    }
}
