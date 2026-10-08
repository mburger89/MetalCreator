import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorViewport

@MainActor
struct ContextMenuTests {
    let size = ViewportSize(width: 400, height: 300)

    func model(
        showing solids: [Solid],
        pose: CameraPose = CameraPose(target: .zero, distance: 100, yaw: 0.6, pitch: 0.4)
    ) async -> ViewportModel {
        let model = ViewportModel(kernel: StubMeshKernel(), pose: pose, clock: ManualClock())
        model.viewSize = size
        model.show(solids.map { ViewportItem(solid: $0) })
        await model.waitForMeshes()
        return model
    }

    @Test func aFaceOffersLookAtSelectEdgesAndItsProducingNode() async throws {
        let node = NodeID()
        let model = await model(showing: [try await fakeBox(node: node)])
        model.pick = { _ in .face(solid: 0, FaceID(2)) }
        model.pointerHovered(at: ScreenPoint(300, 200))
        let ref = ViewportFaceRef(solidIndex: 0, face: FaceID(2))
        #expect(model.contextMenuItems() == [.lookAt(ref), .selectEdgesOfFace(ref),
                                             .showProducingNode(node, title: "Show Producing Node"),
        ])
        #expect(model.contextMenuItems().map(\.title) == ["Look At", "Select Edges of Face", "Show Producing Node"])
    }

    @Test func nothingUnderThePointerMeansNoMenu() async throws {
        let model = await model(showing: [try await fakeBox()])
        model.pointerHovered(at: ScreenPoint(300, 200))
        #expect(model.contextMenuItems().isEmpty)
        model.pick = { _ in .face(solid: 7, FaceID(0)) }
        model.pointerHovered(at: ScreenPoint(301, 200))
        #expect(model.contextMenuItems().isEmpty, "a stale pick of a solid that is gone opens nothing")
    }

    @Test func movingTheCameraUnderAStillPointerRepicks() async throws {
        let model = await model(showing: [try await fakeBox()])
        var underPointer: PickTarget? = .face(solid: 0, FaceID(2))
        model.pick = { _ in underPointer }
        model.pointerHovered(at: ScreenPoint(300, 200))
        #expect(model.contextMenuItems().first == .lookAt(ViewportFaceRef(solidIndex: 0, face: FaceID(2))))

        // An orbit drag, with no hover events while it runs: the release re-picks where the pointer is.
        underPointer = .face(solid: 0, FaceID(3))
        model.pointerDown(at: ScreenPoint(300, 200), modifiers: [])
        model.pointerDragged(to: ScreenPoint(340, 180))
        #expect(model.hovered == .face(solid: 0, FaceID(2)), "nothing is picked during a drag")
        model.pointerUp(at: ScreenPoint(340, 180))
        #expect(model.hovered == .face(solid: 0, FaceID(3)))
        #expect(model.contextMenuItems().first == .lookAt(ViewportFaceRef(solidIndex: 0, face: FaceID(3))))

        // A key zoom and a projection switch move the camera under a still pointer.
        underPointer = nil
        model.performKey(.zoomIn)
        #expect(model.contextMenuItems().isEmpty, "the face that was under the pointer has moved away")
        underPointer = .face(solid: 0, FaceID(1))
        model.perform(.projection(.orthographic))
        #expect(model.hovered == .face(solid: 0, FaceID(1)))

        // An animation re-picks when it ends.
        var picks = 0
        model.pick = { _ in picks += 1; return underPointer }
        underPointer = .face(solid: 0, FaceID(4))
        model.perform(.view(.top))
        #expect(model.isAnimating)
        model.pointerHovered(at: ScreenPoint(300, 200))
        model.pointerHovered(at: ScreenPoint(301, 200))
        #expect(picks == 0, "no GPU pick while the camera animates")
        #expect(model.hovered == .face(solid: 0, FaceID(1)), "the hover is left as it was")
        await model.waitForAnimation()
        #expect(picks == 1, "exactly one pick when the animation ends")
        #expect(model.hovered == .face(solid: 0, FaceID(4)))
        #expect(model.contextMenuItems().first == .lookAt(ViewportFaceRef(solidIndex: 0, face: FaceID(4))))
    }

    @Test func anEdgeUnderThePointerOffersItsFirstFace() async throws {
        let model = await model(showing: [try await fakeBox()])
        model.pick = { _ in .edge(solid: 0, EdgeID(8)) }
        model.pointerHovered(at: ScreenPoint(300, 200))
        #expect(model.hoveredFaceRef() == ViewportFaceRef(solidIndex: 0, face: FaceID(2)))
    }

    @Test func selectEdgesOfFaceReportsTheBoundaryKeys() async throws {
        let box = try await fakeBox()
        let model = await model(showing: [box])
        var reportedFace: ViewportFaceRef?
        var reportedPicks: [EdgePick]?
        var reportedEdges: [EdgeID]?
        model.events.selectEdgesOfFace = { reportedFace = $0; reportedPicks = $1; reportedEdges = $2 }
        let ref = ViewportFaceRef(solidIndex: 0, face: FaceID(2))
        model.choose(.selectEdgesOfFace(ref))
        let face = try #require(reportedFace)
        let picks = try #require(reportedPicks)
        let edges = try #require(reportedEdges)
        #expect(face == ref)
        #expect(edges.map(\.rawValue) == [0, 1, 8, 11])
        // The picks are M3's encoding (`Topology.picks(for:)`), one per distinct boundary key.
        #expect(picks == box.topology.picks(for: edges))
        let expected = edges.compactMap { id in box.topology.edge(id).flatMap(box.topology.key(of:)) }
        #expect(expected.count == 4)
        #expect(Set(picks.map(\.key)) == Set(expected))
    }

    @Test func showProducingNodeNamesEveryNodeOnAMergedFace() async throws {
        let nodeA = NodeID()
        let nodeB = NodeID()
        let merged = FaceInfo(id: FaceID(0), kind: .plane, normal: .unitZ, area: 1, centroid: .zero,
                              tags: [TopoTag(node: nodeA, item: 0, role: .endCap),
                                     TopoTag(node: nodeB, item: 0, role: .startCap),
                              ])
        let solid = Solid(topology: Topology(faces: [merged], edges: []),
                          bounds: BoundingBox(min: .zero, max: Vector3(1, 1, 1)), storage: TestStorage())
        let model = await model(showing: [solid])
        model.events.nodeName = { $0 == nodeA ? "Extrude" : nil }
        model.pick = { _ in .face(solid: 0, FaceID(0)) }
        model.pointerHovered(at: ScreenPoint(300, 200))
        let titles = model.contextMenuItems().map(\.title)
        let sorted = [nodeA, nodeB].sorted()
        let expected = sorted.map {
            $0 == nodeA ? "Show Producing Node (Extrude)" : "Show Producing Node (\(nodeB.description))"
        }
        #expect(Array(titles.dropFirst(2)) == expected)
        var shown: [NodeID] = []
        model.events.showProducingNode = { shown.append($0) }
        for item in model.contextMenuItems().dropFirst(2) { model.choose(item) }
        #expect(shown == sorted)
    }

    @Test func lookAtFacesTheFaceOrthographicAndFramesIt() async throws {
        // An 80 mm wide part whose right face is only 20 × 30: framing the face is much tighter than the part.
        let model = await model(showing: [try await fakeBox(width: 80)])
        model.choose(.lookAt(ViewportFaceRef(solidIndex: 0, face: FaceID(3))))
        #expect(model.isAnimating)
        await model.waitForAnimation()
        #expect(model.pose.projection == .orthographic)
        #expect(isClose(model.pose.toEye, .unitX), "the right face looks along +X")
        #expect(isClose(model.pose.target, Vector3(40, 0, 15)), "framed on the face's centre")
        #expect(model.pose.visibleHeight < 60, "framed on the face (about 42 mm), not the part (about 100 mm)")
    }

    @Test func lookAtAFaceThatDoesNotExistDoesNothing() async throws {
        let model = await model(showing: [try await fakeBox()])
        let before = model.pose
        model.choose(.lookAt(ViewportFaceRef(solidIndex: 0, face: FaceID(42))))
        model.choose(.lookAt(ViewportFaceRef(solidIndex: 3, face: FaceID(0))))
        #expect(model.pose == before)
        #expect(!model.isAnimating)
    }

    @Test func labelsForHandlesTriadAndGrid() async throws {
        let front = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0, pitch: 0,
                               projection: .orthographic)
        let model = await model(showing: [], pose: front)
        model.showHandles([ViewportHandle(id: "r", anchor: .zero, direction: .unitZ, value: 3, range: 0...10,
                                          style: .radial, tint: .feature),
                           ViewportHandle(id: "d", anchor: .zero, direction: .unitZ, value: 12.5, range: 0...50,
                                          style: .linear, tint: .solid),
        ])
        let labels = model.handleLabels()
        #expect(labels.map(\.text) == ["R 3 mm", "12.5 mm"])
        // The 3 mm knob is 22.5 points above the centre of a 300-point-tall, 40 mm view.
        #expect(isClose(labels[0].position, ScreenPoint(200 + 14, 150 - 22.5 - 14)))
        #expect(model.triadLabels().map(\.text) == ["X", "Z"])
        #expect(model.gridLabel == "mm · grid 10 mm", "0.13 mm per point: 1 mm lines would be 7.5 points apart")
        model.perform(.view(.top))
        #expect(model.triadLabels().isEmpty && model.handleLabels().isEmpty,
                "overlay labels can't follow a running animation, so they're hidden (the cube's are painted on it)")
    }
}
