import CreatorGraph
import CreatorKernel

extension EditorModel {
    /// What the context inspector shows now.
    public var inspectorPage: InspectorPage {
        InspectorBuilder.page(graph: graphWithDocumentParameters, selection: selection, registry: registry,
                              results: levelResults)
    }

    /// The graph shown, with the document's parameters: they belong to the top level, and nodes inside a group read
    /// them too (`Evaluator` hands every level the top level's), so the inspector lists and offers them there.
    var graphWithDocumentParameters: Graph {
        var shown = graph
        shown.parameters = rootGraph.parameters
        return shown
    }

    /// Sets an unwired input. `continuous` edits (slider steps) share one coalescing key per
    /// socket, so a whole drag is one undo step; it ends when the selection changes, the canvas
    /// is pressed, another edit is made, or on undo (MetalUI's `Slider` reports no drag end yet).
    public func setInput(_ field: InputField, to value: ConstantValue, continuous: Bool = false) {
        guard value != field.value else { return }
        let key = continuous ? "input-\(field.node.rawValue.uuidString)-\(field.socket.rawValue)" : nil
        do {
            try edit(.setInput(field.node, field.socket, value), coalescingKey: key)
        } catch {
            refuse(error.message, node: field.node)
        }
    }

    /// Unsets an optional input (an empty field), so the node treats it as not given, as one undo
    /// step. A required input is left alone: clearing it would silently fall back to its default.
    public func clearInput(_ field: InputField) {
        guard field.isOptional, graph.nodes[field.node]?.inputValues[field.socket] != nil else { return }
        do {
            try edit(.setInput(field.node, field.socket, nil))
        } catch {
            refuse(error.message, node: field.node)
        }
    }

    /// A number from a slider or a typed field. Integer sockets get it rounded to a whole number;
    /// one no `Int` holds ("1e300") is refused rather than trapping.
    public func setNumber(_ field: InputField, to number: Double, continuous: Bool = false) {
        guard field.type == .integer else {
            setInput(field, to: .number(number), continuous: continuous)
            return
        }
        guard let whole = ValueText.wholeNumber(number) else {
            refuse("Enter a whole number.", node: field.node)
            return
        }
        setInput(field, to: .integer(whole), continuous: continuous)
    }

    /// One typed component (0 x, 1 y, 2 z) of a vector field.
    public func setVectorComponent(_ field: InputField, axis: Int, to number: Double) {
        guard let value = InspectorBuilder.vectorValue(field.value, axis: axis, to: number) else { return }
        setInput(field, to: value)
    }

    /// A parameter picker's choice, stored in the node's setting in M3's encoding (`CreatorGraph`).
    public func chooseParameter(_ id: ParameterID, for field: InputField) {
        setInput(field, to: .parameter(id))
    }

    /// Sets a document parameter; `continuous` coalesces like `setInput`.
    public func setParameter(_ id: ParameterID, to value: ConstantValue, continuous: Bool = false) {
        let key = continuous ? "parameter-\(id.rawValue.uuidString)" : nil
        do {
            try document.perform(.setParameter(id, value), coalescingKey: key)
        } catch {
            refuse(error.message, node: nil)
        }
    }

    /// A number for a parameter, as a whole number for an integer parameter (refused if no `Int` holds it).
    public func setParameterNumber(_ id: ParameterID, to number: Double, continuous: Bool = false) {
        guard let parameter = rootGraph.parameters.first(where: { $0.id == id }) else { return }
        guard parameter.type == .integer else {
            setParameter(id, to: .number(number), continuous: continuous)
            return
        }
        guard let whole = ValueText.wholeNumber(number) else {
            refuse("Enter a whole number.", node: nil)
            return
        }
        setParameter(id, to: .integer(whole), continuous: continuous)
    }

    /// An inspector button: recorded for the viewport, which owns pick mode (M4/M6).
    public func press(_ action: InspectorAction, on node: NodeID) {
        requestSerial += 1
        setInspectorRequest(InspectorRequest(node: node, action: action, serial: requestSerial))
    }
}
