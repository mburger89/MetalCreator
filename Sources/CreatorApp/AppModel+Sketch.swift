import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorSketchEditor
import CreatorViewport

extension AppModel {
    static let noWiredPlane = "Its plane comes from the wire into “plane”, which has no result yet. Wire a plane that evaluates."

    /// "Edit sketch" (sketcher spec §8): opens the node's sketch in the viewport. The camera looks straight at its
    /// plane, orthographic; the model dims (ghosts) but stays in view; the editor takes the primary pointer and the
    /// top bar and inspector show its toolbar and lists. A pick in progress is cancelled, as it would be by any edit.
    public func beginSketch(for id: NodeID) {
        editor.commitPendingEntry()
        editor.closePalette()
        guard let node = document.graph.nodes[id], node.typeID == SketchNode.typeID,
              case .sketch(let stored)? = node.inputValues[NodeSetting.sketch] else { return }
        guard let plane = sketchPlane(of: node, stored) else {
            alert = .problem(AppProblem("The sketch can't be opened yet", Self.noWiredPlane))
            return
        }
        pick = nil
        sketch?.stop()
        let sketchEditor = SketchEditorModel(sketch: SketchStore.folded(stored, constants: node.inputValues), plane: plane,
                                             isReservedName: SketchNode.isReservedDimensionName)
        sketchEditor.events.committed = { [weak self] in self?.storeSketch($0) }
        sketchEditor.events.finished = { [weak self] in self?.finishSketch() }
        sketchEditor.events.dismissHostPopup = { [weak self] in self?.closePaletteOverSketch() ?? false }
        let session = SketchSession(node: id, editor: sketchEditor, viewport: viewport)
        sketch = session
        session.start()
        viewport.lookAt(plane, framing: Self.framing(sketchEditor.sketch, on: plane))
    }

    /// Leaves sketch mode: the viewport gets its pointer, its ground grid and its camera controls back, and the model
    /// is drawn solid again.
    public func finishSketch() {
        sketch?.stop()
        sketch = nil
    }

    /// Closes the add-node palette if it's open over the sketch; true when it was (Review Focus 1).
    func closePaletteOverSketch() -> Bool {
        guard editor.palette != nil else { return false }
        editor.closePalette()
        return true
    }

    /// Stores one editor commit in the node as one undo step (`SketchStore`).
    func storeSketch(_ commit: SketchCommit) {
        guard let session = sketch, let node = document.graph.nodes[session.node] else { return }
        do {
            try document.perform(.batch(SketchStore.commands(storing: commit.sketch, in: node, graph: document.graph)))
        } catch {
            alert = .problem(AppProblem("The sketch couldn't be changed", error.message))
        }
    }

    /// Keeps the open sketch in step with its node after undo, redo or any other edit; leaves sketch mode when the node
    /// is gone. Called from every scene refresh.
    func refreshSketch() {
        guard let session = sketch else { return }
        guard let node = document.graph.nodes[session.node], case .sketch(let stored)? = node.inputValues[NodeSetting.sketch] else {
            return finishSketch()
        }
        let plane = sketchPlane(of: node, stored) ?? session.editor.plane
        session.editor.reload(SketchStore.folded(stored, constants: node.inputValues), plane: plane)
    }

    /// The plane a sketch is drawn on: its own, or the plane wired into the node (from the wire's current result).
    func sketchPlane(of node: Node, _ sketch: Sketch) -> Plane? {
        switch sketch.plane {
        case .fixed(let plane):
            return plane
        case .wired:
            guard let link = document.graph.incomingLink(to: Endpoint(node: node.id, socket: "plane")),
                  case .plane(let plane)? = document.results[link.from.node]?.outputs?[link.from.socket]?.items.first else {
                return nil
            }
            return plane
        }
    }

    /// What entering a sketch frames: its points with a margin, or 100 mm around the plane's origin when it has fewer
    /// than two distinct points.
    static func framing(_ sketch: Sketch, on plane: Plane) -> BoundingBox {
        let points = sketch.entityIDs.compactMap { sketch.position(of: $0) }.map(plane.point)
        if let box = BoundingBox(points: points), box.size.length > 1e-6 {
            let margin = box.size * 0.1
            return BoundingBox(min: box.min - margin, max: box.max + margin)
        }
        return BoundingBox(points: [plane.point(Vector2(-50, -50)), plane.point(Vector2(50, 50))])
            ?? BoundingBox(min: plane.origin, max: plane.origin)
    }
}
