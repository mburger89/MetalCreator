import CreatorGraph
import CreatorNodes
import Testing

/// Every built-in definition's inspector and handles must be data the editor and viewport can
/// bind (spec §6.4–6.5): controls name real sockets (or declared settings) of the right type.
struct CatalogTests {
    func socket(of control: InspectorControl) -> SocketName? {
        switch control {
        case .slider(let name), .number(let name), .integer(let name), .planePicker(let name),
             .anchorGrid(let name), .ruleSummary(let name), .vector(let name), .parameterPicker(let name):
            name
        case .toggle(let name, _), .segmented(let name, _):
            name
        case .button:
            nil
        }
    }

    /// The socket types each control can edit. `nil` means a setting is required.
    func acceptedTypes(of control: InspectorControl) -> Set<SocketType> {
        switch control {
        case .slider, .number: [.number]
        case .integer, .segmented, .anchorGrid: [.integer]
        case .toggle: [.bool]
        case .planePicker: [.plane]
        case .ruleSummary: [.edgeSet]
        case .vector: [.vector]
        case .parameterPicker, .button: []
        }
    }

    @Test func typeIDsAreUniqueAndNamespaced() {
        let ids = BuiltInNodes.all.map { $0.typeID }  // A key path on a metatype crashes Swift 6.4 SILGen.
        #expect(Set(ids).count == ids.count)
        #expect(ids.allSatisfy { $0.hasPrefix("creator.") })
        #expect(BuiltInNodes.all.allSatisfy { BuiltInNodes.registry[$0.typeID] != nil })
    }

    @Test func everyNodeHasAnOutputAndUniqueSocketNames() {
        for definition in BuiltInNodes.all {
            #expect(!definition.outputs.isEmpty, "\(definition.typeID) has no outputs")
            #expect(Set(definition.inputs.map(\.name)).count == definition.inputs.count, "\(definition.typeID) repeats an input")
            #expect(Set(definition.outputs.map(\.name)).count == definition.outputs.count, "\(definition.typeID) repeats an output")
            #expect(Set(definition.defaultSettings.keys).isSubset(of: NodeSetting.all), "\(definition.typeID) seeds an unknown setting")
        }
    }

    /// A setting and an input socket of one name would share one `inputValues` key; the control test above skips settings
    /// before it looks sockets up, so this is what notices.
    @Test func noInputSocketIsNamedLikeASetting() {
        for definition in BuiltInNodes.all {
            let clashes = definition.inputs.map(\.name).filter { NodeSetting.all.contains($0) }
            #expect(clashes.isEmpty, "\(definition.typeID) has input sockets named like settings: \(clashes)")
        }
    }

    @Test func inspectorControlsBindRealSocketsOfTheRightType() {
        for definition in BuiltInNodes.all {
            for control in definition.inspector.flatMap(\.controls) {
                guard let name = socket(of: control) else { continue }
                if NodeSetting.all.contains(name) { continue }
                let sockets = definition.inputs + (control == .ruleSummary(name) ? definition.outputs : [])
                guard let spec = sockets.first(where: { $0.name == name }) else {
                    Issue.record("\(definition.typeID): \(control) names no socket")
                    continue
                }
                #expect(acceptedTypes(of: control).contains(spec.type), "\(definition.typeID): \(control) can't edit a \(spec.type)")
                if case .segmented(_, let options) = control {
                    #expect(options.count >= 2, "\(definition.typeID): \(control) needs at least two options")
                }
            }
        }
    }

    @Test func handlesEditNumberInputs() {
        for definition in BuiltInNodes.all {
            for handle in definition.handles {
                let name: SocketName = switch handle {
                case .linear(let socket), .radial(let socket): socket
                }
                let spec = definition.inputs.first { $0.name == name }
                #expect(spec?.type == .number, "\(definition.typeID): handle \(handle) needs a number input")
            }
        }
    }
}
