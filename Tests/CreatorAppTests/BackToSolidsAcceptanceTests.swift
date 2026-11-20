import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Foundation
import Testing
@testable import CreatorApp
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

#if canImport(CreatorOCCT)
/// NS-5 Task 10: back to solids end to end, through the app over OCCT: a loose-face model sews, fillets and exports; a lofted
/// tube caps and is sectioned; a thickened plate takes a hole; a split piece feeds a Boolean; and a Thicken inside a group
/// names each instance's own faces.
@MainActor
struct BackToSolidsAcceptanceTests {
    let kernel = OCCTKernel()

    func volume(_ solid: Solid) async throws -> Double { try await kernel.properties(of: solid).volume }

    func exportAll(_ app: AppModel, name: String) async throws {
        for kind in [ExportKind.step, .stl, .threeMF] {
            let url = temporaryURL("\(name).\(kind.rawValue)")
            defer { try? FileManager.default.removeItem(at: url) }
            _ = try await app.exportReturningWarnings(kind, to: url)
            let size = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
            #expect(size > 0, "\(kind.title) wrote nothing")
        }
    }

    @Test func anImportedLooseBoxSewsAndExports() async throws {
        let data = try OCCTKernel.looseBoxFaces(size: 10, movingTopBy: 0, doublingTop: false)
        let hash = ImageHash(of: data)
        var builder = GraphBuilder()
        let model = builder.add(ImportModelNode.self, [NodeSetting.modelFile: .modelFile(.embedded(hash))])
        let thicken = builder.add(ThickenNode.self)
        let sew = builder.add(SewNode.self)
        let rule = builder.add(EdgesByTagNode.self)
        let fillet = builder.add(FilletNode.self, ["radius": .number(1)])
        let output = builder.add(OutputNode.self)
        let probe = builder.add(OutputNode.self)
        builder.wire(model, "sheets", to: thicken, "surface")
        builder.wire(thicken, "solid", to: probe, "solid")
        builder.wire(model, "sheets", to: sew, "bodies")
        builder.wire(sew, "solid", to: rule, "solid")
        builder.wire(rule, "edges", to: fillet, "edges")
        builder.wire(fillet, "solid", to: output, "solid")
        let app = AppModel(kernel: kernel, file: GraphFile(graph: builder.graph, images: [hash: data]))
        await app.settle()

        // The precondition (R19): one sheet of six loose faces with 24 boundary edges, so Thicken refuses.
        let sheets = solids(app, model, "sheets")
        try #require(sheets.count == 1)
        #expect(sheets[0].topology.faces.count == 6 && sheets[0].topology.edges.filter(\.isBoundary).count == 24)
        #expect(app.document.results[thicken.id]?.state == .error(OCCTKernel.touchingSentence))

        try app.document.perform(.setOutput(probe.id, false))
        await app.settle()
        let sewn = try #require(solids(app, sew).first)
        #expect(!sewn.hasOpenShell)
        let sewnVolume = try await volume(sewn)
        #expect(abs(sewnVolume - 1000) < 1e-3)

        let edge = try #require(sewn.topology.edges.first { !$0.isBoundary && !$0.isSeam })
        try app.document.perform(.setInput(rule.id, NodeSetting.picks, .edgePicks(sewn.topology.picks(for: [edge.id]))))
        await app.settle()
        #expect(app.document.results[fillet.id]?.state.isSuccess == true, "\(String(describing: app.document.results[fillet.id]?.state))")
        let rounded = try #require(solids(app, fillet).first)
        let roundedVolume = try await volume(rounded)
        #expect(abs(roundedVolume - (1000 - 10 * (1 - Double.pi / 4))) < 1e-2)
        #expect(app.document.results[output.id]?.state.isSuccess == true)
        try await exportAll(app, name: "loose-box")
    }

