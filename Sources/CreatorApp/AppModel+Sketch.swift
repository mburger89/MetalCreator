import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorSketchEditor
import CreatorViewport

extension AppModel {
    static let planeFailed = "The node wired into “plane” has no result now, so the sketch stays on the plane it had."
    static let planeUnwired = "Nothing is wired into “plane” now, so the sketch stays on the plane it had."
    static let noWiredPlane = "Its plane comes from the wire into “plane”, which has no result yet. Wire a plane that evaluates."

    /// "Edit sketch" (sketcher spec §8): opens the node's sketch in the viewport. The camera looks straight at its
    /// plane, orthographic, framed on the sketch (`SketchEditorModel.framingBounds`), and stays locked to it (planar
    /// navigation) until the sketch ends; the model dims (ghosts) but stays in view; the editor takes the primary
    /// pointer and the top bar and inspector show its toolbar and lists. A pick in progress is cancelled, as it would
    /// be by any edit.
    public func beginSketch(for id: NodeID, plane known: Plane? = nil) {
        editor.commitPendingEntry()
        editor.closePalette()
        guard let node = document.graph.nodes[id], node.typeID == SketchNode.typeID,
              case .sketch(let stored)? = node.inputValues[NodeSetting.sketch] else { return }
        // `known`: the plane of a sketch whose wired source hasn't evaluated yet (New Sketch on Face).
        guard let plane = known ?? sketchPlane(of: node, stored) else {
            alert = .problem(AppProblem("The sketch can't be opened yet", Self.noWiredPlane))
            return
        }
        pick = nil
        sketch?.stop()
        let shown = shownSketch(of: node, stored)
        let sketchEditor = SketchEditorModel(sketch: shown.sketch, plane: plane, wired: shown.wired,
                                             isReservedName: SketchNode.isReservedDimensionName)
        sketchEditor.events.committed = { [weak self] in self?.storeSketch($0) }
        sketchEditor.events.finished = { [weak self] in self?.finishSketch() }
        sketchEditor.events.projection = { [weak self] target, plane in
            self?.resolveProjection(target, onto: plane, for: id) ?? ProjectionResolution(candidates: [], skipped: [Self.noProjection])
        }
        sketchEditor.events.dismissHostPopup = { [weak self] in self?.closePaletteOverSketch() ?? false }
        let session = SketchSession(node: id, editor: sketchEditor, viewport: viewport)
        sketch = session
        session.start()
        if let bounds = sketchEditor.framingBounds { viewport.lookAt(plane, framing: bounds) }
    }

