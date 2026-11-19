import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// "Pick regions in view…" and "Clear regions" on a Trim Surface (NS-4 Task 11, R4): the refusals need no geometry.
@MainActor
struct TrimRegionRefusalTests {
    @Test func insideAGroupIsRefused() async throws {
        var builder = GraphBuilder()
        let box = builder.box()
        let trim = builder.add(TrimSurfaceNode.self)
        let app = await makeApp(builder.graph)
        app.editor.selection = [box.rectangle.id, box.extrude.id, trim.id]
        app.editor.groupSelection()
        let group = try #require(app.editor.selection.first)
        #expect(app.editor.enterGroup(group))
        await app.settle()
        app.beginTrimRegionPick(for: trim.id)
        #expect(app.pick == nil)
        #expect(app.alert?.message == "A region can't be picked inside a group yet. Pick it from the top level.")
    }

    @Test func noPiecesRefuses() async throws {
        var builder = GraphBuilder()
        let trim = builder.add(TrimSurfaceNode.self)
        let app = await makeApp(builder.graph)
        app.beginTrimRegionPick(for: trim.id)
        #expect(app.pick == nil)
        #expect(app.alert?.message == "“Trim Surface” has no pieces to pick yet: wire a sheet and a cutter first.")
    }

    @Test func refusedWhileEditingControlPoints() async throws {
        var builder = GraphBuilder()
        let trim = builder.add(TrimSurfaceNode.self)
        let app = await makeApp(builder.graph)
        app.controlNet = ControlNetSession(node: NodeID(), kind: .surface, events: .init())
        app.beginTrimRegionPick(for: trim.id)
        #expect(app.pick == nil && app.alert == nil)
    }

    @Test func theBannerCountsPieces() {
        #expect(PickSession.Prompt.trimRegions.text(picked: 2) == "Click the regions to keep · 2 picked")
    }
}

#if canImport(CreatorOCCT)
import CreatorOCCT

/// A 20 x 10 x 10 tube (Extrude Curve of a rectangle: four faces) cut by the plane x = 0: two pieces of three faces.
@MainActor
struct TrimRegionPickTests {
    struct Setup {
        var app: AppModel
        var trim: Node
        var output: Node
        var tube: Node
        var wall: Node
    }

    func open() async -> Setup {
        var builder = GraphBuilder()
        let rectangle = builder.add(RectangleNode.self, ["width": .number(20), "height": .number(10)])
        let curves = builder.add(ProfileToCurvesNode.self)
        let tube = builder.add(ExtrudeCurveNode.self, ["distance": .number(10)])
        let wallRectangle = builder.add(RectangleNode.self, ["width": .number(80), "height": .number(60), "plane": .plane(.yz)])
        let wall = builder.add(PlanarSurfaceNode.self)
        let trim = builder.add(TrimSurfaceNode.self)
        let output = builder.add(OutputNode.self)
        builder.wire(rectangle, "profile", to: curves, "profile")
        builder.wire(curves, "curves", to: tube, "curve")
        builder.wire(wallRectangle, "profile", to: wall, "curves")
        builder.wire(tube, "surface", to: trim, "surface")
        builder.wire(wall, "surface", to: trim, "cutter")
        builder.wire(trim, "surface", to: output, "solid")
        let app = await makeApp(builder.graph, kernel: OCCTKernel())
        return Setup(app: app, trim: trim, output: output, tube: tube, wall: wall)
    }

    func whole(_ setup: Setup) throws -> Solid {
        try #require(solids(setup.app, setup.trim, "pieces").first)
    }

    /// The faces of the whole split on one side of the cut.
    func faces(_ whole: Solid, left: Bool) -> [FaceID] {
        whole.topology.faces.filter { ($0.centroid.x < 0) == left }.map(\.id)
    }

    func begin(_ setup: Setup) async {
        setup.app.beginTrimRegionPick(for: setup.trim.id)
        await setup.app.settle()
    }

    @Test func piecesMatchTheKernelsSplit() async throws {
        let setup = await open()
        let whole = try whole(setup)
        let pieces = TrimRegions.pieces(of: whole)
        #expect(pieces.count == 2 && pieces.allSatisfy { $0.count == 3 })
        let sides = pieces.map { Set($0.map { whole.topology.faces[$0.rawValue].centroid.x < 0 }) }
        #expect(sides.allSatisfy { $0.count == 1 })
        let sheet = try #require(solids(setup.app, setup.tube, "surface").first)
        let wall = try #require(solids(setup.app, setup.wall, "surface").first)
        let split = try await OCCTKernel().split(sheet, by: .body(wall), tag: NodeTag(node: NodeID(), item: 0))
        #expect(split.pieces.count == 2)
        #expect(TrimRegions.pieces(of: split.whole) == split.pieces, "the same partition in the same order")
    }

    @Test func pickRegionsShowsTheWholeSplit() async throws {
        let setup = await open()
        await begin(setup)
        let app = setup.app
        let session = try #require(app.pick, "\(String(describing: app.alert?.message))")
        let whole = try whole(setup)
        #expect(session.solid === whole && session.trimRegions == setup.trim.id && session.pickedPieces.isEmpty)
        #expect(app.viewport.items.count == 1 && app.viewport.items.first?.solid === whole, "the pieces sheet alone")
        #expect(session.prompt == .trimRegions)
    }