    @Test func aLoftCappedAndSectioned() async throws {
        var builder = GraphBuilder()
        let merge = builder.add(MergeNode.self)
        for (index, (z, diameter)) in [(0.0, 20.0), (20.0, 12.0)].enumerated() {
            let circle = builder.add(CircleNode.self, ["diameter": .number(diameter), "plane": .plane(.through(Vector3(0, 0, z)))])
            builder.wire(circle, "profile", to: merge, ["a", "b"][index])
        }
        let loft = builder.add(LoftSurfaceNode.self)
        let cap = builder.add(CapPlanarHolesNode.self)
        let output = builder.add(OutputNode.self)
        builder.wire(merge, "list", to: loft, "sections")
        builder.wire(loft, "surface", to: cap, "surface")
        builder.wire(cap, "solid", to: output, "solid")
        let app = await makeApp(builder.graph, kernel: kernel)
        #expect(app.document.results[cap.id]?.state.isSuccess == true, "\(String(describing: app.document.results[cap.id]?.state))")
        let solid = try #require(solids(app, cap).first)
        #expect(!solid.hasOpenShell)
        let frustum = Double.pi * 20 * (100 + 60 + 36) / 3
        let frustumVolume = try await volume(solid)
        #expect(abs(frustumVolume - frustum) / frustum < 1e-4)

        let shown = try #require(app.viewport.items.first { !$0.isGuide }).solid
        let model = SectionCapModel(kernel: kernel, tolerance: 0.05)
        model.follow(clip: ViewportClip(origin: Vector3(0, 0, 10), normal: .unitZ), items: [ViewportItem(solid: shown)])
        await model.waitForCaps()
        #expect(model.problem == nil)
        #expect(model.section?.caps.count == 1, "the section caps the lofted solid like any other")
    }

    @Test func aThickenedPlateMinusAHole() async throws {
        var builder = GraphBuilder()
        let rectangle = builder.add(RectangleNode.self, ["width": .number(20), "height": .number(30)])
        let surface = builder.add(PlanarSurfaceNode.self)
        let thicken = builder.add(ThickenNode.self, ["distance": .number(5)])
        let circle = builder.add(CircleNode.self, ["diameter": .number(6), "plane": .plane(.through(Vector3(0, 0, -10)))])
        let hole = builder.add(ExtrudeNode.self, ["distance": .number(30)])
        let boolean = builder.add(BooleanNode.self, ["operation": .integer(1)])
        let output = builder.add(OutputNode.self)
        builder.wire(rectangle, "profile", to: surface, "curves")
        builder.wire(surface, "surface", to: thicken, "surface")
        builder.wire(circle, "profile", to: hole, "profile")
        builder.wire(thicken, "solid", to: boolean, "target")
        builder.wire(hole, "solid", to: boolean, "tools")
        builder.wire(boolean, "solid", to: output, "solid")
        let app = await makeApp(builder.graph, kernel: kernel)
        #expect(app.document.results[boolean.id]?.state.isSuccess == true, "\(String(describing: app.document.results[boolean.id]?.state))")
        let plate = try #require(solids(app, boolean).first)
        let expected = 20 * 30 * 5 - Double.pi * 9 * 5
        let plateVolume = try await volume(plate)
        #expect(abs(plateVolume - expected) / expected < 1e-6)
        #expect(!plate.hasOpenShell)
    }

    @Test func splitSolidPiecesFeedBoolean() async throws {
        var builder = GraphBuilder()
        let (_, part) = builder.solid(distance: 10)
        let cutterRectangle = builder.add(RectangleNode.self, ["width": .number(30), "height": .number(30),
                                                               "plane": .plane(.through(Vector3(0, 0, 5))),
        ])
        let cutter = builder.add(PlanarSurfaceNode.self)
        let split = builder.add(SplitSolidNode.self)
        let pick = builder.add(ListItemNode.self, ["index": .integer(0)])
        let post = builder.add(RectangleNode.self, ["width": .number(4), "height": .number(4),
                                                    "plane": .plane(.through(Vector3(0, 0, -5))),
        ])
        let postSolid = builder.add(ExtrudeNode.self, ["distance": .number(20)])
        let union = builder.add(BooleanNode.self, ["operation": .integer(0)])
        let output = builder.add(OutputNode.self)
        builder.wire(cutterRectangle, "profile", to: cutter, "curves")
        builder.wire(part, "solid", to: split, "solid")
        builder.wire(cutter, "surface", to: split, "tools")
        builder.wire(split, "solids", to: pick, "tree")
        builder.wire(post, "profile", to: postSolid, "profile")
        builder.wire(pick, "item", to: union, "target")
        builder.wire(postSolid, "solid", to: union, "tools")
        builder.wire(union, "solid", to: output, "solid")
        let app = await makeApp(builder.graph, kernel: kernel)
        let pieces = solids(app, split, "solids")
        #expect(pieces.count == 2, "\(String(describing: app.document.results[split.id]?.state))")
        #expect(app.document.results[union.id]?.state.isSuccess == true, "\(String(describing: app.document.results[union.id]?.state))")
        let result = try #require(solids(app, union).first)
        // One half of the 20 x 10 x 10 box (1000) and a 4 x 4 post through it, 5 mm of the post inside the half.
        let unionVolume = try await volume(result)
        #expect(abs(unionVolume - (1000 + 320 - 80)) < 1e-6)
    }

