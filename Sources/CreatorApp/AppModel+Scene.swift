import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorViewport
import Foundation
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

    /// "Selected node" previews the one selected node of the level shown; Final, or anything but one selected node, previews none,
    /// except that a selected layout node is always evaluated (Final preview shows its placements as an overlay,
    /// `layoutOverlay`, even before anything is wired to it), and so is a selected Fields node (its field tints the part and
    /// lights the slice, `fieldPreview`).
    func applyPreview() {
        // Inside a group the document evaluates the whole level (`DocumentModel.inspectedLevel`), so the selected node
        // needs no demand of its own there.
        var wanted: NodeID?
        if editor.selection.count == 1, !editor.isInsideGroup, let selected = editor.selection.first {
            let isLayout = editor.graph.nodes[selected].map { LayoutPreview.layoutTypes.contains($0.typeID) } ?? false
            let isField = editor.graph.nodes[selected].map { FieldPreviewSelection.previews($0, registry: registry) } ?? false
            wanted = previewMode == .selectedNode || isLayout || isField ? selected : nil
        }
        if document.previewNode != wanted { document.previewNode = wanted }
    }

    /// Shows the scene and the selected nodes' handles. In Final preview the scene also carries the selected rules'
    /// edges on solids it doesn't show, as guides (not while sketching). While picking, only the solid being picked on,
    /// with the picked edges selected, no handles and a crosshair pointer. While sketching, the scene dimmed (ghosted,
    /// still pickable) and no handles, and the open sketch follows its node. A scene or handles equal to what's shown
    /// aren't sent again: the observation also fires for canvas pans, camera settles and panel resizes, which change
    /// neither.
    func refreshScene() {
        refreshSketch()
        // A pick belongs to the level it began on: showing another cancels it.
        if let session = pick, session.level != editor.levelPath { pick = nil }
        var scene: [SceneItem]
        if viewport.isPicking != (pick != nil) { viewport.isPicking = pick != nil }
        if let pick {
            scene = [SceneItem(item: ViewportItem(solid: pick.solid, selectedEdges: Set(pick.picked)), source: pick.source)]
        } else {
            scene = shownScene()
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
        fieldPreview.follow(fieldPreviewRequest(for: scene))
        let items = fieldPreview.tinted(scene.map(\.item), colors: themes.current.colors)
        if !ViewportItem.sameScene(items, requestedScene) {
            requestedScene = items
            viewport.show(items)
        }
        // The sketch editor draws its own overlay while a sketch is open; otherwise a selected layout node shows its placements.
        if sketch == nil { viewport.showOverlay(pick == nil ? layoutOverlay : ViewportOverlay()) }
        viewport.showSlice(fieldPreview.viewportSlice(colors: themes.current.colors))
        cutView.follow(bounds: viewport.sceneBounds)
        viewport.showClip(cutView.clip)
        let handles = pick == nil && sketch == nil
            ? HandleBuilder.handles(for: editor.selection, graph: editor.graph, results: editor.levelResults, registry: registry)
            : []
        handleTargets = Dictionary(handles.map { ($0.handle.id, $0.target) }, uniquingKeysWith: { first, _ in first })
        let shownHandles = handles.map(\.handle) + (fieldPreview.sliceHandle.map { [$0] } ?? []) + (cutView.handle.map { [$0] } ?? [])
        if viewport.handles != shownHandles { viewport.showHandles(shownHandles) }
    }

    /// The scene for the preview mode: Final shows every Output node of the whole part, whichever level the graph
    /// panel shows; Selected node shows the one selected node of that level, from the top-level results or, inside
    /// a group, from the results inside it (`EditorModel.levelResults`; there is no last good result to ghost).
    private func shownScene() -> [SceneItem] {
        if previewMode == .final {
            let meshes = followMeshes(shown: outputNodes, results: document.results)
            let options = SceneBuilder.Options(selection: editor.isInsideGroup ? [] : editor.selection, showsGuides: sketch == nil,
                                               meshes: meshes)
            return SceneBuilder.scene(shown: outputNodes, graph: document.graph, results: document.results,
                                      lastGood: document.lastGoodOutputs, options: options)
        }
        let shown = editor.isInsideGroup
            ? (editor.selection.count == 1 ? Array(editor.selection) : [])
            : (document.previewNode.map { [$0] } ?? [])
        let meshes = followMeshes(shown: shown, results: editor.levelResults)
        let options = SceneBuilder.Options(selection: editor.selection, showsGuides: false, meshes: meshes)
        return SceneBuilder.scene(shown: shown, graph: editor.graph, results: editor.levelResults,
                                  lastGood: editor.isInsideGroup ? [:] : document.lastGoodOutputs, options: options)
    }

    /// Hands the preview meshes of the shown nodes to the progressive preview (an edit that replaced one stops its passes), prunes the
    /// display solids of meshes no longer shown, and returns what the scene needs to show the meshes.
    private func followMeshes(shown: [NodeID], results: [NodeID: NodeResult]) -> MeshScene {
        let bases = SceneBuilder.previewMeshes(shown: shown, results: results)
        meshRefinement.follow(bases)
        let scene = MeshScene(solids: meshSolids, refined: meshRefinement.refined)
        meshSolids.keep(Set(bases.map(\.id)).union(meshRefinement.refined.values.map(\.id)).union(Self.meshIDs(in: results, shown: shown)))
        return scene
    }

    /// The IDs of every mesh in the shown nodes' results, so a mesh that cannot be refined keeps its solid.
    private static func meshIDs(in results: [NodeID: NodeResult], shown: [NodeID]) -> Set<UUID> {
        var ids: Set<UUID> = []
        for id in shown {
            for value in results[id]?.outputs?.values ?? [:].values {
                for case .mesh(let payload) in value.items { if let mesh = payload as? TriangleMesh { ids.insert(mesh.id) } }
            }
        }
        return ids
    }

    /// Follows what the scene is made from, once; the first change schedules one refresh, which follows again. A
    /// registration made for parts that have since been replaced is ignored by its generation.
    func observeScene() {
        observationGeneration += 1
        let generation = observationGeneration
        withObservationTracking {
            _ = document.results
            _ = document.innerResults
            _ = document.lastGoodOutputs
            _ = document.graph
            _ = document.definitions
            _ = editor.enteredGroups
            _ = document.previewNode
            _ = fieldPreview.revision
            _ = cutView.revision
            _ = meshRefinement.revision
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
