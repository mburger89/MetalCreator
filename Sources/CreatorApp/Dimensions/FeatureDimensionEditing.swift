import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorSketch
import CreatorViewport

/// Why a typed value for a feature dimension was not taken, in plain language for the value box.
struct FeatureEditRefusal: Error, Equatable {
    var message: String
}

/// What editing a feature dimension means (spec §3.1): the box it opens with, the typed text checked, and the graph command
/// that stores the value. Nothing here touches the document; `AppModel.commitFeatureValue` performs the command checked.
enum FeatureDimensionEditing {
    private static let gone = FeatureEditRefusal(message: "That dimension is gone.")

    /// What the box opens with, or `nil` for a reference (no box).
    static func boxContent(_ dimension: FeatureDimension, units: DocumentUnits) -> DimensionValueBoxContent? {
        let text = units.editText(dimension.spec.value, quantity: dimension.spec.quantity)
        switch dimension.editing {
        case .driving:
            return DimensionValueBoxContent(text: text, note: nil)
        case .parameter(_, let name, let uses):
            return DimensionValueBoxContent(text: text, note: "\(name) (parameter, used by \(uses) \(uses == 1 ? "feature" : "features"))")
        case .reference:
            return nil
        }
    }

    /// The value typed, in millimetres, degrees or a count: `.success(nil)` when it is the value the dimension has already
    /// (nothing to do), a refusal when it is not a number or not allowed for the quantity.
    static func value(from text: String, for dimension: FeatureDimension, units: DocumentUnits) -> Result<Double?, FeatureEditRefusal> {
        let quantity = dimension.spec.quantity
        guard let value = units.parse(text, quantity: quantity) else {
            // A count is parsed only when whole; a number that is not says what a count is.
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if quantity == .count, let number = Double(trimmed), number.isFinite { return .failure(wholeCount) }
            return .failure(FeatureEditRefusal(message: "“\(trimmed)” isn't a number."))
        }
        let current = dimension.spec.value
        if value == current || units.editText(value, quantity: quantity) == units.editText(current, quantity: quantity) {
            return .success(nil)
        }
        if let refusal = refusal(for: value, quantity: quantity, units: units) { return .failure(refusal) }
        return .success(value)
    }

    private static let wholeCount = FeatureEditRefusal(message: "A count must be a whole number of 1 or more.")

    private static func refusal(for value: Double, quantity: DimensionQuantity, units: DocumentUnits) -> FeatureEditRefusal? {
        switch quantity {
        case .length, .radius, .diameter:
            value > 0 ? nil : FeatureEditRefusal(message: "A length must be more than 0 \(units.length.symbol).")
        case .angle:
            value > 0 && value <= 360 ? nil : FeatureEditRefusal(message: "An angle must be more than 0° and at most 360°.")
        case .count:
            value >= 1 && value == value.rounded() ? nil : wholeCount
        }
    }

    /// The command that stores `value` (millimetres, degrees or a count) for `dimension`, where it applies and as which step:
    /// - a parameter edit is at the top level (`nil` path) as "Change Parameter", refused outside the parameter's range;
    /// - any other is at `level`, the graph the dimension is shown in, as "Change Dimension".
    @MainActor
    static func command(for dimension: FeatureDimension, value: Double, graph: Graph, document: DocumentModel,
                        level: GraphPath = .root) -> Result<(GraphCommand, GraphPath?, String), FeatureEditRefusal> {
        switch dimension.editing {
        case .reference:
            return .failure(FeatureEditRefusal(message: "That dimension is calculated, so it can't be changed here."))
        case .parameter(let id, let name, _):
            return parameterCommand(id, name: name, dimension: dimension, value: value, document: document)
        case .driving:
            guard let node = graph.nodes[dimension.node] else { return .failure(gone) }
            switch dimension.spec.target {
            case .input(let socket):
                return inputCommand(socket, of: node, dimension: dimension, value: value, document: document)
                    .map { ($0, level, UndoName.changeDimension) }
            case .sketchDimension(let id):
                guard case .sketch(let sketch)? = node.inputValues[NodeSetting.sketch], let stored = sketch.dimensions[id] else {
                    return .failure(gone)
                }
                if stored.isExposed {
                    return .success((.setInput(node.id, SocketName(stored.name), .number(value)), level, UndoName.changeDimension))
                }
                return sketchCommand(id, of: node, value: value, graph: graph).map { ($0, level, UndoName.changeDimension) }
            }
        }
    }

