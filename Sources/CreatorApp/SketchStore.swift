import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch

/// The graph commands that store an edited sketch in its node as one undo step (S4 → S5 handoff):
/// - the whole sketch, as a `setInput` of the `sketch` setting;
/// - an exposed dimension's value lives in one place, the sketch, so a constant left under its socket name is cleared
///   (otherwise it would silently override later edits);
/// - a renamed exposed dimension takes its wire with it, and one no longer exposed drops its wire and constant.
/// Reserved names are never touched: they are never sockets (`SketchNode.isReservedDimensionName`).
enum SketchStore {
    static func commands(storing new: Sketch, in node: Node, graph: Graph) -> [GraphCommand] {
        let old: Sketch? = if case .sketch(let stored)? = node.inputValues[NodeSetting.sketch] { stored } else { nil }
        let oldNames = old.map(exposedNames) ?? [:]
        let newNames = exposedNames(new)
        var before: [GraphCommand] = []
        var after: [GraphCommand] = []
        for id in oldNames.keys.sorted() {
            guard let oldName = oldNames[id], newNames[id] != oldName else { continue }
            if let link = graph.incomingLink(to: Endpoint(node: node.id, socket: oldName)) {
                before.append(.disconnect(link))
                if let newName = newNames[id] {
                    after.append(.connect(Link(from: link.from, to: Endpoint(node: node.id, socket: newName))))
                }
            }
            if node.inputValues[oldName] != nil { after.append(.setInput(node.id, oldName, nil)) }
        }
        for id in newNames.keys.sorted() {
            guard let name = newNames[id], case .number? = node.inputValues[name] else { continue }
            after.append(.setInput(node.id, name, nil))
        }
        return before + [.setInput(node.id, NodeSetting.sketch, .sketch(new))] + after
    }

    /// The sketch with each exposed dimension's constant (left under its socket name) folded into its value, so the
    /// editor shows what the node evaluates.
    static func folded(_ sketch: Sketch, constants: [SocketName: ConstantValue]) -> Sketch {
        var folded = sketch
        for (id, name) in exposedNames(sketch) {
            if case .number(let value)? = constants[name] { folded.dimensions[id]?.value = value }
        }
        return folded
    }

    /// Each exposed dimension's socket name, leaving out the reserved ones.
    static func exposedNames(_ sketch: Sketch) -> [DimensionID: SocketName] {
        var names: [DimensionID: SocketName] = [:]
        for (id, dimension) in sketch.dimensions where dimension.isExposed && !SketchNode.isReservedDimensionName(dimension.name) {
            names[id] = SocketName(dimension.name)
        }
        return names
    }
}
