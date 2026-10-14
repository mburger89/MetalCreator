import CreatorGeometry
import Foundation
import Testing
@testable import CreatorImplicit

struct STLWriterTests {
    /// A binary STL read back: its triangles' normals and corners.
    struct File {
        var header: Data
        var triangles: [(normal: SIMD3<Float>, corners: [SIMD3<Float>])]

        init?(_ data: Data) {
            guard data.count >= 84 else { return nil }
            header = data.prefix(80)
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
    }

    @Test func aCubeIsTwelveTrianglesOfFiftyBytes() throws {
        var writer = STLWriter()
        writer.add(MeshFixtures.cube)
        let data = writer.data()
        #expect(writer.triangleCount == 12 && data.count == 84 + 50 * 12)
        let file = try #require(File(data))
        #expect(file.triangles.count == 12)
    }

    @Test func theHeaderIsNotMistakenForAsciiAndTheCountIsLittleEndian() throws {
        var writer = STLWriter()
        writer.add(MeshFixtures.tetrahedron)
        let data = writer.data()
        #expect(data.count >= 84 && !(String(bytes: data.prefix(5), encoding: .ascii) ?? "").lowercased().hasPrefix("solid"))
        #expect(Array(data[80..<84]) == [4, 0, 0, 0])
        #expect(Array(data[(84 + 48)..<(84 + 50)]) == [0, 0], "the attribute bytes")
    }

    @Test func normalsPointOutwardAndCornersKeepTheirOrder() throws {
        var writer = STLWriter()
        writer.add(MeshFixtures.cube)
        let file = try #require(File(writer.data()))
        let centre = SIMD3<Float>(0.5, 0.5, 0.5)
        for triangle in file.triangles {
            let middle = (triangle.corners[0] + triangle.corners[1] + triangle.corners[2]) / 3
            #expect(((middle - centre) * triangle.normal).sum() > 0, "normal \(triangle.normal)")
            #expect(abs((triangle.normal * triangle.normal).sum() - 1) < 1e-6)
        }
        // The first triangle of the fixture is (0, 2, 1) of the cube's vertices.
        #expect(file.triangles[0].corners == [SIMD3(0, 0, 0), SIMD3(1, 1, 0), SIMD3(1, 0, 0)])
    }

    @Test func solidsAndMeshesShareOneFile() throws {
        var writer = STLWriter()
        writer.add(positions: [Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(0, 2, 0)], indices: [0, 1, 2])
        writer.add(MeshFixtures.tetrahedron)
        let file = try #require(File(writer.data()))
        #expect(file.triangles.count == 5)
        #expect(file.triangles[0].normal == SIMD3(0, 0, 1) && file.triangles[0].corners[1] == SIMD3(2, 0, 0))
    }

    @Test func aTriangleWithNoAreaGetsAZeroNormal() throws {
        var writer = STLWriter()
        writer.add(positions: [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 0, 0)], indices: [0, 1, 2])
        let file = try #require(File(writer.data()))
        #expect(file.triangles[0].normal == .zero)
    }

    @Test func anEmptyWriterIsAValidEmptyFile() throws {
        let data = STLWriter().data()
        #expect(data.count == 84 && File(data)?.triangles.isEmpty == true)
    }
}
