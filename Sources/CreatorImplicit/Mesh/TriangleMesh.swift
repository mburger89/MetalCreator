import CreatorGeometry
import CreatorGraph
import Foundation

/// A triangle mesh (implicit spec §2.2): `positions` in millimetres (stored as `Float`), `triangles` three indices per face,
/// counter-clockwise seen from outside, and a unit `normals` entry per vertex (empty when unknown). Immutable and `Sendable`
/// (arrays are copy-on-write, so a copy is cheap), never saved. A mesh from the Mesh node is watertight and manifold: every edge has
/// exactly two faces, consistently oriented.
public struct TriangleMesh: MeshPayload, Sendable {
    /// Identifies this mesh, so a refined pass can replace the one it came from. A new mesh gets a new ID.
    public let id: UUID
    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var triangles: [UInt32]
    /// The voxel size it was made at, in millimetres; 0 when unknown.
    public var resolution: Double
    public var quality: MeshQuality
    public var highlights: [MeshHighlight]
    /// What a preview refinement meshes, when this mesh is a preview of an implicit.
    public var source: MeshSource?

    public init(positions: [SIMD3<Float>], normals: [SIMD3<Float>] = [], triangles: [UInt32], resolution: Double = 0,
                quality: MeshQuality = .preview, highlights: [MeshHighlight] = [], source: MeshSource? = nil, id: UUID = UUID()) {
        self.id = id
        self.positions = positions
        self.normals = normals
        self.triangles = triangles
        self.resolution = resolution
        self.quality = quality
        self.highlights = highlights
        self.source = source
    }

    public var vertexCount: Int { positions.count }
    public var triangleCount: Int { triangles.count / 3 }

    /// 16 per vertex and 12 per triangle (implicit spec §2.2).
    public var estimatedBytes: Int { 16 * positions.count + 12 * triangleCount }

    /// The three corners of triangle `index`.
    public func corners(of index: Int) -> (Vector3, Vector3, Vector3) {
        (point(Int(triangles[3 * index])), point(Int(triangles[3 * index + 1])), point(Int(triangles[3 * index + 2])))
    }

    public func point(_ vertex: Int) -> Vector3 {
        let p = positions[vertex]
        return Vector3(Double(p.x), Double(p.y), Double(p.z))
    }

    /// The box around the vertices, or `nil` for an empty mesh.
    public var bounds: BoundingBox? { BoundingBox(points: positions.map { Vector3(Double($0.x), Double($0.y), Double($0.z)) }) }

    /// The enclosed volume in cubic millimetres: positive for a closed mesh wound counter-clockwise seen from outside.
    public var signedVolume: Double {
        var sum = 0.0
        for index in 0..<triangleCount {
            let (a, b, c) = corners(of: index)
            sum += a.dot(b.cross(c))
        }
        return sum / 6
    }

    /// The area of all faces in square millimetres.
    public var surfaceArea: Double {
        var sum = 0.0
        for index in 0..<triangleCount {
            let (a, b, c) = corners(of: index)
            sum += (b - a).cross(c - a).length / 2
        }
        return sum
    }

    /// This mesh with other highlights (checks return their input flagged).
    public func highlighting(_ highlights: [MeshHighlight]) -> TriangleMesh {
        var copy = self
        copy.highlights = highlights
        return copy
    }
}
