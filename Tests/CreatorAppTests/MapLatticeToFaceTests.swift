import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// "Pick Face in View…" on a lattice node (implicit spec §3.5): the viewport shows the solid the node's region was baked from, and a
/// click on one of its faces sets the node to Face mapping on it, as one undo step.
@MainActor
struct MapLatticeToFaceTests {
    struct Setup {
        var app: AppModel
        var lattice: Node
        var extrude: Node
    }

    /// A box on xy → To Implicit → TPMS → Mesh → Output, so the lattice is evaluated: the box's top is face 1.
    func open() async -> Setup {
        var builder = GraphBuilder()
        let (_, extrude) = builder.solid()
        let implicit = builder.add(ToImplicitNode.self)
        let lattice = builder.add(TPMSNode.self)
        let mesh = builder.add(MeshNode.self)
        let output = builder.add(OutputNode.self)
        builder.wire(extrude, "solid", to: implicit, "solid")
        builder.wire(implicit, "implicit", to: lattice, "region")
        builder.wire(lattice, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        let app = await makeApp(builder.graph)
        return Setup(app: app, lattice: lattice, extrude: extrude)
    }

    @Test func theInspectorsButtonBeginsAPickOnTheSolidTheRegionCameFrom() async throws {
        let setup = await open()
        setup.app.editor.press(.pickFacesInView, on: setup.lattice.id)
        setup.app.handle(try #require(setup.app.editor.inspectorRequest))
        await setup.app.settle()
        let session = try #require(setup.app.pick)
        #expect(session.lattice == setup.lattice.id && session.picked.isEmpty)
        let part = try #require(setup.app.solid(at: Endpoint(node: setup.extrude.id, socket: "solid")))
        #expect(session.solid === part, "the baked solid, not the lattice")
        let shown = setup.app.viewport.items.map { ObjectIdentifier($0.solid) }
        #expect(shown == [ObjectIdentifier(part)], "the viewport shows only that solid")
    }

    @Test func aClickOnAFaceMapsTheLatticeToItAsOneNamedStep() async throws {
        let setup = await open()
        let app = setup.app
        app.beginFacePick(for: setup.lattice.id)
        await app.settle()
        app.viewportClicked(.edge(solid: 0, EdgeID(1)))
        app.viewportClicked(nil)
        #expect(app.pick != nil && app.document.canUndo == false, "an edge or empty space does nothing")
        app.viewportClicked(.face(solid: 0, FaceID(1)))
        #expect(app.pick == nil)
        let node = try #require(app.document.graph.nodes[setup.lattice.id])
        let part = try #require(app.solid(at: Endpoint(node: setup.extrude.id, socket: "solid")))
        #expect(node.inputValues[NodeSetting.face] == .facePick(try #require(part.topology.facePick(for: FaceID(1)))))
        #expect(node.inputValues["mapping"] == .integer(LatticeMappingKind.face.rawValue))
        #expect(app.editor.selection == [setup.lattice.id])
        #expect(app.document.undoName == "Map Lattice to Face")
        app.document.undo()
        await app.settle()
        let undone = try #require(app.document.graph.nodes[setup.lattice.id])
        #expect(undone.inputValues[NodeSetting.face] == nil && undone.inputValues["mapping"] == nil, "one step undoes both")
        #expect(app.document.canUndo == false)
    }

    @Test func cancelLeavesTheGraphAsItWas() async throws {
        let setup = await open()
        setup.app.beginFacePick(for: setup.lattice.id)
        setup.app.cancelPick()
        #expect(setup.app.pick == nil && setup.app.document.canUndo == false)
    }

    @Test func aRegionThatIsNotMadeFromASolidHasNothingToPickOn() async throws {
        var builder = GraphBuilder()
        let ball = builder.add(ImplicitSphereNode.self, ["radius": .number(10)])
        let lattice = builder.add(TPMSNode.self)
        let mesh = builder.add(MeshNode.self)
        let output = builder.add(OutputNode.self)
        builder.wire(ball, "implicit", to: lattice, "region")
        builder.wire(lattice, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        let app = await makeApp(builder.graph)
        app.beginFacePick(for: lattice.id)
        guard case .problem(let problem)? = app.alert else { Issue.record("no alert"); return }
        #expect(problem.title == "Nothing to pick on" && problem.message.contains("made from a solid with To Implicit"))
        #expect(app.pick == nil)
    }

    @Test func aNodeThatIsNotALatticeIsRefused() async throws {
        let setup = await open()
        setup.app.beginFacePick(for: setup.extrude.id)
        guard case .problem(let problem)? = setup.app.alert else { Issue.record("no alert"); return }
        #expect(problem.message == "Only a TPMS, Strut Lattice or Voronoi Lattice node maps its cells to a face.")
        #expect(setup.app.pick == nil)
    }
}
