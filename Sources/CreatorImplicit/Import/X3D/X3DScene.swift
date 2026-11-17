extension VRMLScene {
    private struct Work {
        var node: X3DNode
        var matrix: VRMLMatrix
        var depth: Int
    }

    /// The `X3D` element under the identity, walked with its own stack as `evaluate2` is.
    func evaluateX3D(_ root: X3DNode) throws {
        var pending = [Work(node: root, matrix: .identity, depth: 1)]
        while let work = pending.popLast() {
            try visit(depth: work.depth)
            var matrix = work.matrix
            let children = try children(of: work.node, matrix: &matrix)
            for child in children.reversed() { pending.append(Work(node: child, matrix: matrix, depth: work.depth + 1)) }
        }
    }

    private func children(of node: X3DNode, matrix: inout VRMLMatrix) throws -> [X3DNode] {
        switch node.type {
        case "Transform":
            matrix *= VRMLMatrix.transform(translation: node.translation, rotation: node.rotation, scale: node.scale,
                                           scaleOrientation: node.scaleOrientation, center: node.center)
            return node.children
        case _ where Self.groupingTypes.contains(node.type) || ["X3D", "Scene", "StaticGroup", "Shape"].contains(node.type):
            return node.children
        case "LOD":
            let readable = node.children.first { X3DBuilder.isReadable($0.type) }
            return readable.map { [$0] } ?? []
        case "Switch":
            guard node.whichChoice >= 0, node.whichChoice < Float(node.children.count) else { return [] }
            return [node.children[Int(node.whichChoice)]]
        default:
            try makeGeometryX3D(node, matrix: matrix)
            return []
        }
    }

    private func makeGeometryX3D(_ node: X3DNode, matrix: VRMLMatrix) throws {
        switch node.type {
        case "IndexedFaceSet":
            try addFaces(points: points(of: node), indices: node.index, matrix: matrix, counterClockwise: node.counterClockwise)
        case "IndexedTriangleSet":
            try addTriangles(points: points(of: node), indices: node.index, matrix: matrix, counterClockwise: node.counterClockwise)
        case "Box":
            let size = node.size.flatMap { $0.count >= 3 ? $0 : nil } ?? [2, 2, 2]
            try addBox(size: SIMD3(Double(size[0]), Double(size[1]), Double(size[2])), matrix: matrix, reversed: false)
        case "Inline":
            referencesFiles = true
        default:
            if X3DBuilder.isUnread(node.type) { skippedGeometry = true }
        }
    }

    private func points(of node: X3DNode) -> [Float] {
        node.children.first { $0.type == "Coordinate" || $0.type == "CoordinateDouble" }?.point ?? []
    }
}
