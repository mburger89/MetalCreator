import CreatorGeometry
import Foundation

/// Writes binary STL (implicit spec §5.3): the 80-byte header, the triangle count, and for each triangle its normal, its three corners
/// and a two-byte attribute, all little-endian `Float`s in millimetres. Meshes and tessellated solids add to one writer and come out
/// as one file. A triangle's normal is computed from its corners (counter-clockwise seen from outside); a triangle with no area gets a
/// zero normal, which readers take as "work it out".
public struct STLWriter: Sendable {
    /// The header: no "solid" at the start, which would make some readers take the file for ASCII STL.
    static let header: [UInt8] = {
        var bytes = Array("MetalCreator binary STL, millimetres".utf8)
        bytes += [UInt8](repeating: 0, count: 80 - bytes.count)
        return bytes
    }()

    public private(set) var triangleCount = 0
    private var body = Data()

    public init() {}

    /// Adds every triangle of `mesh`.
    public mutating func add(_ mesh: TriangleMesh) {
        body.reserveCapacity(body.count + 50 * mesh.triangleCount)
        for index in 0..<mesh.triangleCount {
            let corners = (0..<3).map { mesh.positions[Int(mesh.triangles[3 * index + $0])] }
            append(corners[0], corners[1], corners[2])
        }
    }

    /// Adds the triangles `indices` (three per triangle) make of `positions`, such as a solid's tessellation.
    public mutating func add(positions: [Vector3], indices: [UInt32]) {
        body.reserveCapacity(body.count + 50 * (indices.count / 3))
        for base in stride(from: 0, to: indices.count - 2, by: 3) {
            let corners = (0..<3).map { positions[Int(indices[base + $0])] }
            append(SIMD3(Float(corners[0].x), Float(corners[0].y), Float(corners[0].z)),
                   SIMD3(Float(corners[1].x), Float(corners[1].y), Float(corners[1].z)),
                   SIMD3(Float(corners[2].x), Float(corners[2].y), Float(corners[2].z)))
        }
    }

    private mutating func append(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        let (u, v) = (b - a, c - a)
        let cross = SIMD3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
        let length = (cross * cross).sum().squareRoot()
        let normal = length > 0 ? cross / length : SIMD3<Float>.zero
        for vector in [normal, a, b, c] {
            for component in [vector.x, vector.y, vector.z] {
                withUnsafeBytes(of: component.bitPattern.littleEndian) { body.append(contentsOf: $0) }
            }
        }
        body.append(contentsOf: [0, 0])
        triangleCount += 1
    }

    /// The finished file.
    public func data() -> Data {
        var file = Data(Self.header)
        withUnsafeBytes(of: UInt32(triangleCount).littleEndian) { file.append(contentsOf: $0) }
        file.append(body)
        return file
    }
}
