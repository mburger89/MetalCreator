import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport

extension AppModel {
    /// "Pattern on Face" (patterns spec §3): a Face Pattern holding the face's remembered pick, wired from the node that made the
    /// face's solid and placed beside it, as one undo step, and selected so its placements show (`LayoutPreview`). A face that
    /// isn't flat is said in words, a face of a solid that is gone does nothing. Inside a group it is refused, as New Sketch on
    /// Face is: the pick would have to be written relative to the group (groups Errata (C2)).
    func patternOnFace(_ ref: ViewportFaceRef, _ pick: FacePick) {
        guard viewport.items.indices.contains(ref.solidIndex) else { return }
        guard !editor.isInsideGroup else {
            alert = .problem(AppProblem("No pattern was made", "Patterns on a face can't be made inside a group yet. "
                                        + "Make it before grouping, or from the top level."))
            return
        }
        let solid = viewport.items[ref.solidIndex].solid
        guard let face = solid.topology.face(ref.face), PlaneFromFaceNode.plane(of: face) != nil else {
            alert = .problem(AppProblem("No pattern was made", "Only a flat face can hold a pattern."))
            return
        }
        guard let source = producer(of: solid) else {
            alert = .problem(AppProblem("No pattern was made", "The node that made this solid can't be found."))
            return
        }
        let from = document.graph.nodes[source.node]?.position ?? .zero
        var pattern = registry.makeNode(FacePatternNode.typeID, at: from + Vector2(240, 140))
        pattern.inputValues[NodeSetting.face] = .facePick(pick)
        let commands: [GraphCommand] = [
            .addNode(pattern), .connect(Link(from: source, to: Endpoint(node: pattern.id, socket: "solid"))),
        ]
        do {
            try document.perform(.batch(commands), name: UndoName.patternOnFace)
        } catch {
            alert = .problem(AppProblem("No pattern was made", error.message))
            return
        }
        editor.selection = [pattern.id]
    }
}
