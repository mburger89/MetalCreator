import CreatorGraph
import CreatorKernel

/// Which end of a loft a face belongs to.
enum LoftSide: CaseIterable {
    case start, end

    var faceSetting: SocketName { self == .start ? NodeSetting.startFace : NodeSetting.endFace }
    var continuitySocket: SocketName { self == .start ? "startContinuity" : "endContinuity" }
    var weightSocket: SocketName { self == .start ? "startWeight" : "endWeight" }
    var word: String { self == .start ? "start" : "end" }

    var pickAction: InspectorAction { self == .start ? .pickLoftStartFace : .pickLoftEndFace }
    var clearAction: InspectorAction { self == .start ? .clearLoftStartFace : .clearLoftEndFace }
}

/// What the Loft node shares about its two face ends (loft end conditions spec, Behaviour): the sockets, the inspector's rows (the
/// continuity shows only when that end has a face, the weight only for Tangent and Curvature) and reading the ends from the inputs.
enum LoftEndSetup {
    static let continuityOptions = ["Free", "Tangent (G1)", "Curvature (G2)"]
    static let weightRange: ClosedRange<Double> = 0.1...2

    static let sockets: [SocketSpec] = [SocketSpec("solid", .solid, optional: true)] + LoftSide.allCases.flatMap { side in
        [
            SocketSpec(side.continuitySocket, .integer, defaultValue: .integer(LoftContinuity.free.rawValue)),
            SocketSpec(side.weightSocket, .number, defaultValue: .number(1), range: weightRange),
        ]
    }

    static func hasFace(_ node: Node, _ side: LoftSide) -> Bool {
        if case .facePick? = node.inputValues[side.faceSetting] { return true }
        return false
    }

    static func continuity(of node: Node, _ side: LoftSide) -> LoftContinuity {
        if case .integer(let stored)? = node.inputValues[side.continuitySocket], let value = LoftContinuity(rawValue: stored) {
            return value
        }
        return .free
    }

    /// The Loft section for the ends: for each end the face status and its buttons, then the continuity when the end has a face,
    /// then the weight when the continuity is Tangent or Curvature.
    static func inspector(for node: Node) -> [InspectorSection] {
        LoftSide.allCases.map { side in
            var controls: [InspectorControl] = [
                .faceStatus(side.faceSetting),
                .button(title: "Pick \(side == .start ? "Start" : "End") Face in View…", action: side.pickAction),
            ]
            if hasFace(node, side) {
                controls.append(.button(title: "Clear \(side == .start ? "Start" : "End") Face", action: side.clearAction))
                controls.append(.segmented(side.continuitySocket, options: continuityOptions))
                if continuity(of: node, side) != .free { controls.append(.slider(side.weightSocket)) }
            }
            return InspectorSection(title: side == .start ? "Start" : "End", controls: controls)
        }
    }

    /// The part and the ends the node's settings and inputs ask for, with the warnings their picks earn.
    struct Ends {
        var part: Solid?
        var start: LoftEnd?
        var end: LoftEnd?
        var warnings: [String] = []

        var count: Int { (start == nil ? 0 : 1) + (end == nil ? 0 : 1) }
    }

    static func read(_ inputs: NodeInputs, context: EvalContext) throws -> Ends {
        var ends = Ends()
        let picked = LoftSide.allCases.filter { context.node.inputValues[$0.faceSetting] != nil }
        guard !picked.isEmpty else { return ends }
        for side in picked where !inputs.has("solid") {
            throw NodeError.invalidValue("Pick a face of the part for the loft's \(side.word).")
        }
        let part = try inputs.solid("solid")
        ends.part = part
        for side in picked {
            let (face, warnings) = try resolve(side, in: part, context: context)
            let continuity = LoftContinuity(rawValue: try inputs.choice(side.continuitySocket, options: continuityOptions)) ?? .free
            let end = LoftEnd(face: face.id, continuity: continuity, weight: try inputs.number(side.weightSocket))
            if side == .start { ends.start = end } else { ends.end = end }
            ends.warnings += warnings
        }
        return ends
    }

    static func resolve(_ side: LoftSide, in part: Solid, context: EvalContext) throws -> (FaceInfo, [String]) {
        let pick: FacePick
        switch context.node.inputValues[side.faceSetting] {
        case .facePick(let stored)?: pick = stored
        default: throw NodeError.invalidValue("The loft's \(side.word) face can't be read. Pick the face again.")
        }
        if let gone = part.topology.vanishedInstances(in: pick.tags).first {
            throw NodeError.invalidValue("Instance \(InstancePath.text(gone)) no longer exists, so the loft's \(side.word) face "
                + "isn't there any more. Pick the face again.")
        }
        let resolution = part.topology.resolution(of: pick)
        guard let face = resolution.faces.first else {
            throw NodeError.invalidValue("The loft's \(side.word) face isn't on this part any more. Pick it again.")
        }
        var warnings: [String] = []
        if resolution.isAmbiguous {
            warnings.append("The loft's \(side.word) face was merged with a face from another part of the model that has since changed, "
                + "so it isn't clear which part was picked. The loft uses the closest one; pick the face again to settle it.")
        } else if resolution.faces.count > 1 {
            warnings.append("The loft's \(side.word) pick matches \(resolution.faces.count.display) faces; the loft uses the first.")
        }
        if pick.touchesUnnamedFace {
            warnings.append("The loft's \(side.word) face has no stable name, so the loft may move to a different face when the model "
                + "changes. Pick it again after the change.")
        }
        return (face, warnings)
    }
}
