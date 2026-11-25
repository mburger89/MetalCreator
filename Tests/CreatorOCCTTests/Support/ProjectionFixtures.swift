#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorOCCT

extension ProjectionTests {
    /// A 10 x 20 x 30 box with its corner at the origin.
    func cornerBox(origin: Vector3 = .zero, size: Vector3 = Vector3(10, 20, 30), tag: NodeTag? = nil) async throws -> Solid {
        let plane = Plane(origin: origin + Vector3(size.x / 2, size.y / 2, 0), normal: .unitZ, xAxis: .unitX)
        return try await kernel.extrude(.rectangle(width: size.x, height: size.y, plane: plane), distance: size.z, mode: .oneSided,
                                        tag: tag ?? self.tag)
    }

    /// A cylinder of radius 5 and height 20 on the origin, axis +Z.
    func cylinder() async throws -> Solid {
        try await kernel.extrude(.circle(radius: 5, center: .zero, plane: .xy), distance: 20, mode: .oneSided, tag: tag)
    }

    func lines(_ projection: Projection2D, _ visibility: LineVisibility, _ lineClass: LineClass? = nil) -> [ProjectedLine] {
        projection.lines.filter { $0.visibility == visibility && (lineClass == nil || $0.lineClass == lineClass) }
    }

    func union(_ rects: [Rect2D]) -> Rect2D? {
        rects.dropFirst().reduce(rects.first) { $0?.union($1) }
    }

    func length(_ curve: ProjectedCurve) -> Double {
        switch curve {
        case .line(let a, let b): (a - b).length
        case .arc(_, let radius, _, let sweep): radius * abs(sweep)
        case .ellipse(_, _, let major, let minor, _, let sweep): (major + minor) / 2 * abs(sweep)
        case .polyline(let points): zip(points, points.dropFirst()).reduce(0) { $0 + ($1.0 - $1.1).length }
        }
    }

    func edgeIDs(_ lines: [ProjectedLine]) -> Set<EdgeID> {
        Set(lines.compactMap { if case .edge(let id)? = $0.source { id } else { nil } })
    }

    func faceEdges(_ solid: Solid, normal: Vector3) throws -> Set<EdgeID> {
        let face = try #require(solid.topology.faces.first { ($0.normal ?? .zero).dot(normal) > 0.999 })
        return Set(solid.topology.edges.filter { $0.faces.contains(face.id) }.map(\.id))
    }
}
#endif