    @Test func pickRegionsStartsFromTheKeptPieces() async throws {
        let setup = await open()
        let app = setup.app
        let first = try whole(setup)
        let leftFace = try #require(faces(first, left: true).first)
        let pick = try #require(first.topology.facePick(for: leftFace))
        try app.document.perform(.setInput(setup.trim.id, NodeSetting.keepRegions, .regionPicks([RegionPick(pick: pick)])),
                                 name: UndoName.pickTrimRegions)
        await app.settle()
        await begin(setup)
        let session = try #require(app.pick)
        #expect(session.pickedPieces.count == 1)
        #expect(Set(app.viewport.items.first?.selectedFaces ?? []) == Set(faces(try whole(setup), left: true)),
                "all of a piece's faces show selected")
    }

    @Test func clickingTogglesARegion() async throws {
        let setup = await open()
        await begin(setup)
        let app = setup.app
        let whole = try whole(setup)
        let right = try #require(faces(whole, left: false).first)
        app.viewportClicked(.face(solid: 0, right))
        #expect(app.pick?.pickedPieces.count == 1)
        app.viewportClicked(.edge(solid: 0, EdgeID(0)))
        app.viewportClicked(nil)
        #expect(app.pick?.pickedPieces.count == 1, "an edge or empty space does nothing")
        app.viewportClicked(.face(solid: 0, right))
        #expect(app.pick?.pickedPieces.isEmpty == true)
    }

    @Test func clickingTogglesAWholePiece() async throws {
        let setup = await open()
        await begin(setup)
        let app = setup.app
        let whole = try whole(setup)
        let left = faces(whole, left: true)
        app.viewportClicked(.face(solid: 0, left[0]))
        await app.settle()
        #expect(app.pick?.selectedFaces == Set(left), "one click selects every face of its piece")
        #expect(app.viewport.items.first?.selectedFaces == Set(left))
        app.viewportClicked(.face(solid: 0, left[2]))
        #expect(app.pick?.selectedFaces.isEmpty == true, "a click on its other face clears both")
        app.viewportClicked(.face(solid: 0, left[1]))
        app.finishPick()
        let picks = try #require(app.document.graph.nodes[setup.trim.id]?.inputValues[NodeSetting.keepRegions]?.regionPicks)
        #expect(picks.count == 1, "Done writes one pick for the piece")
    }

    @Test func doneWritesFacePicksAsOneStep() async throws {
        let setup = await open()
        await begin(setup)
        let app = setup.app
        let whole = try whole(setup)
        app.viewportClicked(.face(solid: 0, try #require(faces(whole, left: false).first)))
        app.finishPick()
        await app.settle()
        #expect(app.pick == nil && app.editor.selection == [setup.trim.id])
        #expect(app.document.undoName == "Pick Trim Regions")
        let picks = try #require(app.document.graph.nodes[setup.trim.id]?.inputValues[NodeSetting.keepRegions]?.regionPicks)
        #expect(picks.count == 1)
        let kept = try #require(solids(app, setup.trim, "surface").first)
        #expect(kept.topology.faces.count == 3 && kept.topology.faces.allSatisfy { $0.centroid.x > 0 }, "the kept area follows")
        app.document.undo()
        #expect(app.document.graph.nodes[setup.trim.id]?.inputValues[NodeSetting.keepRegions] == .regionPicks([]))
    }

    @Test func cancelLeavesTheGraph() async throws {
        let setup = await open()
        await begin(setup)
        let app = setup.app
        let before = app.document.content
        app.viewportClicked(.face(solid: 0, try #require(faces(try whole(setup), left: true).first)))
        app.cancelPick()
        #expect(app.pick == nil && app.document.content == before)
    }

    @Test func clearRegionsIsOneStep() async throws {
        let setup = await open()
        await begin(setup)
        let app = setup.app
        app.viewportClicked(.face(solid: 0, try #require(faces(try whole(setup), left: true).first)))
        app.finishPick()
        await app.settle()
        app.clearTrimRegions(of: setup.trim.id)
        await app.settle()
        #expect(app.document.graph.nodes[setup.trim.id]?.inputValues[NodeSetting.keepRegions] == .regionPicks([]))
        #expect(app.document.undoName == "Clear Trim Regions")
        app.document.undo()
        #expect(app.document.graph.nodes[setup.trim.id]?.inputValues[NodeSetting.keepRegions]?.regionPicks?.count == 1)
    }

    @Test func pickingAgainAfterEveryPickVanished() async throws {
        let setup = await open()
        let gone = RegionPick(pick: FacePick(tags: [TopoTag(node: NodeID(), item: 0, role: .startCap)]))
        try setup.app.document.perform(.setInput(setup.trim.id, NodeSetting.keepRegions, .regionPicks([gone])),
                                       at: setup.app.editor.graphPath, name: UndoName.pickTrimRegions)
        await setup.app.settle()
        #expect(setup.app.editor.result(of: setup.trim.id)?.state.isSuccess == false)
        await begin(setup)
        let session = try #require(setup.app.pick)
        #expect(session.trimRegions == setup.trim.id)
        #expect(session.pieces.count == 2 && session.pickedPieces.isEmpty)
        #expect(setup.app.alert == nil)
    }

    @Test func aFailedTrimRefusesInItsOwnWords() async throws {
        let setup = await open()
        let link = try #require(setup.app.document.graph.links.first { $0.to == Endpoint(node: setup.trim.id, socket: "cutter") })
        try setup.app.document.perform(.disconnect(link), name: UndoName.changeParameter)
        await setup.app.settle()
        await begin(setup)
        #expect(setup.app.pick == nil)
        let message = try #require(setup.app.alert?.message)
        #expect(!message.contains("wire a sheet and a cutter first"), "\(message)")
    }

    @Test func piecesAreNotDrawnInPreview() async throws {
        let setup = await open()
        let app = setup.app
        app.previewMode = .selectedNode
        app.editor.selection = [setup.trim.id]
        await app.settle()
        #expect(app.viewport.items.count == 1, "the kept surface alone")
        let kept = try #require(solids(app, setup.trim, "surface").first)
        #expect(app.viewport.items.first?.solid === kept)
    }
}
#endif