    @Test func aThickenInsideAGroupNamesEachInstance() async throws {
        var builder = GraphBuilder()
        let rectangle = builder.add(RectangleNode.self)
        let surface = builder.add(PlanarSurfaceNode.self)
        let thicken = builder.add(ThickenNode.self, ["distance": .number(2)])
        let plane = builder.add(PlaneFromFaceNode.self)
        builder.wire(rectangle, "profile", to: surface, "curves")
        builder.wire(surface, "surface", to: thicken, "surface")
        builder.wire(thicken, "solid", to: plane, "solid")
        let app = await makeApp(builder.graph, kernel: kernel)
        try app.document.perform(.setOutput(plane.id, true))
        await app.settle()
        // A pick on the thickened plate's end face, made at the top level and renamed by Group.
        let plate = try #require(solids(app, thicken).first)
        let end = try #require(plate.topology.faces.first(where: endsFace))
        try app.document.perform(.setInput(plane.id, NodeSetting.face, .facePick(try #require(plate.topology.facePick(for: end.id)))))
        await app.settle()
        #expect(duration(app, plane) != nil, "the pick resolves at the top level without a warning")
        try app.document.perform(.setOutput(plane.id, false))
        app.editor.selection = [rectangle.id, surface.id, thicken.id, plane.id]
        app.editor.groupSelection()
        let first = try #require(app.editor.selection.first)
        app.editor.perform(.duplicate)
        let second = try #require(app.editor.selection.first)

        let definition = try #require(app.document.definitions.values.first)
        let innerPlane = try #require(definition.graph.nodes.values.first { $0.typeID == PlaneFromFaceNode.typeID }).id
        let innerThicken = try #require(definition.graph.nodes.values.first { $0.typeID == ThickenNode.typeID }).id
        var endTags: [Set<TopoTag>] = []
        for instance in [first, second] {
            // A level that is open is evaluated whole, so each instance is entered in turn.
            app.editor.goToLevel(0)
            app.editor.enterGroup(instance)
            await app.settle()
            let result = try #require(app.document.innerResults[[instance, innerPlane]])
            #expect(result.state.isSuccess, "\(result.state)")
            if case .warning(let text) = result.state { Issue.record("a pick that follows its instance warned: \(text)") }
            let items = app.document.innerResults[[instance, innerThicken]]?.outputs?["solid"]?.items ?? []
            let innerSolids = items.compactMap { (scalar: Scalar) -> Solid? in if case .solid(let solid) = scalar { solid } else { nil } }
            let inner = try #require(innerSolids.first)
            let face = try #require(inner.topology.faces.first(where: endsFace))
            guard case .plane(let placed)? = result.outputs?["plane"]?.items.first else {
                Issue.record("the instance's plane output is missing")
                return
            }
            #expect((placed.origin - face.centroid).length < 1e-6, "the plane sits on this instance's own end face")
            endTags.append(Set(face.tags))
        }
        #expect(endTags[0] != endTags[1], "each instance names its own faces")
    }

    func endsFace(_ face: FaceInfo) -> Bool { face.tags.contains { (tag: TopoTag) in tag.role == .endCap } }

    func duration(_ app: AppModel, _ node: Node) -> Duration? {
        if case .ok(let duration)? = app.document.results[node.id]?.state { duration } else { nil }
    }
}
#endif
