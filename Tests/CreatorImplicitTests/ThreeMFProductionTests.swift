@testable import CreatorGraph
import Foundation
import Testing
@testable import CreatorImplicit

/// The Production extension's parts in other files of the package (mesh import spec, Errata (3MF parts), Task 11b): a `path` on a root
/// `component` or `item` names a part, which is read once, with one budget across the file.
@Suite("ThreeMFProduction")
struct ThreeMFProductionTests {
    typealias Package = ThreeMFPackage

    static let cube = MeshFixtures.cube
    static let triangle = TriangleMesh(positions: [SIMD3(1, 0, 0), SIMD3(0, 2, 0), SIMD3(0, 0, 3)], triangles: [0, 1, 2])
    static let rootName = "3D/3dmodel.model"
    static let producing = "xmlns=\"\(Package.core)\" xmlns:p=\"\(Package.production)\" requiredextensions=\"p\""

    static func part(_ resources: String, unit: String? = "millimeter", namespaces: String = "xmlns=\"\(Package.core)\"") -> String {
        Package.model(resources: resources, build: "", unit: unit, namespaces: namespaces)
    }

    static func root(_ resources: String, _ build: String, unit: String? = "millimeter", prefix: String = "p",
                     requires: Bool = true) -> String {
        let namespaces = "xmlns=\"\(Package.core)\" xmlns:\(prefix)=\"\(Package.production)\""
            + (requires ? " requiredextensions=\"\(prefix)\"" : "")
        return Package.model(resources: resources, build: build, unit: unit, namespaces: namespaces)
    }

    static func component(_ id: Int, path: String, prefix: String = "p", transform: String? = nil) -> String {
        "<component \(prefix):path=\"\(path)\" objectid=\"\(id)\"" + (transform.map { " transform=\"\($0)\"" } ?? "") + "/>"
    }

    static func wrapper(_ id: Int, _ components: String) -> String {
        "<object id=\"\(id)\"><components>\(components)</components></object>"
    }

    /// A package with the root model and `parts`, by entry name.
    static func package(root: String, parts: [(String, String)]) -> Data {
        var items: [ZipReaderForeignTests.Item] = [
            .init(name: "_rels/.rels", body: Data(Package.relationships().utf8)),
            .init(name: rootName, body: Data(root.utf8)),
        ]
        for (name, text) in parts { items.append(.init(name: name, body: Data(text.utf8))) }
        return ZipReaderForeignTests.build(items, zip64: false)
    }

    func read(_ data: Data, triangleLimit: Int = MeshImportLimits.maxTriangles, recordLimit: Int = ThreeMFLimits().records,
              partLimit: Int = ThreeMFLimits().parts, byteLimit: Int = ThreeMFLimits().modelBytes,
              isCancelled: @escaping () -> Bool = { false }) throws -> [ImportedMesh] {
        try ThreeMFReader.read(data, triangleLimit: triangleLimit, recordLimit: recordLimit, partLimit: partLimit, byteLimit: byteLimit,
                               isCancelled: isCancelled)
    }

    func problem(_ data: Data, triangleLimit: Int = MeshImportLimits.maxTriangles, recordLimit: Int = ThreeMFLimits().records,
                 partLimit: Int = ThreeMFLimits().parts, byteLimit: Int = ThreeMFLimits().modelBytes) -> MeshImportProblem? {
        do {
            _ = try read(data, triangleLimit: triangleLimit, recordLimit: recordLimit, partLimit: partLimit, byteLimit: byteLimit)
            return nil
        } catch let problem as MeshImportProblem {
            return problem
        } catch {
            return nil
        }
    }

    func positions(of mesh: ImportedMesh) -> Set<[Float]> {
        Set(mesh.mesh.positions.map { [$0.x, $0.y, $0.z] })
    }

    /// One part holding a cube as object 1, named from a root through a wrapper object 2.
    static func simple(path: String = "/3D/Objects/a.model", entry: String = "3D/Objects/a.model", prefix: String = "p") -> Data {
        package(root: root(wrapper(2, component(1, path: path, prefix: prefix)), Package.item(2), prefix: prefix),
                parts: [(entry, part(Package.object(id: 1, mesh: cube)))])
    }

    // MARK: Reading

