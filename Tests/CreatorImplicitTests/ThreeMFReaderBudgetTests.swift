import CreatorGraph
import Foundation
import Testing
@testable import CreatorImplicit

/// The model parser's one budget (mesh import spec, Limits): everything a file can make the parser keep or walk is capped, and each
/// vector is a small file that must be refused, or read in bounded work. No test here reads a clock.
extension ThreeMFReaderTests {
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var made = 0
        func next() -> Int {
            lock.lock()
            defer { lock.unlock() }
            made += 1
            return made
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return made
        }
    }

    // MARK: Lists the parser walks

    @Test func aTransformIsRefusedAtItsThirteenthNumber() {
        let cube = Package.object(id: 1, mesh: Self.cube)
        let long = String(repeating: "1 ", count: 100_000)
        #expect(problem(resources: cube, build: Package.item(1, long)) == .malformedModel("a transform isn't twelve finite numbers."))
        let component = cube + Package.assembly(id: 2, [(1, long)])
        #expect(problem(resources: component, build: Package.item(2)) == .malformedModel("a transform isn't twelve finite numbers."))
    }

    @Test func aListOfRequiredExtensionsIsBounded() {
        let cube = Package.object(id: 1, mesh: Self.cube)
        let namespaces = "xmlns=\"\(Package.core)\" xmlns:a=\"\(Package.materials)\""
        let many = String(repeating: "a ", count: 100_000)
        let data = Package.package(resources: cube, build: Package.item(1), attributes: "requiredextensions=\"\(many)\"",
                                   namespaces: namespaces)
        guard case .malformedModel? = problem(data) else {
            Issue.record("a long list was accepted")
            return
        }
        // Undeclared names stop at the first.
        let unknown = Package.package(resources: cube, build: Package.item(1),
                                      attributes: "requiredextensions=\"\(String(repeating: "zz ", count: 100_000))\"")
        #expect(problem(unknown) == .unsupportedExtension("zz"))
    }

    @Test func namespaceDeclarationsAreDedupedAndCapped() throws {
        let cube = Package.object(id: 1, mesh: Self.cube)
        let again = String(repeating: "xmlns:a=\"urn:same\" ", count: 50_000)
        let same = Package.package(resources: cube, build: Package.item(1), namespaces: "xmlns=\"\(Package.core)\" " + again)
        #expect(try read(same).first?.mesh.triangleCount == 12)
        // The last declaration of a prefix is the one in force.
        let rebound = Package.package(resources: cube, build: Package.item(1),
                                      attributes: "requiredextensions=\"a\"",
                                      namespaces: "xmlns=\"\(Package.core)\" xmlns:a=\"urn:first\" xmlns:a=\"\(Package.production)\"")
        #expect(problem(rebound) == nil)
        let distinct = (0..<1_000).map { "xmlns:p\($0)=\"urn:x\"" }.joined(separator: " ")
        let flood = Package.package(resources: cube, build: Package.item(1), namespaces: "xmlns=\"\(Package.core)\" " + distinct)
        guard case .malformedModel? = problem(flood) else {
            Issue.record("a flood of declarations was accepted")
            return
        }
    }

    // MARK: Things the parser keeps

    @Test func anAttributeIsRefusedWhereItsRepeatKeepsAnother() {
        let cube = Package.object(id: 1, mesh: Self.cube)
        let transform = "1 0 0 0 1 0 0 0 1 0 0 0"
        for build in [
            "<item objectid=\"1\" transform=\"\(transform)\" transform=\"\(transform)\"/>",
        ] {
            guard case .malformedModel? = problem(resources: cube, build: build) else { Issue.record("\(build)"); continue }
        }
        let component = "<object id=\"2\"><components><component objectid=\"1\" transform=\"\(transform)\" transform=\"\(transform)\"/>"
            + "</components></object>"
        guard case .malformedModel? = problem(resources: cube + component, build: Package.item(2)) else {
            Issue.record("a repeated component transform")
            return
        }
        let twice = cube.replacingOccurrences(of: "<object id=\"1\"", with: "<object id=\"1\" id=\"1\"")
        guard case .malformedModel? = problem(resources: twice, build: Package.item(1)) else {
            Issue.record("a repeated object id")
            return
        }
    }

    @Test func objectsComponentsAndItemsShareOneCap() throws {
        func read(_ resources: String, _ build: String, records: Int) throws -> [ImportedMesh] {
            try ThreeMFReader.read(Package.package(resources: resources, build: build), triangleLimit: 1_000, recordLimit: records,
                                   isCancelled: { false })
        }
        let objects = (2...1_000).map { "<object id=\"\($0)\"/>" }.joined()
        let cube = Package.object(id: 1, mesh: Self.cube)
        #expect(throws: MeshImportProblem.self) { try read(cube + objects, Package.item(1), records: 100) }
        #expect(try read(cube + objects, Package.item(1), records: 2_000).count == 1)
        // 60 components and 60 items between them pass 100.
        let parts = Package.assembly(id: 2, Array(repeating: (1, nil), count: 60))
        let items = String(repeating: Package.item(1), count: 60)
        #expect(throws: MeshImportProblem.self) { try read(cube + parts, items, records: 100) }
        #expect(try read(cube + parts, items, records: 200).count == 60)
    }

    @Test func manyVerticesAreMoreTrianglesThanTheFileMayHold() {
        let positions = (0..<40).map { SIMD3<Float>(Float($0), 0, 0) }
        let spread = TriangleMesh(positions: positions, triangles: [0, 1, 2])
        let data = Package.package(resources: Package.object(id: 1, mesh: spread), build: Package.item(1))
        #expect(problem(data, limit: 10) == .overTriangleLimit)
        #expect(problem(data, limit: 14) == nil)
        #expect(MeshImportProblem.overTriangleLimit.message
            == "This file has more triangles than Import Mesh takes: at most 10,000,000.")
    }

    // MARK: Placement

    @Test func placementMovesOnlyTheCornersItUses() throws {
        // 20,000 vertices of which three are used, placed 400 times: the work is 400 triangles, not 8 million vertices.
        let positions = (0..<20_000).map { SIMD3<Float>(Float($0 % 100), Float($0 / 100), 0) }
        let big = TriangleMesh(positions: positions, triangles: [0, 1, 100])
        let resources = Package.object(id: 1, mesh: big) + Package.assembly(id: 2, Array(repeating: (1, nil), count: 400))
        let calls = Calls()
        let data = Package.package(resources: resources, build: Package.item(2))
        let meshes = try ThreeMFReader.read(data, isCancelled: { _ = calls.next(); return false })
        #expect(meshes[0].mesh.triangleCount == 400 && meshes[0].mesh.positions.count == 3)
        // The parse asks as it asks (by events and by attribute bytes: this model has about 1 MiB of them); the placement's own work, 400
        // triangles, asks once for its first unit and once more for the build item at most.
        let parseAsks = Calls()
        _ = try parse(data, isCancelled: { _ = parseAsks.next(); return false })
        #expect(calls.count - parseAsks.count <= 3, "placement asked \(calls.count - parseAsks.count) times")
    }

    /// The model part of a package, parsed alone (the zip and the placement left out).
    func parse(_ package: Data, isCancelled: @escaping () -> Bool) throws -> ThreeMFModel {
        let zip = try ZipReader(data: package)
        let bytes = try zip.contents(of: "3D/3dmodel.model")
        return try bytes.withUnsafeBytes { try ThreeMFModelParser.parse($0, limits: ThreeMFLimits(), isCancelled: isCancelled) }
    }

    @Test func manyElementsEachUnderAnyThresholdAreMeteredTogether() throws {
        // 100 triangles of 20 KB of attributes each: none is long, together they are 2 MB of walking. The parse asks about
        // cancellation by the bytes it has walked, not by the length of any one element (measured: 3,331 elements of 60 KB made a 463 KB
        // file inflate to 200 MB and parse for 15 s between two asks).
        let pad = String(repeating: "a", count: 20_000)
        let triangles = (0..<100).map { _ in "<triangle v1=\"0\" v2=\"1\" v3=\"2\" note=\"\(pad)\"/>" }.joined()
        let mesh = "<mesh><vertices><vertex x=\"0\" y=\"0\" z=\"0\"/><vertex x=\"1\" y=\"0\" z=\"0\"/><vertex x=\"0\" y=\"1\" z=\"0\"/>"
            + "</vertices><triangles>\(triangles)</triangles></mesh>"
        let data = Package.package(resources: "<object id=\"1\">\(mesh)</object>", build: Package.item(1))
        let calls = Calls()
        let model = try parse(data, isCancelled: { _ = calls.next(); return false })
        #expect(model.triangles.count == 300)
        // The first event, then once per MiB: 100 × 20 KB is 1.9 MiB.
        #expect(calls.count >= 2, "asked \(calls.count) times")
        let cancelled = Calls()
        #expect(throws: CancellationError.self) { try parse(data, isCancelled: { cancelled.next() >= 2 }) }
        #expect(cancelled.count == 2)
    }

    @Test func emptyPartsAreNeverVisited() throws {
        let cube = Package.object(id: 1, mesh: Self.cube)
        let empty = "<object id=\"2\"><components/></object>"
        let noisy = Package.assembly(id: 3, [(1, nil)] + Array(repeating: (2, nil as String?), count: 5_000))
        let fan = Package.assembly(id: 4, Array(repeating: (3, nil), count: 50))
        let meshes = try read(resources: cube + empty + noisy + fan, build: Package.item(4))
        #expect(meshes.count == 1 && meshes[0].mesh.triangleCount == 600)
    }

    @Test func placementAsksAboutCancellation() {
        let data = Package.package(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1))
        let calls = Calls()
        // The parse asks first; the second ask is the placement's.
        #expect(throws: CancellationError.self) { try ThreeMFReader.read(data, isCancelled: { calls.next() >= 2 }) }
        #expect(calls.count == 2)
    }

    // MARK: Support structures

    @Test(arguments: ["support", "solidsupport", "other"])
    func supportStructuresAreLeftOut(_ type: String) throws {
        let cube = Package.object(id: 1, mesh: Self.cube)
        let supported = Package.object(id: 2, mesh: Self.cube, attributes: "type=\"\(type)\"")
        // As a build item: the other item remains.
        let item = try #require(try read(resources: cube + supported, build: Package.item(1) + Package.item(2)).first)
        #expect(item.supportsLeftOut && item.mesh.triangleCount == 12)
        let meshes = try read(resources: cube + supported, build: Package.item(1) + Package.item(2))
        #expect(meshes.count == 1)
        // As a component: the assembly keeps the model part only.
        let assembly = Package.assembly(id: 3, [(1, nil), (2, "1 0 0 0 1 0 0 0 1 5 0 0")])
        let part = try #require(try read(resources: cube + supported + assembly, build: Package.item(3)).first)
        #expect(part.mesh.triangleCount == 12 && part.supportsLeftOut)
        // With nothing else there is nothing.
        #expect(problem(resources: supported, build: Package.item(2)) == .noTriangles)
        #expect(problem(resources: cube + supported + Package.assembly(id: 3, [(2, nil)]), build: Package.item(3)) == .noTriangles)
        // Anything under a support is left out with it, even a cycle.
        let hollow = "<object id=\"4\" type=\"\(type)\"><components><component objectid=\"4\"/></components></object>"
        #expect(try read(resources: cube + hollow + Package.assembly(id: 5, [(1, nil), (4, nil)]), build: Package.item(5)).count == 1)
    }

    @Test(arguments: ["model", "surface", "something-new"])
    func otherTypesAreKept(_ type: String) throws {
        let part = Package.object(id: 1, mesh: Self.cube, attributes: "type=\"\(type)\"")
        let mesh = try #require(try read(resources: part, build: Package.item(1)).first)
        #expect(mesh.mesh.triangleCount == 12 && !mesh.supportsLeftOut)
        #expect(ThreeMFReader.supportsLeftOutWarning == "This 3MF's support structures were left out.")
    }

    @Test func anObjectWithAMeshAndComponentsIsRefused() {
        let cube = Package.object(id: 1, mesh: Self.cube)
        let comps = "<components><component objectid=\"1\"/></components>"
        for mixed in [
            cube.replacingOccurrences(of: "</mesh>", with: "</mesh>" + comps),
            cube.replacingOccurrences(of: "<mesh>", with: comps + "<mesh>"),
        ] {
            guard case .malformedModel(let reason)? = problem(resources: mixed, build: Package.item(1)) else {
                Issue.record("a mixed object was accepted")
                continue
            }
            #expect(reason.contains("mesh") && reason.contains("components"))
        }
    }

    // MARK: Messages

    @Test func textFromTheFileIsCutToEightyCharacters() {
        let long = String(repeating: "a", count: 1_000_000)
        let cube = Package.object(id: 1, mesh: Self.cube)
        let data = Package.package(resources: cube, build: Package.item(1), attributes: "requiredextensions=\"b\"",
                                   namespaces: "xmlns=\"\(Package.core)\" xmlns:b=\"urn:\(long)\"")
        guard case .unsupportedExtension(let name)? = problem(data) else {
            Issue.record("not refused")
            return
        }
        #expect(name.count == 81 && name.hasPrefix("urn:aaaa") && name.hasSuffix("…"))
        #expect(MeshImportProblem.unsupportedExtension(name).message == "This 3MF needs an extension that isn't supported: \(name).")
        #expect(MeshImportProblem.unsupportedExtension(long).message.count < 200)
        #expect(MeshImportProblem.modelTooLarge.message == "This 3MF's model is larger than the 2 GB limit.")
    }

    @Test func aModelThatCouldNotHaveInflatedToItsSizeOrARelationshipsPartOverTheLimitIsTooLarge() throws {
        var bytes = ThreeMFFixtures.foreignTetrahedra
        // The third central directory record is the model's; claim a gigabyte for its few hundred deflated bytes.
        var record = 0
        var seen = 0
        while seen < 3, record + 4 <= bytes.count {
            if bytes[record...(record + 3)].elementsEqual([0x50, 0x4B, 0x01, 0x02]) { seen += 1 }
            if seen < 3 { record += 1 }
        }
        try #require(seen == 3)
        bytes[record + 27] = 0x40
        #expect(problem(Data(bytes)) == .modelTooLarge)
        let padding = Data(repeating: 0x20, count: (1 << 20) + 1)
        let rels = Data(Package.relationships().utf8) + padding
        let big = ZipReaderForeignTests.build([
            .init(name: "_rels/.rels", body: rels),
            .init(name: "3D/3dmodel.model", body: Data(Package.model(resources: "", build: "").utf8)),
        ], zip64: false)
        // A relationships part is not the model: over its limit it is damaged, not "larger than the 2 GB limit".
        #expect(problem(big) == .malformedModel("its relationships part is larger than any real one."))
    }

    // MARK: Part names

    @Test func aPartNameMatchesExactlyThenPercentDecodedThenWithoutCase() throws {
        let model = Package.model(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1))
        let cases: [(target: String, entry: String)] = [
            ("/3D/3dmodel.model", "3D/3dmodel.model"),
            ("/3D/my%20part.model", "3D/my part.model"),
            ("/3D/my%20part.model", "3D/my%20part.model"),
            ("/3D/3DModel.MODEL", "3D/3dmodel.model"),
            ("/3D/My%20Part.model", "3D/my part.model"),
        ]
        for (target, entry) in cases {
            let data = Package.zip(model: model, entry: entry, relationships: Package.relationships(target: target))
            #expect(try read(data).first?.mesh.triangleCount == 12, "\(target) -> \(entry)")
        }
        // The relationships part itself is found whatever its case.
        let upper = ZipReaderForeignTests.build([
            .init(name: "_RELS/.RELS", body: Data(Package.relationships().utf8)), .init(name: "3D/3dmodel.model", body: Data(model.utf8)),
        ], zip64: false)
        #expect(try read(upper).first?.mesh.triangleCount == 12)
        // An exact match wins over a case-folded one.
        let both = ZipReaderForeignTests.build([
            .init(name: "_rels/.rels", body: Data(Package.relationships(target: "/a.model").utf8)),
            .init(name: "A.model", body: Data(Package.model(resources: "", build: "").utf8)),
            .init(name: "a.model", body: Data(model.utf8)),
        ], zip64: false)
        #expect(try read(both).first?.mesh.triangleCount == 12)
        #expect(problem(Package.zip(model: model, entry: "3D/other.model")) == .noModelPart)
    }

    // MARK: What a failed read says

    @Test func anAllocationThatFailsIsTheComputersNotTheFiles() throws {
        let package = Package.package(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1))
        let entry = try #require(try ZipReader(data: package).entries.first)
        #expect(ZipReader.zipError(for: InflateError.allocationFailed, in: entry) == .allocationFailed(entry.name))
        #expect(ZipReader.zipError(for: InflateError.malformed, in: entry) == .checksumMismatch(entry.name))
        #expect(ThreeMFReader.problem(for: .allocationFailed("x")) == .notEnoughMemory)
        #expect(ThreeMFReader.problem(for: .checksumMismatch("x")) == .malformedModel("a part of the file can't be read."))
        #expect(MeshImportProblem.notEnoughMemory.message == "This 3MF is too large to open with the memory available.")
    }

    @Test func aRelationshipsPartOverAMegabyteIsDamagedNotTooLarge() {
        let padding = String(repeating: " ", count: (1 << 20) + 1)
        let relationships = Package.relationships() + "<!--\(padding)-->"
        let model = Package.model(resources: Package.object(id: 1, mesh: Self.cube), build: Package.item(1))
        let problem = problem(Package.zip(model: model, relationships: relationships))
        guard case .malformedModel(let reason)? = problem else {
            Issue.record("\(String(describing: problem))")
            return
        }
        #expect(reason == "its relationships part is larger than any real one.")
        #expect(problem?.message.contains("2 GB") == false)
    }
}