    /// The parameter set to what the input will read: `value` times the spec's scale, held to the parameter's own range.
    @MainActor
    private static func parameterCommand(_ id: ParameterID, name: String, dimension: FeatureDimension, value: Double,
                                         document: DocumentModel) -> Result<(GraphCommand, GraphPath?, String), FeatureEditRefusal> {
        guard let parameter = document.graph.parameters.first(where: { $0.id == id }) else { return .failure(gone) }
        let stored = value * dimension.spec.inputScale
        let units = document.units
        let quantity = dimension.spec.quantity.isLength ? DimensionQuantity.length : dimension.spec.quantity
        if parameter.min != nil || parameter.max != nil, stored < (parameter.min ?? -.infinity) || stored > (parameter.max ?? .infinity) {
            let range = switch (parameter.min, parameter.max) {
            case let (low?, high?): "between \(units.fieldText(low, quantity: quantity)) and \(units.fieldText(high, quantity: quantity))"
            case let (low?, nil): "at least \(units.fieldText(low, quantity: quantity))"
            case let (nil, high?): "at most \(units.fieldText(high, quantity: quantity))"
            case (nil, nil): ""
            }
            return .failure(FeatureEditRefusal(message: "\(name) must be \(range)."))
        }
        let constant: ConstantValue = parameter.type == .integer ? .integer(Int(stored.rounded())) : .number(stored)
        return .success((.setParameter(id, constant), nil, UndoName.changeParameter))
    }

    /// The input set to `value` times the spec's scale: a whole number for an integer socket, one element of a vector.
    @MainActor
    private static func inputCommand(_ socket: SocketName, of node: Node, dimension: FeatureDimension, value: Double,
                                     document: DocumentModel) -> Result<GraphCommand, FeatureEditRefusal> {
        guard let spec = document.registry[node.typeID]?.inputs.first(where: { $0.name == socket }) else { return .failure(gone) }
        let scaled = value * dimension.spec.inputScale
        let constant: ConstantValue
        switch spec.type {
        case .integer:
            constant = .integer(Int(scaled.rounded()))
        case .vector:
            guard let component = dimension.spec.component, (0..<3).contains(component) else { return .failure(gone) }
            var current = Vector3.zero
            if case .vector(let stored)? = node.inputValues[socket] ?? spec.defaultValue { current = stored }
            let parts = [current.x, current.y, current.z].enumerated().map { $0.offset == component ? scaled : $0.element }
            constant = .vector(Vector3(parts[0], parts[1], parts[2]))
        default:
            constant = .number(scaled)
        }
        return .success(.setInput(node.id, socket, constant))
    }

    /// The commands that store the sketch dimension `id` of `node` set to `value`: the sketch solved first (nothing is stored for
    /// a value it cannot satisfy), its solution remembered as the warm start, stored as `SketchStore` does for the editor.
    static func sketchCommand(_ id: DimensionID, of node: Node, value: Double, graph: Graph)
        -> Result<GraphCommand, FeatureEditRefusal> {
        guard case .sketch(var sketch)? = node.inputValues[NodeSetting.sketch], sketch.dimensions[id] != nil else {
            return .failure(gone)
        }
        sketch.dimensions[id]?.value = value
        let solution = SketchSolver.solve(sketch)
        switch solution.status {
        case .overConstrained: return .failure(FeatureEditRefusal(message: "That value would over-constrain the sketch."))
        case .failed(let reason): return .failure(FeatureEditRefusal(message: reason))
        case .solved, .underConstrained: break
        }
        sketch.remember(solution)
        return .success(.batch(SketchStore.commands(storing: sketch, in: node, graph: graph)))
    }
}
