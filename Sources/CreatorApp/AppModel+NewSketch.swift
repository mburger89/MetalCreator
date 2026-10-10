import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorViewport

extension AppModel {
    /// "New Sketch on Face" (sketcher spec §8): a Plane from Face on the face's solid and a Sketch drawn on its plane, as one
    /// undo step, placed beside the node that made the solid; then the sketch opens on the plane computed from the face now (the
    /// new Plane from Face hasn't evaluated; `refreshSketch` takes the node's own plane once it has). A face that isn't flat is
    /// said in words, a face of a solid that is gone does nothing, and nothing starts while a sketch is open. Inside a
    /// group it is refused, as "Edit sketch" is there: sketch mode works on the top level's graph (groups Errata (C2)).
    func newSketchOnFace(_ ref: ViewportFaceRef, _ pick: FacePick) {
        guard sketch == nil, viewport.items.indices.contains(ref.solidIndex) else { return }
        guard !editor.isInsideGroup else {
            alert = .problem(AppProblem("No sketch was made",
                                        "Sketches inside a group can't be made yet. Make it before grouping, or from the top level."))
            return
        }
        let solid = viewport.items[ref.solidIndex].solid
        guard let face = solid.topology.face(ref.face), let plane = PlaneFromFaceNode.plane(of: face) else {
            alert = .problem(AppProblem("No sketch was made", "Only a flat face can hold a sketch."))
            return
        }
        guard let source = producer(of: solid) else {
            alert = .problem(AppProblem("No sketch was made", "The node that made this solid can't be found."))
            return
        }
        let from = document.graph.nodes[source.node]?.position ?? .zero
        var planeNode = registry.makeNode(PlaneFromFaceNode.typeID, at: from + Vector2(240, 140))
        planeNode.inputValues[NodeSetting.face] = .facePick(pick)
        var sketchNode = registry.makeNode(SketchNode.typeID, at: from + Vector2(480, 140))
        sketchNode.inputValues[NodeSetting.sketch] = .sketch(Sketch(plane: .wired))
        let commands: [GraphCommand] = [
            .addNode(planeNode), .addNode(sketchNode),
            .connect(Link(from: source, to: Endpoint(node: planeNode.id, socket: "solid"))),
            .connect(Link(from: Endpoint(node: planeNode.id, socket: "plane"), to: Endpoint(node: sketchNode.id, socket: "plane"))),
        ]
        do {
            try document.perform(.batch(commands))
        } catch {
            alert = .problem(AppProblem("No sketch was made", error.message))
            return
        }
        editor.selection = [sketchNode.id]
        beginSketch(for: sketchNode.id, plane: plane)
    }
}
