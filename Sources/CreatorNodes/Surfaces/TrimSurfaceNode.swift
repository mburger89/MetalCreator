import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A sheet with the regions you keep: it is divided by curves or a body and the pieces you pick, or those inside or outside a
/// closed cutter, remain (NS-4, R4, R5). The whole split is the `pieces` output, which a keep pick names.
public enum TrimSurfaceNode: NodeDefinition {
    public static let typeID = "creator.trimSurface"
    public static let displayName = "Trim Surface"
    public static let category = NodeCategory.surface
    public static let librarySubgroup: String? = "Edit"
    public static let keepOptions = ["Picked", "Inside", "Outside"]
    public static let nothingPicked = "Pick the regions to keep; until then Trim Surface keeps every piece."
    /// Defensive: the kernel refuses a cutter that cuts nothing first, so no known input reaches these two.
    public static let nothingInside = "No piece of the surface lies inside the cutter."
    public static let nothingOutside = "No piece of the surface lies outside the cutter."
    public static let needsClosedCutter = "Inside and Outside need a closed cutter: closed flat curves or a closed solid. "
        + "Pick the regions to keep instead."
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.keepRegions: .regionPicks([])]
    public static let inputs = [SocketSpec("surface", .solid)] + TrimCutterInput.cutterInputs + [
        SocketSpec("keep", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("surface", .solid), SocketSpec("pieces", .solid)]
    public static let previewHiddenOutputs: Set<SocketName> = ["pieces"]

    public static func inspector(for node: Node) -> [InspectorSection] {
        var controls = TrimCutterInput.controls(for: node)
        controls.append(.segmented("keep", options: keepOptions))
        if keep(of: node) == 0 {
            let count = node.inputValues[NodeSetting.keepRegions]?.regionPicks?.count ?? 0
            controls.append(.note(count == 0 ? "No regions picked" : count == 1 ? "1 region picked" : "\(count.display) regions picked"))
            controls.append(.button(title: "Pick regions in view…", action: .pickTrimRegions))
            controls.append(.button(title: "Clear regions", action: .clearTrimRegions))
        }
        return [InspectorSection(title: "Trim Surface", controls: controls)]
    }

    private static func keep(of node: Node) -> Int {
        if case .integer(let stored)? = node.inputValues["keep"] { return stored }
        return 0
    }

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let surface = try inputs.solid("surface")
        let keep = try inputs.choice("keep", options: keepOptions)
        let cutter = try await TrimCutterInput.read(inputs, node: displayName, kernel: kernel, tag: context.tag)
        let split = try await kernel.split(surface, by: cutter, tag: context.tag)
        var warnings = split.warnings
        var kept = Array(split.pieces.indices)
        switch keep {
        case 1, 2:
            guard let inside = split.inside else { throw NodeError.invalidValue(needsClosedCutter) }
            kept = split.pieces.indices.filter { index in
                let faces = split.pieces[index]
                return keep == 1 ? faces.allSatisfy(inside.contains) : !faces.contains(where: inside.contains)
            }
            if kept.isEmpty {
                throw NodeError.invalidValue(keep == 1 ? nothingInside : nothingOutside)
            }
        default:
            let picks = context.node.inputValues[NodeSetting.keepRegions]?.regionPicks ?? []
            if picks.isEmpty {
                warnings.append(nothingPicked)
            } else {
                let resolved = TrimRegions.resolve(picks, pieces: split.pieces, in: split.whole.topology)
                warnings += resolved.warnings
                if resolved.pieces.isEmpty { throw NodeError.invalidValue(TrimRegions.nothingLeft) }
                kept = resolved.pieces
            }
        }
        let result: Solid
        if kept.count == split.pieces.count {
            result = split.whole
        } else {
            let faces = kept.flatMap { split.pieces[$0] }.sorted { $0.rawValue < $1.rawValue }
            result = try await kernel.subSheet(faces, of: split.whole)
        }
        return NodeOutputs(["surface": .solid(result), "pieces": .solid(split.whole)], warnings: warnings)
    }
}
