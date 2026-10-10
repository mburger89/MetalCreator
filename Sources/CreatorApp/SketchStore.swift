import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import Foundation

/// The graph commands that store an edited sketch in its node as one undo step (S4 → S5 handoff):
/// - the whole sketch, as a `setInput` of the `sketch` setting;
/// - an exposed dimension's value lives in one place, the sketch, so a constant left under its socket name is cleared
///   (otherwise it would silently override later edits);
/// - a renamed exposed dimension takes its wire with it, and one no longer exposed drops its wire and constant;
/// - a dimension still wired keeps its stored value: the editor showed (and solved) the wired value, which overrides
///   the stored one only while the wire is there (sketcher spec §7).
/// Reserved names are never touched: they are never sockets (`SketchNode.isReservedDimensionName`).
/// - a projection the edit added stores its pick under `NodeSetting.projection(reference)` and wires its solid into
///   `references` when nothing is wired there; one the edit removed clears its pick.
enum SketchStore {
    /// A projection to store beside the sketch: the pick, and the output that made the solid it was picked on.
    struct Projection {
        let reference: String
        let pick: EdgePick
        let source: Endpoint
    }

    /// The Sketch node's input the projected solids are wired into (sketcher spec §7).
    static let referencesSocket: SocketName = "references"

    static func commands(storing new: Sketch, in node: Node, graph: Graph, projections: [Projection] = []) -> [GraphCommand] {
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
        var storing = new
        for id in newNames.keys {
            guard let oldName = oldNames[id], let oldValue = old?.dimensions[id]?.value,
                  graph.incomingLink(to: Endpoint(node: node.id, socket: oldName)) != nil else { continue }
            storing.dimensions[id]?.value = oldValue
        }
        return before + [.setInput(node.id, NodeSetting.sketch, .sketch(storing))] + after
            + projectionCommands(old: old, new: new, in: node, graph: graph, projections: projections)
    }

    /// The picks of the projections the edit added, the pick settings of the ones it removed (cleared), and the wire from the
    /// first added projection's solid into `references` when that input has none.
    static func projectionCommands(old: Sketch?, new: Sketch, in node: Node, graph: Graph,
                                   projections: [Projection]) -> [GraphCommand] {
        var commands: [GraphCommand] = []
        let removed = old.map(projectedReferences).map { $0.subtracting(projectedReferences(new)) } ?? []
        for reference in removed.sorted() where node.inputValues[NodeSetting.projection(reference)] != nil {
            commands.append(.setInput(node.id, NodeSetting.projection(reference), nil))
        }
        for projection in projections {
            commands.append(.setInput(node.id, NodeSetting.projection(projection.reference), .edgePicks([projection.pick])))
        }
        let references = Endpoint(node: node.id, socket: referencesSocket)
        if let first = projections.first, graph.incomingLink(to: references) == nil {
            commands.append(.connect(Link(from: first.source, to: references)))
        }
        return commands
    }

    /// The references of the sketch's projected edges.
    static func projectedReferences(_ sketch: Sketch) -> Set<String> {
        Set(sketch.entityIDs.compactMap { id -> String? in
            if case .projected(let source)? = sketch.entities[id]?.kind { source.reference } else { nil }
        })
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

    /// Each exposed dimension's socket name, as the node partitions them (reserved and repeated names left out).
    static func exposedNames(_ sketch: Sketch) -> [DimensionID: SocketName] {
        SketchNode.exposedSocketNames(sketch)
    }
}
