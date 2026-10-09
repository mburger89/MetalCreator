import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

/// Turns a node definition's inspector data into rows bound to the node's unwired inputs
/// (spec §6.4). Pure: tests check wired versus unwired binding without any UI.
public enum InspectorBuilder {
    public static func page(graph: Graph, selection: Set<NodeID>, registry: NodeRegistry,
                            results: [NodeID: NodeResult]) -> InspectorPage {
        let parameters = graph.parameters.map { ParameterRow(parameter: $0, range: parameterRange($0)) }
        guard selection.count == 1, let id = selection.first, let node = graph.nodes[id] else {
            return InspectorPage(header: nil, sections: [], parameters: parameters)
        }
        guard let definition = registry[node.typeID] else {
            let header = InspectorHeader(node: id, title: node.name, category: .value, state: results[id]?.state)
            let note = InspectorSectionRows(title: "Missing node",
                                            rows: [.readOnly(label: "Type", text: "“\(node.typeID)” isn't available")])
            return InspectorPage(header: header, sections: [note], parameters: parameters)
        }
        let header = InspectorHeader(node: id, title: node.name, category: definition.category, state: results[id]?.state)
        // `inputs(for:)`, not the static list: per-node sockets (exposed sketch dimensions) get their unit and default.
        // A declared inspector can't name them, so they follow its sections as fallback rows.
        let inputs = definition.inputs(for: node)
        let fixed = Set(definition.inputs.map(\.name))
        let declared = definition.inspector.isEmpty
            ? fallbackSections(inputs)
            : definition.inspector + fallbackSections(inputs.filter { !fixed.contains($0.name) })
        let sections = declared.map { section in
            InspectorSectionRows(title: section.title, rows: section.controls.map {
                row(for: $0, node: node, inputs: inputs, outputs: definition.outputs, graph: graph,
                    results: results)
            })
        }
        return InspectorPage(header: header, sections: sections, parameters: parameters)
    }

    /// A definition that declares no inspector gets one row per number, integer, bool or vector input.
    static func fallbackSections(_ inputs: [SocketSpec]) -> [InspectorSection] {
        let controls: [InspectorControl] = inputs.compactMap { spec in
            switch spec.type {
            case .number where spec.range == nil: .number(spec.name)
            case .number: .slider(spec.name)
            case .integer: .integer(spec.name)
            case .bool: .toggle(spec.name, label: InspectorLabel.text(for: spec.name))
            case .vector: .vector(spec.name)
            default: nil
            }
        }
        return controls.isEmpty ? [] : [InspectorSection(title: "Inputs", controls: controls)]
    }

    static func row(for control: InspectorControl, node: Node, inputs: [SocketSpec], outputs: [SocketSpec], graph: Graph,
                    results: [NodeID: NodeResult]) -> InspectorRow {
        guard let socket = control.socket else {
            if case .button(let title, let action) = control { return .button(title: title, action: action) }
            return .readOnly(label: "", text: "")
        }
        let label = InspectorLabel.text(for: socket)
        let spec = inputs.first { $0.name == socket }

        if case .ruleSummary = control {
            let ownOutput = spec == nil && outputs.contains { $0.name == socket }
            return .ruleSummary(label: label, summary: ruleSummary(socket, ownOutput: ownOutput, node: node, graph: graph,
                                                                   results: results))
        }
        if let link = graph.incomingLink(to: Endpoint(node: node.id, socket: socket)), let source = graph.nodes[link.from.node] {
            return .wired(label: label, source: "wired from \(source.name)")
        }

        // A name that isn't an input socket is a setting (M3's `NodeSetting`). `makeNode` seeds
        // settings from `defaultSettings`; a toggle with none stored (a hand-edited file) reads On.
        var value = node.inputValues[socket] ?? spec?.defaultValue
        var type = spec?.type
        if spec == nil, case .toggle = control {
            type = .bool
            if value == nil { value = .bool(true) }
        }
        let field = InputField(node: node.id, socket: socket, label: label, type: type, unit: spec?.unit ?? .none,
                               value: value, isOptional: spec?.isOptional ?? false)
        return valueRow(for: control, field: field, spec: spec, graph: graph)
    }

    /// The summary text of a `.ruleSummary` row. With `ownOutput` (M3's selection rules), it counts
    /// the node's own result; otherwise the rule wired into the input.
    static func ruleSummary(_ socket: SocketName, ownOutput: Bool, node: Node, graph: Graph,
                            results: [NodeID: NodeResult]) -> String {
        if ownOutput {
            guard let count = edgeCount(results[node.id]?.outputs?[socket]) else { return "No result yet" }
            return edgesText(count)
        }
        guard let link = graph.incomingLink(to: Endpoint(node: node.id, socket: socket)),
              let source = graph.nodes[link.from.node] else {
            return "No rule connected"
        }
        guard let count = edgeCount(results[source.id]?.outputs?[link.from.socket]) else { return source.name }
        return "\(source.name) · \(edgesText(count))"
    }

