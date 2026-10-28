import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorSketchEditor
import CreatorViewport

/// The model dimension tool (dimensions spec §3.5): two clicks on edges, walls or holes of the part add the dimension between the
/// sketch entities they come from, at the value they already have, and open its value box.
extension AppModel {
    /// Starts the tool, with `target` as the first pick when given (the face menu's Dimension). Refused (false) while a sketch is
    /// open or a pick session runs; true otherwise, and when it already runs nothing changes.
    @discardableResult
    public func beginModelDimension(from target: PickTarget? = nil) -> Bool {
        guard sketch == nil, pick == nil else { return false }
        guard modelDimension == nil else { return true }
        editor.commitPendingEntry()
        // The banner's Escape is a button shortcut, which runs before the palette's keys in `onInput`.
        editor.closePalette()
        modelDimension = ModelDimensionSession(level: editor.levelPath)
        if let target { modelDimensionClicked(target) }
        return true
    }

    /// Ends the tool, leaving the graph as it was.
    public func cancelModelDimension() {
        modelDimension = nil
    }

    /// Ends the tool and forgets the dimension it added last: nothing is shown or opened for it any more.
    func endModelDimension() {
        modelDimension = nil
        heldModelDimension = nil
        pendingValueBox = nil
    }

    /// A click while the tool runs. A click on nothing, a ghost or a guide is ignored; the first pick is kept with the sketch
    /// entities it comes from; the second adds the dimension between the entities of the sketch both come from, or says why not.
    func modelDimensionClicked(_ target: PickTarget?) {
        guard var session = modelDimension else { return }
        guard session.level == editor.levelPath else {
            modelDimension = nil
            return
        }
        session.message = nil
        modelDimension = session
        guard let target, viewport.items.indices.contains(target.solidIndex) else { return }
        let item = viewport.items[target.solidIndex]
        guard !item.isGhost, !item.isGuide else { return }
        let pick = ModelDimensionPick(target: target, items: ModelDimensionTrace.items(
            for: target, solid: item.solid, graph: editor.graph, results: editor.levelResults))
        guard let first = session.first else {
            session.first = pick
            modelDimension = session
            return
        }
        guard let (a, b) = ModelDimensionTrace.shared(first.items, pick.items) else {
            return refuseModelDimension(&session)
        }
        // The same sketch entity twice (a hole's top and bottom rim): nothing to measure, the first pick stays.
        guard a != b else { return }
        guard add(between: a, and: b) else { return refuseModelDimension(&session) }
        modelDimension = nil
    }

    private func refuseModelDimension(_ session: inout ModelDimensionSession) {
        session.first = nil
        session.message = ModelDimensionText.differentFeatures
        modelDimension = session
    }

    /// Adds the dimension between `a` and `b` (entities of one Sketch node) at the value the evaluated sketch measures, as one undo step.
    /// False, and nothing written, when the node, an entity or the measurement is gone.
    private func add(between a: SketchItem, and b: SketchItem) -> Bool {
        let graph = editor.graph
        guard let node = graph.nodes[a.node], node.typeID == SketchNode.typeID,
              case .sketch(let stored)? = node.inputValues[NodeSetting.sketch],
              let evaluated = editor.levelResults[node.id]?.sketchTrace?.sketch,
              [a.entity, b.entity].allSatisfy({ stored.entities[$0] != nil && evaluated.entities[$0] != nil }),
              let kind = ModelDimensionKind.between(a.entity, b.entity, in: evaluated),
              let added = MeasuredDimension.add(kind, measuredOn: evaluated, to: stored) else { return false }
        do {
            try document.perform(.batch(SketchStore.commands(storing: added.sketch, in: node, graph: graph)), at: editor.graphPath,
                                 name: UndoName.sketch(SketchStepName.addDimension))
        } catch {
            alert = .problem(AppProblem("The dimension couldn't be added", error.message))
            return true
        }
        if added.isDriving {
            heldModelDimension = DimensionPin(node: node.id, target: .sketchDimension(added.id))
            pendingValueBox = FeatureDimension.overlayID(node: node.id, target: .sketchDimension(added.id))
        }
        return true
    }
}
