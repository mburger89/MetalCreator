/// What VRML 1 carries from node to node: the transform so far, the points of the last `Coordinate3` and the face winding.
struct VRMLState {
    var matrix = VRMLMatrix.identity
    var points: [Float] = []
    var clockwise = false
}

extension VRMLScene {
    private enum Work {
        case node(VRMLNode, depth: Int)
        /// The state a `Separator` gives back when it ends.
        case restoreState(VRMLState)
        /// The transform a `TransformSeparator` gives back; everything else it did stays.
        case restoreMatrix(VRMLMatrix)
    }

    /// The top-level VRML 1 nodes in order. A `Separator` gives its children a copy of the state and drops it after, a
    /// `TransformSeparator` keeps only the transform from leaking, a `Group` shares the state with what follows it. The walk keeps
    /// its own stack instead of recursing.
    func evaluate1(_ roots: [VRMLNode]) throws {
        var state = VRMLState()
        var pending = roots.reversed().map { Work.node($0, depth: 1) }
        while let work = pending.popLast() {
            switch work {
            case .restoreState(let saved):
                state = saved
            case .restoreMatrix(let saved):
                state.matrix = saved
            case .node(let node, let depth):
                try visit(depth: depth)
                try evaluate(node, &state, depth: depth, pending: &pending)
            }
        }
    }

    private func evaluate(_ node: VRMLNode, _ state: inout VRMLState, depth: Int, pending: inout [Work]) throws {
        func push(_ nodes: [VRMLNode]) {
            for child in nodes.reversed() { pending.append(.node(child, depth: depth + 1)) }
        }
        switch node.type {
        case "Separator":
            pending.append(.restoreState(state))
            push(node.children)
        case "TransformSeparator":
            pending.append(.restoreMatrix(state.matrix))
            push(node.children)
        case "Group":
            push(node.children)
        case "Switch":
            push(Self.chosenChildren(of: node))
        case "Coordinate3":
            state.points = node.numbers("point") ?? []
        case "Transform", "Translation", "Rotation", "Scale", "MatrixTransform", "ShapeHints":
            Self.change(&state, by: node)
        case "Cube":
            let width = node.numbers("width")?.first ?? 2
            let height = node.numbers("height")?.first ?? 2
            let length = node.numbers("depth")?.first ?? 2
            try addBox(size: SIMD3(Double(width), Double(height), Double(length)), matrix: state.matrix,
                       reversed: state.clockwise)
        case "IndexedFaceSet":
            try addFaces(points: state.points, indices: node.numbers("coordIndex") ?? [], matrix: state.matrix,
                         counterClockwise: !state.clockwise)
        default:
            if Self.isUnread(node.type) { skippedGeometry = true }
        }
    }

    /// The nodes that only change what comes after them.
    private static func change(_ state: inout VRMLState, by node: VRMLNode) {
        switch node.type {
        case "Transform":
            state.matrix *= .transform(translation: node.numbers("translation"), rotation: node.numbers("rotation"),
                                       scale: node.numbers("scaleFactor"), scaleOrientation: node.numbers("scaleOrientation"),
                                       center: node.numbers("center"))
        case "Translation":
            state.matrix *= .transform(translation: node.numbers("translation"), rotation: nil, scale: nil,
                                       scaleOrientation: nil, center: nil)
        case "Rotation":
            state.matrix *= .transform(translation: nil, rotation: node.numbers("rotation"), scale: nil,
                                       scaleOrientation: nil, center: nil)
        case "Scale":
            state.matrix *= .transform(translation: nil, rotation: nil, scale: node.numbers("scaleFactor"),
                                       scaleOrientation: nil, center: nil)
        case "MatrixTransform":
            if let rows = node.numbers("matrix").flatMap(VRMLMatrix.init(rowMajor:)) { state.matrix *= rows }
        default:
            if let ordering = node.field("vertexOrdering")?.word { state.clockwise = ordering == "CLOCKWISE" }
        }
    }

    /// A VRML 1 `Switch`'s `whichChild`: none (-1, the default), all (-3) or one.
    private static func chosenChildren(of node: VRMLNode) -> [VRMLNode] {
        let chosen = node.numbers("whichChild")?.first ?? -1
        if chosen == -3 { return node.children }
        guard chosen >= 0, chosen < Float(node.children.count) else { return [] }
        return [node.children[Int(chosen)]]
    }
}