    /// The row for a control bound to an unwired input or a setting.
    static func valueRow(for control: InspectorControl, field: InputField, spec: SocketSpec?, graph: Graph) -> InspectorRow {
        if case .slider = control { return .slider(field, range: sliderRange(spec: spec, value: field.number)) }
        if case .number = control { return .number(field) }
        if case .integer = control { return .integer(field) }
        if case .toggle(_, let title) = control { return .toggle(field, label: title) }
        if case .segmented(_, let options) = control {
            return .segmented(field, options: options, selected: segmentIndex(field.value, options: options))
        }
        if case .planePicker = control { return .planePicker(field, selected: planeChoice(field.value)) }
        if case .anchorGrid = control { return .anchorGrid(field, selected: anchorIndex(field.value)) }
        if case .vector = control { return .vector(field) }
        if case .parameterPicker = control {
            let id = field.value?.parameterID
            let selected = graph.parameters.contains { $0.id == id } ? id : nil
            return .parameterPicker(field, options: graph.parameters, selected: selected)
        }
        return .readOnly(label: field.label, text: ValueText.format(field.value, unit: field.unit))
    }

    /// The plane picker's choice for a stored plane, or `nil` when none is stored.
    static func planeChoice(_ value: ConstantValue?) -> PlaneChoice? {
        if case .plane(let plane)? = value { return PlaneChoice(plane) }
        return nil
    }

    /// The anchor grid's cell (0…8, row-major from the top-left), or `nil` for anything else.
    static func anchorIndex(_ value: ConstantValue?) -> Int? {
        if case .integer(let index)? = value, (0...8).contains(index) { return index }
        return nil
    }

    static func edgesText(_ count: Int) -> String { "\(count) \(count == 1 ? "edge" : "edges")" }

    /// `value` with one component (0 x, 1 y, 2 z) replaced; a missing vector counts as zero.
    public static func vectorValue(_ value: ConstantValue?, axis: Int, to number: Double) -> ConstantValue? {
        var vector = Vector3.zero
        if case .vector(let current)? = value { vector = current }
        switch axis {
        case 0: vector.x = number
        case 1: vector.y = number
        case 2: vector.z = number
        default: return nil
        }
        return .vector(vector)
    }

    /// Which option a stored value selects: an integer index, a bool (false, true), or the option's text.
    static func segmentIndex(_ value: ConstantValue?, options: [String]) -> Int? {
        if case .integer(let index)? = value { return options.indices.contains(index) ? index : nil }
        if case .bool(let flag)? = value { return options.count == 2 ? (flag ? 1 : 0) : nil }
        if case .text(let text)? = value { return options.firstIndex(of: text) }
        return nil
    }

    /// The value a segmented control writes for option `index`, in the socket's own type.
    public static func segmentValue(_ index: Int, options: [String], type: SocketType?) -> ConstantValue? {
        guard options.indices.contains(index) else { return nil }
        switch type {
        case .integer?: return .integer(index)
        case .bool?: return .bool(index == 1)
        default: return .text(options[index])
        }
    }

    /// The socket's declared range, else a default for its unit, widened to include the value.
    static func sliderRange(spec: SocketSpec?, value: Double?) -> ClosedRange<Double> {
        let base: ClosedRange<Double>
        if let range = spec?.range {
            base = range
        } else {
            switch spec?.unit ?? .none {
            case .millimetres: base = 0...100
            case .degrees: base = 0...360
            case .count: base = 0...20
            case .none: base = 0...10
            }
        }
        guard let value, value.isFinite else { return base }
        return min(base.lowerBound, value)...max(base.upperBound, value)
    }

    static func parameterRange(_ parameter: GraphParameter) -> ClosedRange<Double> {
        var value = 0.0
        if case .number(let number) = parameter.value { value = number }
        if case .integer(let integer) = parameter.value { value = Double(integer) }
        let lower = min(parameter.min ?? 0, value)
        let upper = max(parameter.max ?? max(100, value * 2), value)
        return lower...max(upper, lower + 1)
    }

    /// The number of edges an edge-set output carries across its items, or `nil` if it isn't one.
    static func edgeCount(_ value: Value?) -> Int? {
        guard let value else { return nil }
        var total = 0
        for item in value.items {
            guard case .edgeSet(let set) = item else { return nil }
            total += set.edges.count
        }
        return total
    }
}
