import CreatorGraph
import Foundation
import Testing
@testable import CreatorImplicit

/// The 3MF reader (mesh import spec, Reading, Limits, Construction): packages found through their relationships, the core
/// specification's units, transforms, components and build items, and a file that tries to hurt.
@Suite("ThreeMFReader")
struct ThreeMFReaderTests {
    typealias Package = ThreeMFPackage

    static let cube = MeshFixtures.cube
    /// One triangle with distinct coordinates, so a wrong transform order shows.
    static let triangle = TriangleMesh(positions: [SIMD3(1, 0, 0), SIMD3(0, 2, 0), SIMD3(0, 0, 3)], triangles: [0, 1, 2])
    static let translateX100 = "1 0 0 0 1 0 0 0 1 100 0 0"

    func read(_ data: Data, limit: Int = MeshImportLimits.maxTriangles) throws -> [ImportedMesh] {
        try ThreeMFReader.read(data, triangleLimit: limit, isCancelled: { false })
    }

    func read(resources: String, build: String, unit: String? = "millimeter", attributes: String = "",
              namespaces: String = "xmlns=\"\(Package.core)\"") throws -> [ImportedMesh] {
        try read(Package.package(resources: resources, build: build, unit: unit, attributes: attributes, namespaces: namespaces))
    }

    func positions(of mesh: ImportedMesh) -> Set<[Float]> {
        Set(mesh.mesh.positions.map { [$0.x, $0.y, $0.z] })
    }

    func problem(_ data: Data, limit: Int = MeshImportLimits.maxTriangles) -> MeshImportProblem? {
        do {
            _ = try read(data, limit: limit)
            return nil
        } catch let problem as MeshImportProblem {
            return problem
        } catch {
            return nil
        }
    }

    func problem(resources: String, build: String, attributes: String = "") -> MeshImportProblem? {
        problem(Package.package(resources: resources, build: build, attributes: attributes))
    }

    // MARK: Round trip and agreement

