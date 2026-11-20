import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// NS-5 R14: warned edges are drawn in the theme's warning colour, 2.5 points wide, in every display mode.
struct WarningEdgeTests {
    let mesh = TestMeshes.box(BoundingBox(min: Vector3(-5, -10, 0), max: Vector3(5, 10, 30)))
    let palette = ViewportPalette.dracula

    @Test func warningEdgesTakeTheWarningColour() {
        let instances = GPUGeometry.edgeInstances(mesh.edgePolylines, solid: 0, selected: [EdgeID(2)], selectedOnly: false, scale: 2,
                                                  warning: [EdgeID(1), EdgeID(2)])
        let one = instances.filter { PickID.decode($0.id) == .edge(solid: 0, EdgeID(1)) }
        #expect(!one.isEmpty)
        #expect(one.allSatisfy { $0.color == palette.warning && $0.width == 5 })
        let both = instances.filter { PickID.decode($0.id) == .edge(solid: 0, EdgeID(2)) }
        #expect(both.allSatisfy { $0.color == palette.selection }, "selection wins over warning")
        let plain = instances.filter { PickID.decode($0.id) == .edge(solid: 0, EdgeID(0)) }
        #expect(plain.allSatisfy { $0.color == palette.edge && $0.width == 2.5 })
    }

    @Test func shadedModeStillDrawsWarningEdges() {
        let instances = GPUGeometry.edgeInstances(mesh.edgePolylines, solid: 0, selected: [], selectedOnly: true, scale: 1,
                                                  warning: [EdgeID(1)])
        #expect(!instances.isEmpty)
        #expect(instances.allSatisfy { PickID.decode($0.id) == .edge(solid: 0, EdgeID(1)) })
    }
}
