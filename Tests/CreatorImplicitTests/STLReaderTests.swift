import Foundation
import CreatorGraph
import Testing
@testable import CreatorImplicit

@Suite struct STLReaderTests {
    private static func binary(_ triangles: [[SIMD3<Float>]], header: String = "", declaredCount: UInt32? = nil) -> Data {
        var data = Data(Array(header.utf8))
        data.append(contentsOf: [UInt8](repeating: 0, count: 80 - data.count))
        data.append(contentsOf: littleEndian(declaredCount ?? UInt32(triangles.count)))
        for corners in triangles {
            for _ in 0..<3 { data.append(contentsOf: littleEndian(Float(0).bitPattern)) }
            for corner in corners {
                for value in [corner.x, corner.y, corner.z] { data.append(contentsOf: littleEndian(value.bitPattern)) }
            }
            data.append(contentsOf: [0, 0])
        }
        return data
    }

    private static func littleEndian(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian) { Array($0) }
    }

    private static let one: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0]]

    private static func read(_ data: Data) throws -> ImportedMesh {
        try STLReader.read(data, isCancelled: { false })
    }

    private static func problem(_ data: Data) -> MeshImportProblem? {
        do { _ = try read(data); return nil } catch { return error as? MeshImportProblem }
    }

    @Test func aBinaryStartingWithSolidIsBinary() throws {
        let mesh = try Self.read(Self.binary([Self.one], header: "solid looks like text"))
        #expect(mesh.mesh.triangleCount == 1)
        #expect(mesh.unit == nil)
    }

    @Test func anAsciiWhoseSizeFitsTheBinaryFormulaIsAscii() throws {
        let text = "solid t\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid t\n"
        var bytes = Array(text.utf8)
        var triangles = 1
        while 84 + 50 * triangles < bytes.count { triangles += 1 }
        bytes += [UInt8](repeating: 0x20, count: 84 + 50 * triangles - bytes.count)
        let mesh = try Self.read(Data(bytes))
        #expect(mesh.mesh.triangleCount == 1)
    }

    @Test func asciiToleratesCRLFOddSpacingAndExponents() throws {
        let text = "  solid   x \r\n facet normal 0 0 1 \r\n  outer loop\r\n\tvertex   0  0\t0\r\n vertex 1.5E+01 0 0\r\n"
            + "vertex 0 -2.5e-1 0\r\n endloop\r\n endfacet\r\nendsolid x\r\n"
        let mesh = try Self.read(Data(text.utf8)).mesh
        #expect(mesh.triangleCount == 1)
        #expect(Set(mesh.positions) == [[0, 0, 0], [15, 0, 0], [0, -0.25, 0]])
    }

    private static let asciiBody = "facet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid\n"

    @Test func anAsciiWithAUTF8NameReads() throws {
        let data = Data(("solid Bräcket – Ø\n" + Self.asciiBody).utf8)
        #expect(data.count < 84 || data.contains { $0 >= 0x80 })
        #expect(try Self.read(data).mesh.triangleCount == 1)
    }

    @Test func anAsciiWithABOMReads() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(("solid x\n" + Self.asciiBody).utf8))
        #expect(data.count >= 84)
        #expect(try Self.read(data).mesh.triangleCount == 1)
    }

    @Test func aTruncatedBinaryWithASolidHeaderEndsEarly() {
        var data = Self.binary([Self.one, Self.one], header: "solid exported by something")
        data.removeLast(10)
        #expect(Self.problem(data) == .endsEarly)
        #expect(Self.problem(Self.binary([], header: "solid x", declaredCount: 10_000_001)) == .tooManyTriangles(10_000_001))
    }

    @Test func aTruncatedBinaryEndsEarly() {
        var data = Self.binary([Self.one, Self.one], header: "")
        data.removeLast(10)
        #expect(Self.problem(data) == .endsEarly)
        #expect(Self.problem(Self.binary([Self.one], declaredCount: 5_000_000)) == .endsEarly)
    }

    @Test func aCountAboveTheLimitRefuses() {
        let data = Self.binary([], declaredCount: 10_000_001)
        #expect(data.count == 84)
        #expect(Self.problem(data) == .tooManyTriangles(10_000_001))
    }

    @Test func aBadNumberNamesItsLine() {
        let text = "solid x\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 abc 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid\n"
        #expect(Self.problem(Data(text.utf8)) == .badNumber(line: 5))
        let short = "solid x\nvertex 0 0\n"
        #expect(Self.problem(Data(short.utf8)) == .badNumber(line: 2))
        let nan = "solid x\nvertex nan 0 0\n"
        #expect(Self.problem(Data(nan.utf8)) == .badNumber(line: 2))
    }

    @Test func aNonFiniteBinaryCoordinateRefuses() {
        let data = Self.binary([[[0, 0, 0], [1, 0, 0], [.nan, 1, 0]]])
        #expect(Self.problem(data) == .notAMeshFile)
    }

    @Test func anEmptySolidHoldsNoTriangles() {
        #expect(Self.problem(Data("solid empty\nendsolid empty\n".utf8)) == .noTriangles)
        #expect(Self.problem(Self.binary([])) == .noTriangles)
    }

    @Test func somethingElseIsNotAMeshFile() {
        #expect(Self.problem(Data("hello".utf8)) == .notAMeshFile)
        #expect(Self.problem(Data()) == .notAMeshFile)
    }

    @Test func theFacetNormalIsIgnored() throws {
        let text = "solid x\nfacet normal 9 9 9\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid\n"
        var binary = Self.binary([Self.one])
        binary.replaceSubrange(84..<96, with: [UInt8](repeating: 0x7F, count: 12))
        let ascii = try Self.read(Data(text.utf8)).mesh
        let fromBinary = try Self.read(binary).mesh
        #expect(ascii.triangles == fromBinary.triangles)
        #expect(ascii.positions == fromBinary.positions)
    }

    @Test func aRoundTripThroughSTLWriterIsExact() throws {
        let box = unitBoxMesh()
        var writer = STLWriter()
        writer.add(box)
        let read = try Self.read(writer.data())
        #expect(Set(read.mesh.positions) == Set(box.positions))
        #expect(read.mesh.positions.count == 8)
        func triangleSet(_ mesh: TriangleMesh) -> Set<[SIMD3<Float>]> {
            Set((0..<mesh.triangleCount).map { index in
                let corners = (0..<3).map { mesh.positions[Int(mesh.triangles[3 * index + $0])] }
                let first = corners.indices.min { corners[$0].x != corners[$1].x ? corners[$0].x < corners[$1].x
                    : corners[$0].y != corners[$1].y ? corners[$0].y < corners[$1].y : corners[$0].z < corners[$1].z } ?? 0
                return (0..<3).map { corners[(first + $0) % 3] }
            })
        }
        #expect(triangleSet(read.mesh) == triangleSet(box))
        #expect(EdgeCounts(read.mesh).isClosed)
        #expect(read.droppedTriangles == 0)
    }

    @Test func cancellationStopsAParse() {
        let triangles = [[SIMD3<Float>]](repeating: Self.one, count: 70_000)
        #expect(throws: CancellationError.self) {
            _ = try STLReader.read(Self.binary(triangles), isCancelled: { true })
        }
    }
}
