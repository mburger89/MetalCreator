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
        // A count above the limit that the size does not hold is not an STL at all (a 3MF or other binary renamed .stl).
        #expect(Self.problem(Self.binary([], header: "solid x", declaredCount: 10_000_001)) == .notAMeshFile)
    }

    @Test func aTruncatedBinaryEndsEarly() {
        var data = Self.binary([Self.one, Self.one], header: "")
        data.removeLast(10)
        #expect(Self.problem(data) == .endsEarly)
        #expect(Self.problem(Self.binary([Self.one], declaredCount: 5_000_000)) == .endsEarly)
    }

    @Test func aCountAboveTheLimitRefusesOnlyWhenTheSizeHoldsIt() throws {
        let over = MeshImportLimits.maxTriangles + 1
        // The exact size of a file that really holds `over` triangles (500 MB, so only the arithmetic is tested).
        #expect(throws: MeshImportProblem.tooManyTriangles(over)) {
            _ = try STLReader.binaryFit(count: over, size: 84 + 50 * over, triangleLimit: MeshImportLimits.maxTriangles)
        }
        #expect(try STLReader.binaryFit(count: over, size: 84, triangleLimit: MeshImportLimits.maxTriangles) == .doesNotFit)
        #expect(try STLReader.binaryFit(count: over, size: 84 + 50 * over + 7, triangleLimit: MeshImportLimits.maxTriangles) == .doesNotFit)
        #expect(try STLReader.binaryFit(count: 10, size: 84, triangleLimit: MeshImportLimits.maxTriangles) == .endsEarly)
        #expect(try STLReader.binaryFit(count: 10, size: 84 + 500, triangleLimit: MeshImportLimits.maxTriangles) == .exact)
        // An exact fit over a smaller limit through the whole reader.
        #expect(throws: MeshImportProblem.tooManyTriangles(2)) {
            _ = try STLReader.read(Self.binary([Self.one, Self.one]), triangleLimit: 1, isCancelled: { false })
        }
        let data = Self.binary([], declaredCount: UInt32(over))
        #expect(data.count == 84)
        #expect(Self.problem(data) == .notAMeshFile)
    }

    @Test func aZipRenamedStlIsNotAMeshFile() {
        var zip = Data([0x50, 0x4B, 0x03, 0x04])
        zip.append(Data(repeating: 0x61, count: 200))
        #expect(Self.problem(zip) == .notAMeshFile)
        var random = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        random.append(Data(repeating: 0x00, count: 40))
        random.append(contentsOf: [0xD4, 0x35, 0x6B, 0x6C])
        random.append(Data(repeating: 0x01, count: 100))
        #expect(Self.problem(random) == .notAMeshFile)
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

    // MARK: ASCII is read by token

    private static func vertices(_ data: String) throws -> [SIMD3<Float>] {
        try STLReader.read(Data(data.utf8), isCancelled: { false }).mesh.positions
    }

    @Test func severalVerticesOnALineRead() throws {
        let text = "solid x\nvertex 0 0 0 vertex 1 0 0 vertex 0 1 0\nvertex 0 0 0 vertex 1 0 0 vertex 0 0 1\nendsolid\n"
        let mesh = try STLReader.read(Data(text.utf8), isCancelled: { false }).mesh
        #expect(mesh.triangleCount == 2)
        #expect(Set(mesh.positions) == [[0, 0, 0], [1, 0, 0], [0, 1, 0], [0, 0, 1]])
    }

    @Test func aFacetOnOneLineReads() throws {
        let text = "solid x\nfacet normal 0 0 1 outer loop vertex 0 0 0 vertex 1 0 0 vertex 0 1 0 endloop endfacet\nendsolid x\n"
        #expect(try Self.vertices(text).count == 3)
    }

    @Test func aWholeFileOnOneLineReads() throws {
        let text = "solid x facet normal 0 0 1 outer loop vertex 0 0 0 vertex 1 0 0 vertex 0 1 0 endloop endfacet endsolid x"
        #expect(try Self.vertices(text).count == 3)
    }

    @Test func aNumberMayBeOnTheNextLine() throws {
        #expect(try Self.vertices("solid x\nvertex 0 0\n0\nvertex 1 0 0\nvertex\n0 1 0\n").count == 3)
    }

    @Test func crOnlyLineEndsRead() throws {
        let text = "solid x\rfacet normal 0 0 1\router loop\rvertex 0 0 0\rvertex 1 0 0\rvertex 0 1 0\rendloop\rendfacet\rendsolid\r"
        #expect(try Self.vertices(text).count == 3)
        let bad = "solid x\rfacet normal 0 0 1\router loop\rvertex 0 0 0\rvertex 1 abc 0\rvertex 0 1 0\r"
        #expect(Self.problem(Data(bad.utf8)) == .badNumber(line: 5))
        // With LF present a lone CR is only a blank.
        let mixed = "solid x\nvertex 0 0 0\rvertex 1 0 0\nvertex 0 1 0\nvertex 1 2 abc\n"
        #expect(Self.problem(Data(mixed.utf8)) == .badNumber(line: 4))
    }

    @Test func uppercaseKeywordsRead() throws {
        let text = "SOLID X\nFACET NORMAL 0 0 1\nOUTER LOOP\nVERTEX 0 0 0\nVertex 1 0 0\nvErTeX 0 1 0\nENDLOOP\nENDFACET\nENDSOLID X\n"
        #expect(try Self.vertices(text).count == 3)
    }

    @Test func noSolidLineReads() throws {
        let text = "facet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\n"
        #expect(try Self.vertices(text).count == 3)
        #expect(try Self.vertices("vertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\n").count == 3)
    }

    @Test func plainTextIsNotAMeshFile() {
        #expect(Self.problem(Data("Dear reader, this is a letter about nothing in particular.\n".utf8)) == .notAMeshFile)
        #expect(Self.problem(Data(String(repeating: "lorem ipsum dolor sit amet ", count: 200).utf8)) == .notAMeshFile)
        // A token past the bounded look at the start does not make a letter an STL.
        #expect(Self.problem(Data((String(repeating: "word ", count: 600) + "vertex 0 0 0").utf8)) == .notAMeshFile)
    }

    @Test func asciiOverTheTriangleLimitRefusesAndStops() {
        var text = "solid x\n"
        for _ in 0..<50 { text += "vertex 0 0 0 vertex 1 0 0 vertex 0 1 0\n" }
        text += "vertex 0 0 abc\n"  // never reached: the limit is hit first
        #expect(throws: MeshImportProblem.tooManyTriangles(11)) {
            _ = try STLReader.read(Data(text.utf8), triangleLimit: 10, isCancelled: { false })
        }
    }

    @Test func aStrayVertexCountNotAMultipleOfThreeEndsEarly() {
        #expect(Self.problem(Data("solid x\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nvertex 2 2 2\n".utf8)) == .endsEarly)
    }

    @Test func asciiCancellationStopsWithNoVertices() {
        // 200 KB of text, so the byte-interval check runs, and no vertex ever completes a triangle.
        let text = "solid x\n" + String(repeating: "facet normal 0 0 1 outer loop endloop endfacet\n", count: 5_000)
        #expect(text.utf8.count > 200_000)
        #expect(throws: CancellationError.self) {
            _ = try STLReader.read(Data(text.utf8), isCancelled: { true })
        }
    }
}
