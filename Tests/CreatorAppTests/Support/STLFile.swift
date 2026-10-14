// Test fixture file: a binary STL read back, to check what an export wrote.
import Foundation

struct STLFile {
    var triangles: [(normal: SIMD3<Float>, corners: [SIMD3<Float>])]

    /// `nil` unless `data` is exactly a header, a count and that many 50-byte triangles.
    init?(_ data: Data) {
        guard data.count >= 84 else { return nil }
        let count = data.subdata(in: 80..<84).withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard data.count == 84 + 50 * count else { return nil }
        func float(_ offset: Int) -> Float {
            let bits = data.subdata(in: offset..<offset + 4).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
            return Float(bitPattern: bits)
        }
        triangles = (0..<count).map { index in
            let base = 84 + 50 * index
            let vectors = (0..<4).map { SIMD3(float(base + 12 * $0), float(base + 12 * $0 + 4), float(base + 12 * $0 + 8)) }
            return (vectors[0], Array(vectors[1...]))
        }
    }

    /// The enclosed volume of a closed, outward-wound surface.
    var volume: Double {
        triangles.reduce(0) { sum, triangle in
            let (a, b, c) = (triangle.corners[0], triangle.corners[1], triangle.corners[2])
            let cross = SIMD3(b.y * c.z - b.z * c.y, b.z * c.x - b.x * c.z, b.x * c.y - b.y * c.x)
            return sum + Double((a * cross).sum()) / 6
        }
    }
}
