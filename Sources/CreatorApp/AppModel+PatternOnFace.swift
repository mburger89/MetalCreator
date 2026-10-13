import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport

extension AppModel {
    /// "Pattern on Face" (patterns spec §3): a Face Pattern holding the face's remembered pick.
    func patternOnFace(_ ref: ViewportFaceRef, _ pick: FacePick) {
        layoutOnFace(ref, pick, as: .pattern)
    }

    /// A layout node of type `layout` holding the face's remembered pick, wired from the node that made the face's solid and
    /// placed beside it, as one undo step, and selected so its placements show (`LayoutPreview`). A face that isn't flat is said
    /// in words, a face of a solid that is gone does nothing. Inside a group it is refused, as New Sketch on Face is: the pick
    /// would have to be written relative to the group (groups Errata (C2)).
    func layoutOnFace(_ ref: ViewportFaceRef, _ pick: FacePick, as layout: FaceLayout) {
        guard viewport.items.indices.contains(ref.solidIndex) else { return }
        guard !editor.isInsideGroup else {
            alert = .problem(AppProblem(layout.failureTitle, layout.insideGroup))
            return
        }
        let solid = viewport.items[ref.solidIndex].solid
        guard let face = solid.topology.face(ref.face), PlaneFromFaceNode.plane(of: face) != nil else {
            alert = .problem(AppProblem(layout.failureTitle, layout.notFlat))
            return
        }
        guard let source = producer(of: solid) else {
            alert = .problem(AppProblem(layout.failureTitle, "The node that made this solid can't be found."))
            return
        }
        let from = document.graph.nodes[source.node]?.position ?? .zero
        var node = registry.makeNode(layout.typeID, at: from + Vector2(240, 140))
        node.inputValues[NodeSetting.face] = .facePick(pick)
        let commands: [GraphCommand] = [
            .addNode(node), .connect(Link(from: source, to: Endpoint(node: node.id, socket: "solid"))),
        ]
        do {
            try document.perform(.batch(commands), name: layout.undoName)
        } catch {
            alert = .problem(AppProblem(layout.failureTitle, error.message))
            return
        }
        editor.selection = [node.id]
    }
}
