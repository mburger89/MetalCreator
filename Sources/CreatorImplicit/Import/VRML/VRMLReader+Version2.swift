extension VRMLScene {
    private static let unreadGeometry: Set<String> = [
        "Sphere", "Cone", "Cylinder", "ElevationGrid", "Extrusion", "IndexedLineSet", "PointSet", "Text", "AsciiText"
    ]

    /// Nodes that only pass their `children` on, in VRML 2 and X3D alike.
    static let groupingTypes: Set<String> = ["Group", "Collision", "Billboard", "Anchor"]

    static func isUnread(_ type: String) -> Bool { unreadGeometry.contains(type) }

    private struct Work {
        var node: VRMLNode
        var matrix: VRMLMatrix
        var depth: Int
    }

    /// The top-level VRML 2 nodes under the identity. Grouping nodes pass their children on, a `Shape` its geometry, and geometry
    /// makes triangles. The walk keeps its own stack instead of recursing, so depth costs the thread's stack nothing; children are
    /// pushed in reverse to be read in order.
    func evaluate2(_ roots: [VRMLNode]) throws {
        var pending = roots.reversed().map { Work(node: $0, matrix: .identity, depth: 1) }
        while let work = pending.popLast() {
            try visit(depth: work.depth)
            var matrix = work.matrix
            let children = try children2(of: work.node, matrix: &matrix)
            for child in children.reversed() { pending.append(Work(node: child, matrix: matrix, depth: work.depth + 1)) }
        }
    }

    /// The nodes a VRML 2 node passes on (moving `matrix` by its own transform), after making the triangles it holds itself.
    private func children2(of node: VRMLNode, matrix: inout VRMLMatrix) throws -> [VRMLNode] {
        switch node.type {
        case "Transform":
            matrix *= VRMLMatrix.transform(
                translation: node.numbers("translation"), rotation: node.numbers("rotation"), scale: node.numbers("scale"),
                scaleOrientation: node.numbers("scaleOrientation"), center: node.numbers("center"))
            return node.nodes("children")
        case _ where Self.groupingTypes.contains(node.type):
            return node.nodes("children")
        case "Switch":
            let choices = node.nodes("choice") + node.nodes("children")
            guard let chosen = node.numbers("whichChoice")?.first, chosen >= 0, chosen < Float(choices.count) else { return [] }
            return [choices[Int(chosen)]]
        case "Shape":
            return node.nodes("geometry")
        default:
            try makeGeometry2(node, matrix: matrix)
            return []
        }
    }

    private func makeGeometry2(_ node: VRMLNode, matrix: VRMLMatrix) throws {
        switch node.type {
        case "Inline":
            referencesFiles = true
        case "IndexedFaceSet":
            try addFaces(points: node.nodes("coord").first?.numbers("point") ?? [], indices: node.numbers("coordIndex") ?? [],
                         matrix: matrix, counterClockwise: node.field("ccw")?.word != "FALSE")
        case "Box":
            let size = node.numbers("size").flatMap { $0.count >= 3 ? $0 : nil } ?? [2, 2, 2]
            try addBox(size: SIMD3(Double(size[0]), Double(size[1]), Double(size[2])), matrix: matrix, reversed: false)
        default:
            if Self.isUnread(node.type) { skippedGeometry = true }
        }
    }
}