    @Test func aBambuShapedFileReads() throws {
        // The shape of a Bambu Studio project: the root's wrappers name the meshes in 3D/Objects, build items place the wrappers, and
        // there are plate, paint and UUID attributes and config parts the reader never opens.
        let bambu = "xmlns:BambuStudio=\"http://schemas.bambulab.com/package/2021\""
        let resources = "<object id=\"3\" p:UUID=\"00000001\" type=\"model\"><components>"
            + Self.component(1, path: "/3D/Objects/object_1.model", transform: "1 0 0 0 1 0 0 0 1 0 0 0")
            + "</components></object><object id=\"4\" type=\"model\"><components>"
            + Self.component(1, path: "/3D/Objects/object_2.model") + "</components></object>"
        let build = "<item objectid=\"3\" p:UUID=\"x\" transform=\"1 0 0 0 1 0 0 0 1 128 128 10\" printable=\"1\"/>"
            + "<item objectid=\"4\" printable=\"1\"/>"
        let namespaces = "xmlns=\"\(Package.core)\" xmlns:p=\"\(Package.production)\" \(bambu) requiredextensions=\"p\""
        let root = Package.model(resources: resources, build: build, namespaces: namespaces)
        // Triangles carry `paint_color`; an object carries `name`; a vertex has a stray attribute.
        let painted = Package.object(id: 1, mesh: Self.cube)
            .replacingOccurrences(of: "<triangle ", with: "<triangle paint_color=\"4\" ")
            .replacingOccurrences(of: "<object id=\"1\" ", with: "<object id=\"1\" name=\"cube\" ")
        let data = Self.package(root: root, parts: [
            ("3D/Objects/object_1.model", Self.part(painted)),
            ("3D/Objects/object_2.model", Self.part(Package.object(id: 1, mesh: Self.triangle))),
            ("Metadata/model_settings.config", "<config><plate/></config>"),
            ("Metadata/project_settings.config", "{\"x\": 1}"),
        ])
        let meshes = try read(data)
        #expect(meshes.count == 2)
        #expect(meshes[0].mesh.triangleCount == 12 && meshes[0].mesh.positions.count == 8)
        #expect(positions(of: meshes[1]) == [[1, 0, 0], [0, 2, 0], [0, 0, 3]])
        // Painting is dropped like a colour, and says so (the flag is the file's, so it is on every mesh).
        #expect(meshes.allSatisfy(\.ignoredExtras) && meshes[0].unit == 1)
        let digests = meshes.map { ThreeMFProductionTests.digest($0.mesh) }
        #expect(digests == [
            "fe90e8c4ddc81c48a22c079e27f56af065126762cfbd4ebba05447a342448f35",
            "aa13012e88483bc471a1fc78c3b4a63e4bf733e3c330c4d86d04a17591bf0332",
        ])
    }

    @Test func aPartNamedTwiceIsReadOnce() throws {
        let part = Self.part(Package.object(id: 1, mesh: Self.cube))
        let wrappers = Self.wrapper(2, Self.component(1, path: "/3D/Objects/a.model") + Self.component(1, path: "/3D/Objects/a.model"))
            + Self.wrapper(3, Self.component(1, path: "/3D/Objects/A.model"))
        let root = Self.root(wrappers, Package.item(2) + Package.item(3))
        let data = Self.package(root: root, parts: [("3D/Objects/a.model", part)])
        // The budget holds the root and one copy of the part: a second reading would pass it.
        let allowed = root.utf8.count + part.utf8.count + 8
        let meshes = try read(data, byteLimit: allowed)
        #expect(meshes.count == 2 && meshes[0].mesh.triangleCount == 24 && meshes[1].mesh.triangleCount == 12)
        // Stored once: a triangle limit of one cube's worth stores it, though 36 are instanced.
        #expect(problem(data, triangleLimit: 12) == .tooManyTriangles(36))
    }

    @Test func anUnnamedPartIsNotRead() throws {
        let root = Self.root(Self.wrapper(2, Self.component(1, path: "/3D/Objects/a.model")), Package.item(2))
        let data = Self.package(root: root, parts: [
            ("3D/Objects/a.model", Self.part(Package.object(id: 1, mesh: Self.cube))),
            ("3D/Objects/damaged.model", "<model this is not xml"),
            ("3D/Objects/big.model", String(repeating: "x", count: 5_000)),
        ])
        #expect(try read(data).count == 1)
        // Not even its size counts against the budget.
        #expect(try read(data, byteLimit: root.utf8.count + Self.part(Package.object(id: 1, mesh: Self.cube)).utf8.count + 8).count == 1)
    }

    @Test func sameIdInTwoPartsIsTwoObjects() throws {
        let wrappers = Self.wrapper(10, Self.component(1, path: "/3D/Objects/a.model"))
            + Self.wrapper(11, Self.component(1, path: "/3D/Objects/b.model"))
        let data = Self.package(root: Self.root(wrappers, Package.item(10) + Package.item(11)), parts: [
            ("3D/Objects/a.model", Self.part(Package.object(id: 1, mesh: Self.cube))),
            ("3D/Objects/b.model", Self.part(Package.object(id: 1, mesh: Self.triangle))),
        ])
        let meshes = try read(data)
        #expect(meshes.map(\.mesh.triangleCount) == [12, 1])
    }

    @Test func aPathOnAnItemReads() throws {
        let build = "<item p:path=\"/3D/Objects/a.model\" objectid=\"1\" transform=\"\(ThreeMFReaderTests.translateX100)\"/>"
        let part = Self.part(Package.object(id: 1, mesh: Self.triangle))
        let data = Self.package(root: Self.root("", build), parts: [("3D/Objects/a.model", part)])
        let meshes = try read(data)
        #expect(positions(of: meshes[0]) == [[101, 0, 0], [100, 2, 0], [100, 0, 3]])
    }

    @Test func aPathToTheRootIsTheRoot() throws {
        let resources = Package.object(id: 1, mesh: Self.cube) + Self.wrapper(2, Self.component(1, path: "/3D/3dmodel.model"))
        let data = Self.package(root: Self.root(resources, Package.item(2)), parts: [])
        #expect(try read(data)[0].mesh.triangleCount == 12)
        // Spelled differently, it is still the root.
        let spelled = Self.wrapper(2, Self.component(1, path: "/3d/3DMODEL.model"))
        #expect(try read(Self.package(root: Self.root(Package.object(id: 1, mesh: Self.cube) + spelled, Package.item(2)), parts: []))
            .count == 1)
    }

    @Test func aPrefixOtherThanPReads() throws {
        for prefix in ["q", "prod", "p2"] {
            let meshes = try read(Self.simple(prefix: prefix))
            #expect(meshes.count == 1 && meshes[0].mesh.triangleCount == 12, "\(prefix)")
        }
        // A `p:path` whose `p` is another namespace names nothing.
        let decoy = Self.wrapper(2, "<component objectid=\"1\" p:path=\"/x\"/>")
        let root = Package.model(resources: Package.object(id: 1, mesh: Self.cube) + decoy, build: Package.item(2),
                                 namespaces: "xmlns=\"\(Package.core)\" xmlns:p=\"urn:other\"")
        #expect(try read(Self.package(root: root, parts: [])).count == 1)
    }

    @Test func aPercentEncodedPathReads() throws {
        let data = Self.simple(path: "/3D/Objects/my%20part.model", entry: "3D/Objects/my part.model")
        #expect(try read(data).count == 1)
        #expect(try read(Self.simple(path: "/3D/OBJECTS/A.MODEL")).count == 1)
    }

    @Test func partTransformsCompose() throws {
        // The part's wrapper is moved by its own component, the root's component by its, the build item by its.
        let inner = Package.object(id: 1, mesh: Self.triangle)
            + Package.assembly(id: 2, [(1, "1 0 0 0 1 0 0 0 1 0 10 0")])
        let wrapper = Self.wrapper(5, Self.component(2, path: "/3D/Objects/a.model", transform: "1 0 0 0 1 0 0 0 1 0 0 1000"))
        let data = Self.package(root: Self.root(wrapper, Package.item(5, ThreeMFReaderTests.translateX100)),
                                parts: [("3D/Objects/a.model", Self.part(inner))])
        #expect(positions(of: try read(data)[0]) == [[101, 10, 1000], [100, 12, 1000], [100, 10, 1003]])
    }

    @Test func aMirrorThroughAPartStaysRightSideOut() throws {
        let mirror = "-1 0 0 0 1 0 0 0 1 0 0 0"
        let wrapper = Self.wrapper(5, Self.component(1, path: "/3D/Objects/a.model", transform: mirror))
        let data = Self.package(root: Self.root(wrapper, Package.item(5)),
                                parts: [("3D/Objects/a.model", Self.part(Package.object(id: 1, mesh: Self.cube)))])
        let mirrored = try read(data)[0].mesh
        let plain = try read(Self.simple())[0].mesh
        func volume(_ mesh: TriangleMesh) -> Float {
            var sum: Float = 0
            for base in stride(from: 0, to: mesh.triangles.count, by: 3) {
                let (a, b, c) = (mesh.positions[Int(mesh.triangles[base])], mesh.positions[Int(mesh.triangles[base + 1])],
                                 mesh.positions[Int(mesh.triangles[base + 2])])
                sum += (a.x * (b.y * c.z - b.z * c.y) - a.y * (b.x * c.z - b.z * c.x) + a.z * (b.x * c.y - b.y * c.x)) / 6
            }
            return sum
        }
        #expect(volume(plain) > 0 && volume(mirrored) > 0)
    }

    @Test func supportsInAPartAreLeftOut() throws {
        let part = Package.object(id: 1, mesh: Self.cube) + Package.object(id: 2, mesh: Self.triangle, attributes: "type=\"support\"")
        let wrappers = Self.wrapper(5, Self.component(1, path: "/3D/Objects/a.model") + Self.component(2, path: "/3D/Objects/a.model"))
        let data = Self.package(root: Self.root(wrappers, Package.item(5)), parts: [("3D/Objects/a.model", Self.part(part))])
        let meshes = try read(data)
        #expect(meshes[0].mesh.triangleCount == 12 && meshes[0].partsLeftOut)
    }

    static func digest(_ mesh: TriangleMesh) -> String {
        var bytes = Data()
        for p in mesh.positions {
            for value in [p.x, p.y, p.z] { withUnsafeBytes(of: value.bitPattern.littleEndian) { bytes.append(contentsOf: $0) } }
        }
        for index in mesh.triangles { withUnsafeBytes(of: UInt32(index).littleEndian) { bytes.append(contentsOf: $0) } }
        return SHA256.hex(of: bytes)
    }
}