    @Test func aFileOurWriterMadeReadsBackWithItsTriangles() throws {
        let url = URL.temporaryDirectory.appending(path: "reader-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        var writer = ThreeMFWriter(destination: url)
        let sphere = MeshFixtures.sphereMesh(radius: 5, subdivisions: 1)
        for (name, mesh) in [("Cube", Self.cube), ("Ball", sphere)] {
            try writer.beginObject(name: name)
            try writer.add(MeshWindow(positions: mesh.positions, triangles: mesh.triangles, startingAt: 0))
            try writer.endObject()
        }
        try writer.finish()
        let meshes = try read(try Data(contentsOf: url))
        #expect(meshes.count == 2)
        for (read, original) in zip(meshes, [Self.cube, sphere]) {
            #expect(read.unit == 1 && !read.ignoredExtras && read.droppedTriangles == 0)
            #expect(read.mesh.triangleCount == original.triangleCount && read.mesh.positions.count == original.positions.count)
            // The writer keeps six significant digits, so positions agree to that and the triangles by the vertex they meet.
            func match(_ p: SIMD3<Float>) -> Int? {
                read.mesh.positions.indices.first { index in
                    let q = read.mesh.positions[index]
                    return abs(q.x - p.x) <= 1e-4 && abs(q.y - p.y) <= 1e-4 && abs(q.z - p.z) <= 1e-4
                }
            }
            let mapped = original.positions.map(match)
            #expect(!mapped.contains(nil) && Set(mapped.compactMap { $0 }).count == original.positions.count)
            func triples(_ triangles: [UInt32], _ map: (Int) -> Int) -> Set<[Int]> {
                Set(stride(from: 0, to: triangles.count, by: 3).map { base in
                    let corners = (0..<3).map { map(Int(triangles[base + $0])) }
                    let lowest = corners.indices.min { corners[$0] < corners[$1] } ?? 0
                    return (0..<3).map { corners[(lowest + $0) % 3] }
                })
            }
            #expect(triples(original.triangles, { mapped[$0] ?? -1 }) == triples(read.mesh.triangles, { $0 }))
        }
    }

    @Test func theWritersModelReadsTheSameAsTheXMLParserOracle() throws {
        let url = URL.temporaryDirectory.appending(path: "oracle-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        var writer = ThreeMFWriter(destination: url)
        let ball = MeshFixtures.sphereMesh(radius: 2, subdivisions: 2)
        try writer.beginObject(name: "Ball")
        try writer.add(MeshWindow(positions: ball.positions, triangles: ball.triangles, startingAt: 0))
        try writer.endObject()
        try writer.finish()
        let bytes = try Data(contentsOf: url)
        let oracle = try #require(ThreeMFReading.read(try ZipReader(data: bytes).contents(of: "3D/3dmodel.model")))
        let meshes = try read(bytes)
        let object = try #require(oracle.objects.first)
        #expect(meshes.count == oracle.buildItems.count)
        #expect(meshes[0].mesh.positions.count == object.vertices.count && meshes[0].mesh.triangleCount == object.triangles.count)
        let ours = Set(meshes[0].mesh.positions.map { [Double($0.x), Double($0.y), Double($0.z)] })
        let theirs = Set(object.vertices.map { [Double(Float($0.x)), Double(Float($0.y)), Double(Float($0.z))] })
        #expect(ours == theirs)
    }

    @Test func aFileFromAnotherToolReads() throws {
        let meshes = try read(Data(ThreeMFFixtures.foreignTetrahedra))
        let mesh = try #require(meshes.first)
        #expect(meshes.count == 1 && mesh.unit == 25.4 && !mesh.ignoredExtras)
        #expect(mesh.mesh.triangleCount == 8 && mesh.mesh.positions.count == 8)
        // Two tetrahedra of volume 8/3, one of them mirrored: both come out right side out.
        #expect(abs(mesh.mesh.signedVolume - 16.0 / 3) < 1e-5)
        #expect(EdgeCounts(mesh.mesh).isClosed)
        #expect(positions(of: mesh).contains([9, 1, 1]) && positions(of: mesh).contains([1, 1, 1]))
    }

    // MARK: Finding the model

    @Test func theModelIsFoundThroughRels() throws {
        let model = Package.model(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1))
        for target in ["/Models/part.model", "Models/part.model", "/3D/deep/er/x.model"] {
            let entry = target.hasPrefix("/") ? String(target.dropFirst()) : target
            let data = Package.zip(model: model, entry: entry, relationships: Package.relationships(target: target))
            #expect(try read(data).first?.mesh.triangleCount == 12, "\(target)")
        }
    }

    @Test func aMissingModelPartIsNamed() {
        let model = Package.model(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1))
        // Not at the path the relationship names, differing only in case, no relationship at all, or one of another type.
        let cases: [Data] = [
            Package.zip(model: model, entry: "3D/other.model"),
            Package.zip(model: model, entry: "3d/3dmodel.model"),
            Package.zip(model: model, relationships: nil),
            Package.zip(model: model, relationships: Package.relationships(type: "http://example.com/thumbnail")),
            Package.zip(model: model, relationships: "<Relationships/>"),
        ]
        for data in cases { #expect(problem(data) == .noModelPart) }
        #expect(MeshImportProblem.noModelPart.message == "This 3MF has no 3D model part.")
    }

    @Test func aZipThatIsNotA3MFOrNotAZipIsNotAMeshFile() {
        #expect(problem(Data("solid x\nendsolid x\n".utf8)) == .notAMeshFile)
        #expect(problem(Data()) == .notAMeshFile)
    }

    // MARK: Units, transforms, components, build items

    @Test func eachUnitConverts() throws {
        let table: [(String, Double)] = [
            ("micron", 0.001), ("millimeter", 1), ("centimeter", 10), ("inch", 25.4), ("foot", 304.8), ("meter", 1000),
        ]
        let asWritten = positions(of: ImportedMesh(mesh: Self.cube, droppedTriangles: 0, unit: nil, ignoredExtras: false))
        for (name, factor) in table {
            let meshes = try read(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1), unit: name)
            #expect(meshes.first?.unit == factor, "\(name)")
            // The reader leaves the coordinates as the file has them; the node scales afterwards.
            #expect(meshes.first.map(positions) == asWritten)
        }
        let none = try read(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1), unit: nil)
        #expect(none.first?.unit == 1)
        #expect(problem(Package.package(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1), unit: "furlong"))
            != nil)
    }

    @Test func buildTransformsApply() throws {
        // 3MF's twelve numbers are the rows m00 m01 m02, m10 m11 m12, m20 m21 m22 and the offset m30 m31 m32, applied to a point as a row:
        // x' = m00 x + m10 y + m20 z + m30, and so on. A point (1, 0, 0) lands on the first row plus the offset.
        let transform = "1 2 0 0 1 3 4 0 1 5 6 7"
        let meshes = try read(resources: Package.object(id: 1, mesh: Self.triangle), build: Package.item(1, transform))
        #expect(positions(of: try #require(meshes.first)) == [[6, 8, 7], [5, 8, 13], [17, 6, 10]])
        // A quarter turn about z moves +x to +y: the first row is (0, 1, 0), the second (-1, 0, 0).
        let turned = try read(resources: Package.object(id: 1, mesh: Self.triangle), build: Package.item(1, "0 1 0 -1 0 0 0 0 1 0 0 0"))
        #expect(positions(of: try #require(turned.first)) == [[0, 1, 0], [-2, 0, 0], [0, 0, 3]])
        // White space of every kind separates the numbers.
        let spaced = try read(resources: Package.object(id: 1, mesh: Self.triangle),
                              build: Package.item(1, " 1\t0 0\n0  1 0\r\n0 0 1 \t5 0 0 "))
        #expect(positions(of: try #require(spaced.first)) == [[6, 0, 0], [5, 2, 0], [5, 0, 3]])
    }

    @Test func componentTransformsCompose() throws {
        // Triangle -> object 2 (scale 2, then move 1) -> object 3 (move 10) -> the build item (move 100).
        let resources = Package.object(id: 1, mesh: Self.triangle)
            + Package.assembly(id: 2, [(1, "2 0 0 0 2 0 0 0 2 1 0 0")])
            + Package.assembly(id: 3, [(2, "1 0 0 0 1 0 0 0 1 10 0 0")])
        let meshes = try read(resources: resources, build: Package.item(3, Self.translateX100))
        #expect(positions(of: try #require(meshes.first)) == [[113, 0, 0], [111, 4, 0], [111, 0, 6]])
    }

    @Test func componentsOfOneObjectJoinIntoOneWeldedMesh() throws {
        let apart = Package.assembly(id: 2, [(1, nil), (1, "1 0 0 0 1 0 0 0 1 10 0 0")])
        let meshes = try read(resources: Package.object(id: 1, mesh: Self.cube) + apart, build: Package.item(2))
        #expect(meshes.count == 1 && meshes[0].mesh.triangleCount == 24 && meshes[0].mesh.positions.count == 16)
        // Two cubes that touch along a face share its four corners.
        let touching = Package.assembly(id: 2, [(1, nil), (1, "1 0 0 0 1 0 0 0 1 1 0 0")])
        let joined = try read(resources: Package.object(id: 1, mesh: Self.cube) + touching, build: Package.item(2))
        #expect(joined[0].mesh.positions.count == 12)
    }

    @Test func aMirrorKeepsItRightSideOut() throws {
        let mirror = "-1 0 0 0 1 0 0 0 1 0 0 0"
        let cube = Package.object(id: 1, mesh: Self.cube)
        let item = try #require(try read(resources: cube, build: Package.item(1, mirror)).first)
        #expect(EdgeCounts(item.mesh).isClosed && abs(item.mesh.signedVolume - 1) < 1e-6)
        #expect(positions(of: item).contains([-1, 1, 1]) && !positions(of: item).contains([1, 1, 1]))
        // A mirrored component, and two mirrors that cancel.
        let part = try #require(try read(resources: cube + Package.assembly(id: 2, [(1, mirror)]), build: Package.item(2)).first)
        #expect(EdgeCounts(part.mesh).isClosed && abs(part.mesh.signedVolume - 1) < 1e-6)
        let twice = try #require(try read(resources: cube + Package.assembly(id: 2, [(1, mirror)]), build: Package.item(2, mirror)).first)
        #expect(EdgeCounts(twice.mesh).isClosed && abs(twice.mesh.signedVolume - 1) < 1e-6)
        #expect(positions(of: twice).contains([1, 1, 1]))
    }

    @Test func eachBuildItemIsItsOwnMesh() throws {
        let resources = Package.object(id: 1, mesh: Self.cube) + Package.assembly(id: 2, [(1, nil), (1, "1 0 0 0 1 0 0 0 1 5 0 0")])
        let meshes = try read(resources: resources, build: Package.item(1) + Package.item(1, Self.translateX100) + Package.item(2))
        #expect(meshes.map(\.mesh.triangleCount) == [12, 12, 24])
        #expect(positions(of: meshes[1]).contains([100, 0, 0]))
    }

    @Test func anEmptyBuildHoldsNoTriangles() {
        #expect(problem(resources: Package.object(id: 1, mesh: Self.cube), build: "") == .noTriangles)
        #expect(problem(resources: "", build: "") == .noTriangles)
        // An item that is nothing but degenerate triangles is dropped, and with nothing else, nothing is left.
        let flat = TriangleMesh(positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0)], triangles: [0, 1, 1])
        #expect(problem(resources: Package.object(id: 1, mesh: flat), build: Package.item(1)) == .noTriangles)
    }

    @Test func aDegenerateTriangleIsDroppedAndCounted() throws {
        let mesh = TriangleMesh(positions: Self.cube.positions, triangles: Self.cube.triangles + [0, 0, 1])
        let read = try #require(try read(resources: Package.object(id: 1, mesh: mesh), build: Package.item(1)).first)
        #expect(read.droppedTriangles == 1 && read.mesh.triangleCount == 12)
    }

    @Test func anItemWithNoTrianglesAmongOthersIsLeftOut() throws {
        let resources = Package.object(id: 1, mesh: Self.cube) + "<object id=\"2\"><components/></object>"
        let meshes = try read(resources: resources, build: Package.item(2) + Package.item(1))
        #expect(meshes.count == 1 && meshes[0].mesh.triangleCount == 12)
    }
}
