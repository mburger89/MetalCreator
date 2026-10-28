import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorSketch
import CreatorViewport

/// Turns the specs nodes declared into the dimensions the viewport shows (spec §3.1, §3.3).
enum FeatureDimensionBuilder {
    // swiftlint:disable function_parameter_count
    /// The dimensions of the `contextual` nodes and of each one's private chain (`FeatureChain`), then those of the `pinned`
    /// targets, each ID once, in that order. `graph` and `results` are the level shown; `content` gives the document's
    /// parameters and group definitions. A pin whose node, target or result is gone adds nothing.
    static func dimensions(contextual: Set<NodeID>, pinned: [DimensionPin], graph: Graph, content: GraphContent,
                           results: [NodeID: NodeResult], registry: NodeRegistry, units: DocumentUnits,
                           style: DimensionStyle) -> [FeatureDimension] {
        let context = Context(graph: graph, content: content, results: results, registry: registry, units: units, style: style,
                              pins: Set(pinned))
        var shown: [FeatureDimension] = []
        var seen: Set<OverlayDimensionID> = []
        func add(_ entries: [FeatureDimension]) {
            for entry in entries where seen.insert(entry.id).inserted { shown.append(entry) }
        }
        for selected in contextual.sorted() {
            let chain = FeatureChain.nodes(of: selected, in: graph, registry: registry)
            for id in [selected] + chain.subtracting([selected]).sorted() { add(context.entries(of: id, target: nil)) }
        }
        for pin in pinned { add(context.entries(of: pin.node, target: pin.target)) }
        return shown
    }
    // swiftlint:enable function_parameter_count

    /// What every entry is built from.
    private struct Context {
        var graph: Graph
        var content: GraphContent
        var results: [NodeID: NodeResult]
        var registry: NodeRegistry
        var units: DocumentUnits
        var style: DimensionStyle
        var pins: Set<DimensionPin>

        /// The dimensions `node` declared, only those on `target` when it is given.
        func entries(of nodeID: NodeID, target: DimensionTarget?) -> [FeatureDimension] {
            guard let node = graph.nodes[nodeID], let specs = results[nodeID]?.dimensions else { return [] }
            var counts: [String: Int] = [:]
            var made: [FeatureDimension] = []
            for spec in specs {
                let key = SpecKey(target: spec.target, component: spec.component)
                let index = counts[key.text, default: 0]
                counts[key.text] = index + 1
                guard target == nil || target == spec.target else { continue }
                let isRepeated = specs.count { $0.target == spec.target && $0.component == spec.component } > 1
                guard let editing = editing(of: spec, on: node, isRepeated: isRepeated) else { continue }
                made.append(entry(spec, on: node, editing: editing, index: index))
            }
            return made
        }

        private func entry(_ spec: DimensionSpec, on node: Node, editing: FeatureDimension.Editing,
                           index: Int) -> FeatureDimension {
            let isReference: Bool
            if case .reference = editing { isReference = true } else { isReference = false }
            let reading = DimensionReading(spec.value, spec.quantity, count: spec.count, isReference: isReference,
                                           name: exposedName(of: spec, on: node))
            let id = FeatureDimension.overlayID(node: node.id, target: spec.target, component: spec.component, index: index)
            let isPinned = pins.contains(DimensionPin(node: node.id, target: spec.target))
            let overlay = OverlayDimension(id: id, geometry: spec.geometry, text: style.text(reading, units: units),
                                           tint: isReference ? .dimensionReference : .dimensionDriving, isPinned: isPinned)
            return FeatureDimension(id: id, node: node.id, spec: spec, editing: editing, isPinned: isPinned, overlay: overlay)
        }

        /// The sketch dimension a spec names, when it is one the node's sketch still has.
        private func sketchDimension(of spec: DimensionSpec, on node: Node) -> SketchDimension? {
            guard case let .sketchDimension(id) = spec.target, case let .sketch(sketch)? = node.inputValues[NodeSetting.sketch]
            else { return nil }
            return sketch.dimensions[id]
        }

        private func exposedName(of spec: DimensionSpec, on node: Node) -> String? {
            guard let dimension = sketchDimension(of: spec, on: node), dimension.isExposed else { return nil }
            return dimension.name
        }

        /// How the spec is edited, or `nil` for a sketch dimension the sketch no longer has.
        private func editing(of spec: DimensionSpec, on node: Node, isRepeated: Bool) -> FeatureDimension.Editing? {
            let socket: SocketName
            switch spec.target {
            case let .input(name):
                socket = name
            case .sketchDimension:
                guard let dimension = sketchDimension(of: spec, on: node) else { return nil }
                guard dimension.isDriving else { return .reference(source: nil) }
                guard dimension.isExposed else { return .driving }
                socket = SocketName(dimension.name)
            }
            let wire = graph.incomingLink(to: Endpoint(node: node.id, socket: socket))
            if isRepeated { return .reference(source: wire.flatMap(source(of:))) }
            guard let wire else { return .driving }
            if let id = parameterID(of: wire), let parameter = content.graph.parameters.first(where: { $0.id == id }) {
                return .parameter(id, name: parameter.name, uses: uses(of: id))
            }
            return .reference(source: source(of: wire))
        }

        private func parameterID(of wire: Link) -> ParameterID? {
            guard let source = graph.nodes[wire.from.node], source.typeID == GraphParameterNode.typeID else { return nil }
            return source.inputValues[NodeSetting.parameter]?.parameterID
        }

        /// "from Number “width”", or "from Number" when the node still has its type's name.
        private func source(of wire: Link) -> String? {
            guard let node = graph.nodes[wire.from.node] else { return nil }
            let type = registry[node.typeID]?.displayName ?? node.typeID
            return node.name == type ? "from \(type)" : "from \(type) “\(node.name)”"
        }

        /// The distinct nodes that read the parameter through a Graph Parameter node, in the top level and in each group
        /// definition once.
        private func uses(of id: ParameterID) -> Int {
            ([content.graph] + content.definitions.values.map(\.graph)).reduce(0) { total, level in
                let readers = Set(level.nodes.values.filter {
                    $0.typeID == GraphParameterNode.typeID && $0.inputValues[NodeSetting.parameter]?.parameterID == id
                }.map(\.id))
                return total + Set(level.links.filter { readers.contains($0.from.node) }.map(\.to.node)).count
            }
        }
    }

    private struct SpecKey {
        var target: DimensionTarget
        var component: Int?
        var text: String { "\(target.key).\(component.map(String.init) ?? "-")" }
    }
}
