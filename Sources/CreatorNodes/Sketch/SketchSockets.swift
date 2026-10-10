import CreatorGraph
import CreatorSketch

/// The Sketch node's exposed-dimension sockets (sketcher spec §7): one number input per dimension
/// with `isExposed`, named after it, in name order, whose unwired value is the stored one.
enum SketchSockets {
    /// The exposed dimensions that are sockets, with their specs. A name the node already uses (a
    /// fixed input, a setting or a projection setting), an empty name or a repeated one is left out,
    /// and `refused` names it.
    static func exposed(_ sketch: Sketch) -> [(id: DimensionID, spec: SocketSpec)] {
        partition(sketch).sockets
    }

    /// Exposed dimensions that can't be sockets, as warnings for the node.
    static func refused(_ sketch: Sketch) -> [String] {
        partition(sketch).refused.map { refusal in
            if refusal.name.isEmpty {
                return "An exposed dimension has no name, so it isn't an input. Name it to expose it."
            }
            return refusal.isRepeat
                ? "Dimension “\(refusal.name)” can't be an input: another exposed dimension has the same name. Rename one of them."
                : "Dimension “\(refusal.name)” can't be an input: the node already has an input or setting with that name. Rename it."
        }
    }

    private static func partition(_ sketch: Sketch)
        -> (sockets: [(id: DimensionID, spec: SocketSpec)], refused: [(name: String, isRepeat: Bool)]) {
        var sockets: [(id: DimensionID, spec: SocketSpec)] = []
        var refused: [(name: String, isRepeat: Bool)] = []
        var used = Set<String>()
        let exposed = sketch.dimensionIDs.compactMap { id in sketch.dimensions[id].map { (id, $0) } }
            .filter { $0.1.isExposed }
            .sorted { ($0.1.name, $0.0) < ($1.1.name, $1.0) }
        for (id, dimension) in exposed {
            guard !isReserved(dimension.name) else {
                refused.append((dimension.name, false))
                continue
            }
            guard used.insert(dimension.name).inserted else {
                refused.append((dimension.name, true))
                continue
            }
            let unit: ValueUnit = if case .angle = dimension.kind { .degrees } else { .millimetres }
            sockets.append((id, SocketSpec(SocketName(dimension.name), .number, defaultValue: .number(dimension.value), unit: unit)))
        }
        return (sockets, refused)
    }

    /// Names an exposed dimension may not take.
    static func isReserved(_ name: String) -> Bool {
        name.isEmpty || name.hasPrefix(NodeSetting.projectionPrefix) || NodeSetting.all.contains(SocketName(name))
            || SketchNode.inputs.contains { $0.name.rawValue == name }
    }
}
