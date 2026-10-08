import CreatorGeometry

/// One of the 54 tiles the view cube is drawn with. Each face is split 3 × 3, and each tile belongs to the face,
/// edge or corner region it sits in. Corners run counter-clockwise seen from outside.
struct ViewCubeCell: Sendable {
    let region: ViewCubeRegion
    let normal: Vector3
    let corners: [Vector3]

    static let all: [ViewCubeCell] = ViewCubeRegion.faces.flatMap { cells(on: $0) }

    static func cells(on face: ViewCubeRegion) -> [ViewCubeCell] {
        let n = face.direction
        // t1 × t2 = n, so corners listed along t1 then t2 wind counter-clockwise seen from +n.
        let t1: Vector3 = abs(n.z) > 0.5 ? .unitX : .unitZ
        let t2 = n.cross(t1)
        let edges = [-1.0, -1.0 / 3, 1.0 / 3, 1.0]
        var cells: [ViewCubeCell] = []
        for i in 0..<3 {
            for j in 0..<3 {
                let (a0, a1, b0, b1) = (edges[i], edges[i + 1], edges[j], edges[j + 1])
                func corner(_ a: Double, _ b: Double) -> Vector3 { n + t1 * a + t2 * b }
                let centre = n + t1 * ((a0 + a1) / 2) + t2 * ((b0 + b1) / 2)
                guard let region = ViewCubeRegion(x: ViewCubeLayout.cell(centre.x), y: ViewCubeLayout.cell(centre.y),
                                                  z: ViewCubeLayout.cell(centre.z)) else { continue }
                cells.append(ViewCubeCell(region: region, normal: n,
                                          corners: [corner(a0, b0), corner(a1, b0), corner(a1, b1), corner(a0, b1)]))
            }
        }
        return cells
    }
}
