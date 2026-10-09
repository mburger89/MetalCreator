import CreatorGraph
import CreatorKernel
import CreatorViewport
import Observation

extension AppModel {
    /// The nodes Final preview shows: every Output node, in ID order.
    var outputNodes: [NodeID] {
        document.graph.nodes.values.filter(\.isOutput).map(\.id).sorted()
    }

    /// Re-applies the preview mode, the panels' model area, the viewport's theme and the scene, then follows their
    /// inputs again.
    func sceneInputsChanged() {
        sceneTask = nil
        applyPreview()
        viewport.setModelArea(AppLayout.modelArea(dock: editor.dock, panelWidth: panelWidth, panelHeight: panelHeight))
        if viewport.theme != themes.current { viewport.theme = themes.current }
        refreshScene()
        observeScene()
    }

    /// "Selected node" previews the one selected node; Final, or anything but one selected node, previews none.
    func applyPreview() {
        let wanted = previewMode == .selectedNode && editor.selection.count == 1 ? editor.selection.first : nil
        if document.previewNode != wanted { document.previewNode = wanted }
    }

    /// Shows the scene and the selected nodes' handles. While picking, only the solid being picked on, with the
    /// picked edges selected, no handles and a crosshair pointer. While sketching, the scene dimmed (ghosted, still
    /// pickable) and no handles, and the open sketch follows its node. A scene or handles equal to what's shown aren't
    /// sent again: the observation also fires for canvas pans, camera settles and panel resizes, which change neither.
    func refreshScene() {
        refreshSketch()
        var scene: [SceneItem]
        if viewport.isPicking != (pick != nil) { viewport.isPicking = pick != nil }
        if let pick {
            scene = [SceneItem(item: ViewportItem(solid: pick.solid, selectedEdges: Set(pick.picked)), source: pick.source)]
        } else {
            let shown = previewMode == .final ? outputNodes : (document.previewNode.map { [$0] } ?? [])
            scene = SceneBuilder.scene(shown: shown, graph: document.graph, results: document.results,
                                       lastGood: document.lastGoodOutputs, selection: editor.selection)
        }
        if sketch != nil {
            scene = scene.map { entry in
                var dimmed = entry
                dimmed.item.isGhost = true
                return dimmed
            }
        }
        sources = Dictionary(scene.compactMap { entry in entry.source.map { (ObjectIdentifier(entry.item.solid), $0) } },
                             uniquingKeysWith: { first, _ in first })
        let items = scene.map(\.item)
        if !ViewportItem.sameScene(items, requestedScene) {
            requestedScene = items
            viewport.show(items)
        }
        let handles = pick == nil && sketch == nil
            ? HandleBuilder.handles(for: editor.selection, graph: document.graph, results: document.results, registry: registry)
            : []
        handleTargets = Dictionary(handles.map { ($0.handle.id, $0.target) }, uniquingKeysWith: { first, _ in first })
        let shownHandles = handles.map(\.handle)
        if viewport.handles != shownHandles { viewport.showHandles(shownHandles) }
    }

    /// Follows what the scene is made from, once; the first change schedules one refresh, which follows again. A
    /// registration made for parts that have since been replaced is ignored by its generation.
    func observeScene() {
        observationGeneration += 1
        let generation = observationGeneration
        withObservationTracking {
            _ = document.results
            _ = document.lastGoodOutputs
            _ = document.graph
            _ = document.previewNode
            _ = editor.selection
            _ = editor.dock
            _ = previewMode
            _ = pick
            _ = sketch
            _ = panelWidth
            _ = panelHeight
            _ = themes.current
        } onChange: { [weak self] in
            // Observation calls this as the property is about to change, on the actor that changes it: every
            // property above is main-actor state.
            MainActor.assumeIsolated { self?.scheduleSceneRefresh(generation) }
        }
    }

    private func scheduleSceneRefresh(_ generation: Int) {
        guard generation == observationGeneration, sceneTask == nil else { return }
        sceneTask = Task { [weak self] in self?.sceneInputsChanged() }
    }
}
