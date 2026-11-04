import CreatorGraph
import Foundation
import Testing
@testable import CreatorImplicit

/// The 3MF reader on namespaces and extensions, and on files that try to hurt it.
extension ThreeMFReaderTests {
    // MARK: Namespaces, prefixes, extensions

    @Test func coloursAndMaterialsAreIgnoredWithAWarning() throws {
        let plain = try read(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1))
        #expect(plain[0].ignoredExtras == false)
        let cube = Package.object(id: 1, mesh: Self.cube)
        let coloured = Package.object(id: 1, mesh: Self.cube, attributes: "pid=\"5\" pindex=\"0\"")
        let materials = "xmlns:m=\"\(Package.materials)\""
        let cases: [(String, String, String)] = [
            ("<basematerials id=\"5\"><base name=\"x\" displaycolor=\"#FF0000\"/></basematerials>" + cube, "", ""),
            ("<m:colorgroup id=\"5\"><m:color color=\"#00FF00\"/></m:colorgroup>" + cube, "", materials),
            ("<m:texture2d id=\"5\" path=\"/3D/Texture/a.png\" contenttype=\"image/png\"/>" + cube, "", materials),
            (coloured, "", ""),
            (cube.replacingOccurrences(of: "v3=\"2\"", with: "v3=\"2\" p1=\"0\" pid=\"5\""), "", ""),
        ]
        for (resources, attributes, namespaces) in cases {
            let meshes = try read(resources: resources, build: Package.item(1), attributes: attributes,
                                  namespaces: "xmlns=\"\(Package.core)\" " + namespaces)
            #expect(meshes[0].ignoredExtras && meshes[0].mesh.triangleCount == 12, "\(resources.prefix(40))")
        }
        let lattice = cube.replacingOccurrences(of: "</mesh>", with: "<b:beamlattice minlength=\"1\"><b:beams/></b:beamlattice></mesh>")
        let beamNamespaces = "xmlns=\"\(Package.core)\" xmlns:b=\"\(Package.beamLattice)\""
        let beamed = try read(resources: lattice, build: Package.item(1), namespaces: beamNamespaces)
        #expect(beamed[0].ignoredExtras && beamed[0].mesh.triangleCount == 12)
        let sliced = cube.replacingOccurrences(of: "<object id=\"1\"", with: "<object s:slicestackid=\"3\" id=\"1\"")
        let sliceNamespaces = "xmlns=\"\(Package.core)\" xmlns:s=\"\(Package.slice)\""
        let slices = try read(resources: sliced, build: Package.item(1), namespaces: sliceNamespaces)
        #expect(slices[0].ignoredExtras)
        #expect(ThreeMFReader.ignoredExtrasWarning == "This mesh's color and material data was ignored.")
    }

    @Test func aRepeatedRequiredExtensionsIsRefused() {
        let cube = Package.object(id: 1, mesh: Self.cube)
        let data = Package.package(resources: cube, build: Package.item(1), attributes: "requiredextensions=\"\" requiredextensions=\"\"")
        guard case .malformedModel(let reason)? = problem(data) else { Issue.record("not refused"); return }
        #expect(reason.contains("required extensions twice"), "\(reason)")
    }

    @Test func aRepeatedUnitIsRefused() {
        let cube = Package.object(id: 1, mesh: Self.cube)
        let data = Package.package(resources: cube, build: Package.item(1), attributes: "unit=\"inch\"")
        guard case .malformedModel(let reason)? = problem(data) else { Issue.record("not refused"); return }
        #expect(reason.contains("two units"), "\(reason)")
    }

    @Test func aLongRunOfAttributesOnOneElementAsksAboutCancellation() throws {
        // 1.6 MB of attributes on one element passes the 1 MiB between asks: the element's bytes are counted once, as it starts.
        let attributes = String(repeating: " q0:a=\"\"", count: 200_000)
        let model = Package.model(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1), attributes: attributes)
        let calls = CallCounter()
        let bytes = Array(model.utf8)
        #expect(throws: CancellationError.self) {
            try bytes.withUnsafeBytes { raw in
                _ = try ThreeMFModelParser.parse(raw, limits: ThreeMFLimits(), isCancelled: { calls.next() >= 2 })
            }
        }
    }

    @Test func aProductionPathIsRefused() {
        let cube = Package.object(id: 1, mesh: Self.cube)
        // The prefix is whatever the file declared; it is the namespace that counts.
        for prefix in ["p", "q", "prod"] {
            let text = "<object id=\"2\"><components><component objectid=\"1\" \(prefix):path=\"/3D/other.model\"/></components></object>"
            let namespaces = "xmlns=\"\(Package.core)\" xmlns:\(prefix)=\"\(Package.production)\""
            let data = Package.package(resources: cube + text, build: Package.item(2), namespaces: namespaces)
            #expect(problem(data) == .otherFiles, "\(prefix)")
        }
        #expect(MeshImportProblem.otherFiles.message
            == "This 3MF keeps parts in other files, which isn't supported. Export it as a generic 3MF.")
        // A `p:path` whose `p` is some other namespace is not the Production extension's.
        let decoy = "<object id=\"2\"><components><component objectid=\"1\" p:path=\"/x\"/></components></object>"
        let data = Package.package(resources: cube + decoy, build: Package.item(2),
                                   namespaces: "xmlns=\"\(Package.core)\" xmlns:p=\"urn:something-else\"")
        #expect(problem(data) == nil)
        // An unprefixed `path` is not either.
        let bare = "<object id=\"2\"><components><component objectid=\"1\" path=\"/x\"/></components></object>"
        #expect(problem(resources: cube + bare, build: Package.item(2)) == nil)
    }

    @Test func prefixesAndDeclarationsCanBeAnywhere() throws {
        // Core elements under a prefix, with a default namespace declared on a lower element, an unknown namespace skipped whole.
        let cube = Package.object(id: 1, mesh: Self.cube)
        let skipped = "<extra xmlns=\"urn:other\"><vertices><vertex x=\"9\" y=\"9\" z=\"9\"/></vertices>"
            + "<triangles><triangle v1=\"0\" v2=\"1\" v3=\"7\"/></triangles></extra>"
        let resources = cube.replacingOccurrences(of: "<mesh>", with: "<mesh>" + skipped)
        #expect(try read(resources: resources, build: Package.item(1)).first?.mesh.positions.count == 8)

        let prefixed = Package.object(id: 1, mesh: Self.cube, prefix: "c:")
        let model = "<?xml version=\"1.0\"?><c:model xmlns:c=\"\(Package.core)\" unit=\"inch\"><c:resources>\(prefixed)</c:resources>"
            + "<c:build><c:item objectid=\"1\"/></c:build></c:model>"
        let meshes = try read(Package.zip(model: model))
        #expect(meshes.count == 1 && meshes[0].mesh.triangleCount == 12 && meshes[0].unit == 25.4)

        // The default namespace is declared on `resources` and again on `build`, not on the root.
        let lowered = "<c:model xmlns:c=\"\(Package.core)\"><resources xmlns=\"\(Package.core)\">\(cube)</resources>"
            + "<build xmlns=\"\(Package.core)\"><item objectid=\"1\"/></build></c:model>"
        #expect(try read(Package.zip(model: lowered)).first?.mesh.triangleCount == 12)

        // A root in a namespace that isn't the core's is no model.
        let wrong = "<model xmlns=\"urn:other\"><resources/><build/></model>"
        #expect(problem(Package.zip(model: wrong)) != nil)
    }

    @Test func attributeOrderIsFree() throws {
        let cube = Package.object(id: 1, mesh: Self.cube)
        let shuffled = cube
            .replacingOccurrences(of: "<vertex x=\"1.0\" y=\"0.0\" z=\"0.0\"/>", with: "<vertex z=\"0.0\" x=\"1.0\" y=\"0.0\"/>")
            .replacingOccurrences(of: "<triangle v1=\"0\" v2=\"2\" v3=\"1\"/>", with: "<triangle v3=\"1\" v1=\"0\" v2=\"2\"/>")
            .replacingOccurrences(of: "<object id=\"1\" >", with: "<object  type=\"model\"   id='1'>")
        #expect(shuffled != cube)
        let meshes = try read(resources: shuffled, build: "<item  objectid = \"1\" />")
        #expect(meshes[0].mesh.triangleCount == 12 && meshes[0].mesh.positions.count == 8)
        #expect(abs(meshes[0].mesh.signedVolume - 1) < 1e-6)
    }

    @Test func requiredExtensionsWeCannotReadAreRefused() throws {
        let cube = Package.object(id: 1, mesh: Self.cube)
        let namespaces = "xmlns=\"\(Package.core)\" xmlns:m=\"\(Package.materials)\" xmlns:p=\"\(Package.production)\" "
            + "xmlns:b=\"\(Package.beamLattice)\" xmlns:x=\"urn:unknown-extension\""
        for supported in ["m", "p", "m p", " p  m "] {
            let data = Package.package(resources: cube, build: Package.item(1), attributes: "requiredextensions=\"\(supported)\"",
                                       namespaces: namespaces)
            #expect(problem(data) == nil, "\(supported)")
        }
        for refused in ["b", "m b", "x", "unbound"] {
            let data = Package.package(resources: cube, build: Package.item(1), attributes: "requiredextensions=\"\(refused)\"",
                                       namespaces: namespaces)
            guard case .unsupportedExtension(let name)? = problem(data) else {
                Issue.record("\(refused) was not refused")
                continue
            }
            let named = refused.split(separator: " ").last.map(String.init) ?? ""
            #expect(name == (named == "x" ? "urn:unknown-extension" : named == "b" ? Package.beamLattice : named), "\(name)")
        }
    }

    @Test func aModelInUTF16IsRefusedAndABOMIsSkipped() throws {
        let model = Package.model(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1))
        let sixteen = try #require(model.data(using: .utf16))
        guard case .malformedModel(let reason)? = problem(Package.zip(modelBytes: sixteen)) else {
            Issue.record("not refused")
            return
        }
        #expect(reason.contains("UTF-16"))
        let withBOM = Data([0xEF, 0xBB, 0xBF]) + Data(model.utf8)
        let zip = ZipReaderForeignTests.build([
            .init(name: "_rels/.rels", body: Data(Package.relationships().utf8)), .init(name: "3D/3dmodel.model", body: withBOM),
        ], zip64: false)
        #expect(try read(zip).first?.mesh.triangleCount == 12)
    }

    @Test func theNamesOfObjectsMayBeAnyBytes() throws {
        let bytes = Data(Package.model(resources: Package.object(id: 1, mesh: Self.cube, attributes: "name=\"@@\""),
                                       build: Package.item(1)).utf8)
        var damaged = bytes
        let at = try #require(damaged.range(of: Data("@@".utf8)))
        damaged.replaceSubrange(at, with: [0xFF, 0xFE])
        let zip = ZipReaderForeignTests.build([
            .init(name: "_rels/.rels", body: Data(Package.relationships().utf8)), .init(name: "3D/3dmodel.model", body: damaged),
        ], zip64: false)
        #expect(try read(zip).first?.mesh.triangleCount == 12)
    }

    // MARK: Hostile files

    /// `levels` objects above a triangle object (ID 1), each placing the one below `fan` times; the build item is the top one.
    func nesting(levels: Int, fan: Int, leaf: TriangleMesh = triangle) -> Data {
        var resources = Package.object(id: 1, mesh: leaf)
        for level in 1...levels { resources += Package.assembly(id: level + 1, Array(repeating: (level, nil), count: fan)) }
        return Package.package(resources: resources, build: Package.item(levels + 1))
    }

    @Test func nestedComponentsAreCountedBeforeInstancing() {
        // Ten levels of ten over one triangle: ten thousand million, found without making one.
        #expect(problem(nesting(levels: 10, fan: 10)) == .tooManyTriangles(10_000_000_000))
        // Thirty-two levels: the count saturates rather than overflows, and the walk is as long as the file, not the product.
        #expect(problem(nesting(levels: 32, fan: 10)) == .overTriangleLimit)
        // With the limit as a parameter, a small file crosses it.
        #expect(problem(nesting(levels: 3, fan: 10), limit: 500) == .tooManyTriangles(1000))
        // A subtree with nothing in it costs nothing, however it nests.
        let empty = TriangleMesh(positions: [], triangles: [])
        #expect(problem(nesting(levels: 32, fan: 10, leaf: empty)) == .noTriangles)
    }

    @Test func aMeshThatIsNestedAndShallowEnoughIsInstanced() throws {
        let meshes = try read(nesting(levels: 3, fan: 4))
        #expect(meshes.count == 1 && meshes[0].mesh.triangleCount == 64)
    }

    @Test func storedTrianglesAreLimitedToo() {
        #expect(problem(Package.package(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1)), limit: 11)
            == .overTriangleLimit)
    }

    @Test func aCycleIsRefused() {
        let cube = Package.object(id: 1, mesh: Self.cube)
        let loop = Package.assembly(id: 2, [(3, nil)]) + Package.assembly(id: 3, [(2, nil)])
        let own = Package.assembly(id: 2, [(1, nil), (2, nil)])
        for resources in [cube + loop, cube + own] {
            guard case .malformedModel(let reason)? = problem(resources: resources, build: Package.item(2)) else {
                Issue.record("not refused")
                continue
            }
            #expect(reason.contains("itself"))
        }
    }

    @Test func nestingStopsAtDepth32() throws {
        func chain(hops: Int) -> Data {
            var resources = Package.object(id: 1, mesh: Self.cube)
            for level in 1..<(hops + 1) { resources += Package.assembly(id: level + 1, [(level, nil)]) }
            return Package.package(resources: resources, build: Package.item(hops + 1))
        }
        #expect(try read(chain(hops: 32)).first?.mesh.triangleCount == 12)
        guard case .malformedModel(let reason)? = problem(chain(hops: 33)) else {
            Issue.record("depth 33 was not refused")
            return
        }
        #expect(reason.contains("deeply"))
    }

    @Test func aDoctypeIsRefused() {
        let model = Package.model(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1))
        let bomb = "<?xml version=\"1.0\"?><!DOCTYPE model [<!ENTITY a \"aaaa\"><!ENTITY b \"&a;&a;&a;&a;\">]>" + model
        guard case .malformedModel(let reason)? = problem(Package.zip(model: bomb)) else {
            Issue.record("not refused")
            return
        }
        #expect(reason.contains("DOCTYPE"))
    }

    @Test func badNumbersAndIndicesAreRefused() {
        let cube = Package.object(id: 1, mesh: Self.cube)
        func mutated(_ from: String, _ to: String) -> MeshImportProblem? {
            let resources = cube.replacingOccurrences(of: from, with: to)
            #expect(resources != cube, "\(from)")
            return problem(resources: resources, build: Package.item(1))
        }
        for index in ["8", "4294967296", "99999999999999999999", "-1", "1.5", "x", "", "+1"] {
            guard case .malformedModel? = mutated("v3=\"1\"", "v3=\"\(index)\"") else { Issue.record("index \(index)"); continue }
        }
        for coordinate in ["nan", "NaN", "inf", "-inf", "1e999", "", "1,5", "0x10", "1e", "--1"] {
            guard case .malformedModel? = mutated("x=\"1.0\" y=\"1.0\" z=\"0.0\"", "x=\"\(coordinate)\" y=\"1.0\" z=\"0.0\"") else {
                Issue.record("coordinate \(coordinate)")
                continue
            }
        }
        guard case .malformedModel? = mutated("v2=\"2\" ", "") else { Issue.record("missing index"); return }
        guard case .malformedModel? = mutated("y=\"1.0\" z=\"0.0\"", "z=\"0.0\"") else { Issue.record("missing coordinate"); return }
    }

    @Test func objectsAndReferencesAreChecked() {
        let cube = Package.object(id: 1, mesh: Self.cube)
        for (resources, build) in [
            (cube, Package.item(9)),
            (cube + Package.assembly(id: 2, [(9, nil)]), Package.item(2)),
            (cube + cube, Package.item(1)),
            (cube, "<item/>"),
            (cube, "<item objectid=\"-1\"/>"),
            (cube.replacingOccurrences(of: "<object id=\"1\"", with: "<object id=\"one\""), Package.item(1)),
        ] {
            guard case .malformedModel? = problem(resources: resources, build: build) else {
                Issue.record("accepted \(resources.suffix(60)) \(build)")
                continue
            }
        }
    }

    @Test func transformsAreChecked() {
        let cube = Package.object(id: 1, mesh: Self.cube)
        let bad = [
            "1 0 0 0 1 0 0 0 1 0 0", "1 0 0 0 1 0 0 0 1 0 0 0 0", "", "a b c", "nan 0 0 0 1 0 0 0 1 0 0 0", "1 0 0 0 1 0 0 0 1 0 0 1e999",
            // Singular: a flat matrix, zeros.
            "1 0 0 0 1 0 0 0 0 0 0 0", "0 0 0 0 0 0 0 0 0 5 5 5", "1 2 3 2 4 6 3 6 9 0 0 0",
        ]
        for transform in bad {
            guard case .malformedModel? = problem(resources: cube, build: Package.item(1, transform)) else {
                Issue.record("accepted “\(transform)”")
                continue
            }
            let inComponent = cube + Package.assembly(id: 2, [(1, transform)])
            guard case .malformedModel? = problem(resources: inComponent, build: Package.item(2)) else {
                Issue.record("accepted “\(transform)” on a component")
                continue
            }
        }
    }

    @Test func aTransformThatOverflowsOnceAppliedIsRefused() {
        let huge = "1e30 0 0 0 1 0 0 0 1 0 0 0"
        let twice = Package.object(id: 1, mesh: Self.cube) + Package.assembly(id: 2, [(1, huge)]) + Package.assembly(id: 3, [(2, huge)])
            + Package.assembly(id: 4, [(3, huge)])
        #expect(problem(resources: twice, build: Package.item(4)) == .coordinatesOverflow)
    }

    @Test func aModelEntryOver2GBIsRefused() throws {
        var bytes = Package.zip(model: Package.model(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1)))
        // The central directory's size for the model is 3.75 GB; the bytes are the few thousand that are really there.
        let record = try #require(bytes.range(of: Data([0x50, 0x4B, 0x01, 0x02]), options: .backwards))
        let at = record.lowerBound + 24
        bytes.replaceSubrange(at..<(at + 4), with: [0x00, 0x00, 0x00, 0xF0])
        #expect(problem(bytes) == .modelTooLarge)
    }

    @Test func anEncryptedModelIsEncrypted() {
        let model = Package.model(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1))
        #expect(problem(Package.zip(model: model, flags: 1)) == .encrypted)
        #expect(MeshImportProblem.encrypted.message == "This 3MF is encrypted.")
        // Secure Content: a key store relationship, or the extension required.
        let store = Package.relationships() .replacingOccurrences(of: "</Relationships>", with:
            "<Relationship Target=\"/Secure/keystore.xml\" Id=\"rel1\" Type=\"http://schemas.microsoft.com/3dmanufacturing/2019/04/keystore\"/></Relationships>")
        #expect(problem(Package.zip(model: model, relationships: store)) == .encrypted)
    }

    @Test func aCorruptModelPartIsReportedNotTrapped() {
        var zip = Package.zip(model: Package.model(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1)))
        zip[zip.count / 2] ^= 0xFF
        let found = problem(zip)
        #expect(found != nil)
        // An XML that stops short.
        let cut = Package.model(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1)).dropLast(30)
        guard case .malformedModel? = problem(Package.zip(model: String(cut))) else { Issue.record("a cut file was accepted"); return }
        #expect(MeshImportProblem.malformedModel("x").message == "This 3MF is damaged: x")
    }

    @Test func cancellationIsReported() {
        let data = Package.package(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1))
        #expect(throws: CancellationError.self) { try ThreeMFReader.read(data, isCancelled: { true }) }
    }

    @Test func theLargeCaseStaysFast() throws {
        // A hundred thousand triangles through the whole path, to see the hot loops do not allocate per element.
        let big = MeshFixtures.subdividedCube(divisions: 90)
        let data = Package.package(resources: Package.object(id: 1, mesh: big), build: Package.item(1))
        let meshes = try read(data)
        #expect(meshes[0].mesh.triangleCount == big.triangleCount && meshes[0].mesh.positions.count == big.positions.count)
    }
}

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
}
