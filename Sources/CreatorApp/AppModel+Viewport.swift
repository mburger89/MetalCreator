import CreatorEditor
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport

extension AppModel {
    /// The viewport's events, turned into graph commands and document state. Each one acts only while this
    /// viewport is still the current one: after New or Open the old one may outlive its replacement (a settling
    /// camera, a last draw), and its events must not reach the new document.
    func connectViewportEvents() {
        let viewport = self.viewport
        let events = { [weak self, weak viewport] in self?.ifCurrent(viewport) }
        viewport.events.clicked = { events()?.viewportClicked($0) }
        viewport.events.selectEdgesOfFace = { face, picks, edges in events()?.selectEdgesOfFace(face, picks, edges) }
        viewport.events.showProducingNode = { events()?.showProducingNode($0) }
        viewport.events.newSketchOnFace = { face, pick in events()?.newSketchOnFace(face, pick) }
        viewport.events.handleChanged = { id, value, phase in events()?.handleChanged(id, value, phase) }
        viewport.events.nodeName = { id in events()?.producingNode(id)?.name }
        // The camera reaches the file only when it comes to rest, never per frame: writing `viewState` invalidates
        // the editor, which reads its dock and canvas transform from it (M4 carry-over, spec §7.3).
        viewport.events.cameraSettled = { events()?.document.viewState.camera = $0 }
        viewport.events.homeChanged = { events()?.document.viewState.homeCamera = $0 }
        // A viewport press gives the keys back, as a canvas press does (gap M5-g), and commits a typed value.
        viewport.events.pressed = {
            guard let model = events() else { return }
            model.editor.commitPendingEntry()
            model.releaseTextFocus?()
        }
    }

    /// This model while `viewport` is its current viewport, else nil.
    private func ifCurrent(_ viewport: ViewportModel?) -> AppModel? {
        self.viewport === viewport ? self : nil
    }

    /// A handle drag edits its input: every step of one drag is one undo step (spec §6.5, §4.5). A step that
    /// leaves the value as it is (a click on the knob without moving) records nothing, so it neither adds an undo
    /// step nor clears redo.
    func handleChanged(_ id: String, _ value: Double, _ phase: HandleDragPhase) {
        guard let target = handleTargets[id] else { return }
        if value != currentNumber(target) {
            do {
                try document.perform(.setInput(target.node, target.socket, .number(value)), coalescingKey: "handle-\(id)")
            } catch {
                alert = .problem(AppProblem("The value couldn't be changed", error.message))
            }
        }
        if phase == .ended { document.endCoalescing() }
    }

    /// The number `target` currently reads: its stored input, or its socket's default (from `inputs(for:)`, so a
    /// per-node socket's default counts).
    private func currentNumber(_ target: HandleTarget) -> Double? {
        guard let node = document.graph.nodes[target.node] else { return nil }
        let stored = node.inputValues[target.socket]
            ?? registry[node.typeID]?.inputs(for: node).first { $0.name == target.socket }?.defaultValue
        return HandleBuilder.number(stored)
    }

    /// "Show Producing Node": selects the node and scrolls the graph to it, showing a hidden panel first. A face made
    /// inside a group names a scoped ID, so its group node on the top level is shown.
    func showProducingNode(_ id: NodeID) {
        guard let node = producingNode(id) else { return }
        if !editor.isPanelVisible { editor.toggleHidden() }
        editor.selection = [node.id]
        let zoom = editor.transform.zoom
        editor.transform = CanvasTransform(offset: AppLayout.revealPoint - editor.displayOrigin(of: node) * zoom, zoom: zoom)
    }

    /// The top-level node behind faces tagged with `id` (`GraphContent.topLevelNode(producing:)`).
    func producingNode(_ id: NodeID) -> Node? {
        document.content.topLevelNode(producing: id).flatMap { document.graph.nodes[$0] }
    }
}