    /// Leaves sketch mode: the viewport gets its pointer, its ground grid, free orbit and its camera controls back (the
    /// camera stays where it is), and the model is drawn solid again.
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
        var projections: [SketchStore.Projection] = []
        for write in commit.projections {
            guard viewport.items.indices.contains(write.solid), let source = producer(of: viewport.items[write.solid].solid) else {
                alert = .problem(AppProblem("The projection couldn't be stored", "The part it was picked on can't be found."))
                refreshSketch()   // the editor already shows the projections it was refused: back to what is stored
                return
            }
            projections.append(SketchStore.Projection(reference: write.reference, pick: write.pick, source: source))
        }
        do {
            let commands = SketchStore.commands(storing: commit.sketch, in: node, graph: document.graph, projections: projections)
            try document.perform(.batch(commands), name: UndoName.sketch(commit.name))
        } catch {
            alert = .problem(AppProblem("The sketch couldn't be changed", error.message))
            refreshSketch()
        }
    }

    /// Keeps the open sketch in step with its node after undo, redo or any other edit; leaves sketch mode when the node
    /// is gone. Called from every scene refresh.
    func refreshSketch() {
        guard let session = sketch else { return }
        guard let node = document.graph.nodes[session.node], case .sketch(let stored)? = node.inputValues[NodeSetting.sketch] else {
            return finishSketch()
        }
        let found = sketchPlane(of: node, stored)
        let plane = found ?? session.editor.plane
        // A wired plane that moved: the camera looks at it again. One that lost its result (the wire's node failed)
        // leaves the sketch on the last plane and says so once, when it is lost; while another alert or a close is
        // being answered it waits, and is said at the first refresh after.
        let moved = found != nil && plane != session.editor.plane
        if found != nil {
            session.hasPlane = true
        } else if session.hasPlane, alert == nil, closeRequest == .idle, let message = planeLossMessage(of: node, stored) {
            session.hasPlane = false
            alert = .problem(AppProblem("The plane lost its result", message))
        }
        let shown = shownSketch(of: node, stored)
        session.editor.reload(shown.sketch, plane: plane, wired: shown.wired)
        if moved, let bounds = session.editor.framingBounds { viewport.lookAt(plane, framing: bounds) }
    }

    /// The sketch as the node evaluates it (sketcher spec §7): each exposed dimension takes the constant left under its
    /// socket name or, when the socket is wired, the wire's current result (a wire without a number result yet leaves
    /// the stored value). `wired` names the wired dimensions, whose values the editor can't type.
    func shownSketch(of node: Node, _ stored: Sketch) -> (sketch: Sketch, wired: Set<DimensionID>) {
        var sketch = refreshedProjections(SketchStore.folded(stored, constants: node.inputValues), of: node)
        var wired: Set<DimensionID> = []
        for (id, name) in SketchStore.exposedNames(stored) {
            guard let link = document.graph.incomingLink(to: Endpoint(node: node.id, socket: name)) else { continue }
            wired.insert(id)
            if let result = document.results[link.from.node], result.state.isSuccess,
               case .number(let value)? = result.outputs?[link.from.socket]?.items.first {
                sketch.dimensions[id]?.value = value
            }
        }
        return (sketch, wired)
    }

    /// The plane a sketch is drawn on: its own, or the plane wired into the node (from the wire's current result).
    func sketchPlane(of node: Node, _ sketch: Sketch) -> Plane? {
        switch sketch.plane {
        case .fixed(let plane):
            return plane
        case .wired:
            guard let link = document.graph.incomingLink(to: Endpoint(node: node.id, socket: "plane")) else { return nil }
            if let result = document.results[link.from.node], result.state.isSuccess,
               case .plane(let plane)? = result.outputs?[link.from.socket]?.items.first {
                return plane
            }
            // Only a node that hasn't evaluated falls back: one that evaluated and failed rejected the plane itself.
            guard document.results[link.from.node] == nil else { return nil }
            return unevaluatedFacePlane(of: link.from.node)
        }
    }

    /// Why the plane wired into `node` is gone for good, or `nil` while it is not: its wire was removed, or its node
    /// failed. A node that is only evaluating again (or not yet) isn't gone: the sketch waits for its result.
    private func planeLossMessage(of node: Node, _ sketch: Sketch) -> String? {
        guard case .wired = sketch.plane else { return nil }
        guard let link = document.graph.incomingLink(to: Endpoint(node: node.id, socket: "plane")) else {
            return Self.planeUnwired
        }
        if case .error? = document.results[link.from.node]?.state { return Self.planeFailed }
        return nil
    }

    /// The plane a Plane from Face makes, worked out from its picked face when the node itself hasn't evaluated: nothing
    /// downstream of a new sketch draws it yet. It needs the node's solid to have a result; `nil` otherwise.
    private func unevaluatedFacePlane(of id: NodeID) -> Plane? {
        guard let node = document.graph.nodes[id], node.typeID == PlaneFromFaceNode.typeID,
              case .facePick(let pick)? = node.inputValues[NodeSetting.face],
              let source = document.graph.incomingLink(to: Endpoint(node: id, socket: "solid"))?.from,
              let solid = solid(at: source), let face = solid.topology.faces(matching: pick).first else { return nil }
        return PlaneFromFaceNode.plane(of: face)
    }
}
