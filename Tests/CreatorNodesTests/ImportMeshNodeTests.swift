import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation
import Testing
@testable import CreatorNodes

/// Import Mesh (mesh import spec, the node) through the real evaluator: the mesh it makes, its facts, warnings and refusals.
struct ImportMeshNodeTests {
    let folder = TempFolderForNodes()

    typealias Face = (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
    static let a = SIMD3<Float>(0, 0, 0), b = SIMD3<Float>(10, 0, 0), c = SIMD3<Float>(0, 10, 0), d = SIMD3<Float>(0, 0, 10)
    /// A tetrahedron wound counter-clockwise seen from outside.
    static let tetra: [Face] = [(a, c, b), (a, b, d), (a, d, c), (b, c, d)]

    /// An ASCII STL of `faces`.
    static func stl(_ faces: [Face]) -> Data {
        var text = "solid t\n"
        for face in faces {
            text += "facet normal 0 0 0\nouter loop\n"
            for p in [face.0, face.1, face.2] { text += "vertex \(p.x) \(p.y) \(p.z)\n" }
            text += "endloop\nendfacet\n"
        }
        return Data((text + "endsolid t\n").utf8)
    }

    /// An Import Mesh node holding `data` as an embedded file, and the resolver that holds it.
    func embedded(_ data: Data, _ values: [SocketName: ConstantValue] = [:]) -> (Harness, Node, ImageResolver) {
        var h = Harness()
        let hash = ImageHash(of: data)
        let node = h.add(ImportMeshNode.self, values.merging([NodeSetting.meshFile: .meshFile(.embedded(hash))]) { _, new in new })
        return (h, node, ImageResolver(embedded: [hash: data]))
    }

    func mesh(_ report: EvaluationReport, _ node: Node) throws -> TriangleMesh {
        let value = try #require(report.value(node, "mesh"), "\(String(describing: report.state(node)))")
        return try #require(value.items.first.flatMap { if case .mesh(let payload) = $0 { payload as? TriangleMesh } else { nil } })
    }

    @Test func readsAnSTLOntoTheDefaultPlane() async throws {
        let (h, node, images) = embedded(Self.stl(Self.tetra))
        let report = try await h.run([node], images: images)
        let made = try mesh(report, node)
        #expect(made.triangleCount == 4 && made.vertexCount == 4)
        #expect(made.positions.contains(SIMD3<Float>(10, 0, 0)) && made.positions.contains(SIMD3<Float>(0, 0, 10)))
        #expect(made.quality == .export && made.resolution == 0 && made.source == nil)
        #expect(report.isOK(node))
    }

    @Test func theMeshDrawsItsSharpEdgesHard() async throws {
        let (h, node, images) = embedded(Self.stl(Self.tetra))
        let made = try mesh(await h.run([node], images: images), node)
        #expect(made.creaseAngle == 30)
        let kept = made.checked(highlights: [], facts: [])
        #expect(kept.creaseAngle == 30)
    }

    @Test func noFileChosenSaysSo() async throws {
        var h = Harness()
        let node = h.add(ImportMeshNode.self)
        #expect(try await h.run([node]).error(node) == MeshImportProblem.notChosen.message)
    }

    @Test func factsAreRight() async throws {
        let (h, node, images) = embedded(Self.stl(Self.tetra), ["units": .integer(2)])
        let made = try mesh(await h.run([node], images: images), node)
        let facts = Dictionary(uniqueKeysWithValues: made.extraFacts.map { ($0.label, $0.value) })
        #expect(facts["Triangles"] == "4" && facts["Vertices"] == "4")
        #expect(facts["Size"] == "100 × 100 × 100 mm")
        #expect(facts["Closed"] == "Yes")
        #expect(facts["File"] == "Embedded")
        let open = Array(Self.tetra.dropLast())
        let (h2, node2, images2) = embedded(Self.stl(open))
        let facts2 = try mesh(await h2.run([node2], images: images2), node2).extraFacts
        #expect(facts2.contains(PayloadFact("Closed", "No")))
    }

    @Test func aLinkedFileNamesItself() async throws {
        let file = try folder.write(Self.stl(Self.tetra), to: "part.stl")
        var h = Harness()
        let path = file.path(percentEncoded: false)
        let node = h.add(ImportMeshNode.self, [NodeSetting.meshFile: .meshFile(.linked(relativePath: nil, absolutePath: path))])
        let made = try mesh(await h.run([node]), node)
        #expect(made.extraFacts.contains(PayloadFact("File", "part.stl")))
    }

    @Test func eachWarningFires() async throws {
        let open = Array(Self.tetra.dropLast())
        var flippedFaces = Self.tetra
        flippedFaces[3] = (Self.b, Self.d, Self.c)
        let third = SIMD3<Float>(5, 5, -5)
        let overfull = Self.tetra + [(Self.a, Self.b, third)]
        let degenerate = Self.tetra + [(Self.a, Self.a, Self.b)]
        let cases: [(Data, String)] = [
            (Self.stl(open), "This mesh isn't closed: 3 open edges."),
            (Self.stl(overfull), "This mesh has 1 edge shared by more than two faces."),
            (Self.stl(flippedFaces), "3 edges join faces flipped against each other."),
            (Self.stl(degenerate), "1 degenerate triangle was dropped."),
        ]
        for (data, text) in cases {
            let (h, node, images) = embedded(data)
            let report = try await h.run([node], images: images)
            #expect(report.warning(node)?.contains(text) == true, "\(text) in \(String(describing: report.state(node)))")
        }
    }

    @Test func warningsAreWordedForOneAndForMany() {
        #expect(ImportMeshNode.warnings(open: 1, overfull: 0, flipped: 0, dropped: 0, triangles: 4)
                == ["This mesh isn't closed: 1 open edge."])
        #expect(ImportMeshNode.warnings(open: 0, overfull: 2, flipped: 1, dropped: 2, triangles: 4)
                == ["This mesh has 2 edges shared by more than two faces.", "1 edge joins faces flipped against each other.",
                    "2 degenerate triangles were dropped.",
                ])
        #expect(ImportMeshNode.warnings(open: 0, overfull: 0, flipped: 0, dropped: 0, triangles: 2_000_000).isEmpty)
        #expect(ImportMeshNode.warnings(open: 0, overfull: 0, flipped: 0, dropped: 0, triangles: 2_000_001)
                == ["This mesh has 2,000,001 triangles, so the view may be slow."])
    }

    @Test func unitsScale() async throws {
        for (units, factor) in [(0, 1.0), (1, 1), (2, 10), (3, 1000), (4, 25.4)] {
            let (h, node, images) = embedded(Self.stl(Self.tetra), ["units": .integer(units)])
            let made = try mesh(await h.run([node], images: images), node)
            let far = made.positions.map(\.x).max() ?? 0
            #expect(far == Float(10 * factor), "units \(units)")
        }
    }

    @Test func placementMovesIt() async throws {
        let plane = Plane(origin: Vector3(1, 2, 5), normal: Vector3(0, 0, 1), xAxis: Vector3(0, 1, 0))
        let (h, node, images) = embedded(Self.stl(Self.tetra), ["placement": .plane(plane)])
        let (plain, plainNode, plainImages) = embedded(Self.stl(Self.tetra))
        let before = try mesh(await plain.run([plainNode], images: plainImages), plainNode)
        let after = try mesh(await h.run([node], images: images), node)
        #expect(before.positions.count == after.positions.count)
        for (p, q) in zip(before.positions, after.positions) {
            // x becomes the plane's x axis (world y), y becomes world -x, z stays up.
            #expect(q == SIMD3<Float>(1 - p.y, 2 + p.x, 5 + p.z), "\(p)")
        }
    }

    private func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
    }

    @Test func aSkewedPlacementStaysRigid() async throws {
        let skewed = Plane(origin: Vector3(1, 2, 3), normal: .unitZ, xAxis: Vector3(1, 0, 1))
        let (h, node, images) = embedded(Self.stl(Self.tetra), ["placement": .plane(skewed)])
        let (plain, plainNode, plainImages) = embedded(Self.stl(Self.tetra))
        let before = try mesh(await plain.run([plainNode], images: plainImages), plainNode)
        let after = try mesh(await h.run([node], images: images), node)
        for (i, j) in [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)] {
            let was = distance(before.positions[i], before.positions[j])
            let now = distance(after.positions[i], after.positions[j])
            #expect(abs(was - now) < 1e-4)
        }
        #expect(abs(after.signedVolume - before.signedVolume) < 1e-3)
    }

    @Test func movingPlacementDoesNotReadTheFileAgain() async throws {
        let data = Self.stl(Self.tetra)
        let file = try folder.write(data, to: "keep.stl")
        let date = Date(timeIntervalSince1970: 3_000)
        try folder.touch(file, date)
        var h = Harness()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let node = h.add(ImportMeshNode.self, [NodeSetting.meshFile: .meshFile(reference)])
        let first = try mesh(await h.run([node]), node)
        // The same size and date, other bytes: only a read would notice.
        try folder.write(Data(repeating: 0x41, count: data.count), to: "keep.stl")
        try folder.touch(file, date)
        h.set(node, "placement", .plane(Plane(origin: Vector3(0, 0, 3), normal: .unitZ, xAxis: .unitX)))
        let second = try mesh(await h.run([node]), node)
        #expect(second.positions.map(\.z) == first.positions.map { $0.z + 3 })
        #expect(second.id != first.id)
    }

    @Test func anUnchangedNodeKeepsItsMeshAndAChangedPlacementMakesANewOne() async throws {
        let (h, node, images) = embedded(Self.stl(Self.tetra))
        let evaluator = Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
        let one = try await evaluator.evaluate(h.graph, demand: [node.id], images: images)
        let two = try await evaluator.evaluate(h.graph, demand: [node.id], images: images)
        #expect(try mesh(one, node).id == mesh(two, node).id)
        var moved = h
        moved.set(node, "placement", .plane(Plane(origin: Vector3(1, 0, 0), normal: .unitZ, xAxis: .unitX)))
        let three = try await evaluator.evaluate(moved.graph, demand: [node.id], images: images)
        #expect(try mesh(three, node).id != mesh(one, node).id)
    }

    @Test func anOverflowingUnitRefuses() async throws {
        let big = SIMD3<Float>(1e38, 0, 0)
        let (h, node, images) = embedded(Self.stl([(Self.a, big, Self.c), (Self.a, Self.c, big)]), ["units": .integer(3)])
        #expect(try await h.run([node], images: images).error(node) == MeshImportProblem.coordinatesOverflow.message)
    }

    @Test func aBrokenFileFailsOnceUntilItChanges() async throws {
        let valid = Self.stl(Self.tetra)
        let text = String(bytes: valid, encoding: .utf8) ?? ""
        let broken = Data(text.replacingOccurrences(of: "vertex", with: "vertax").utf8)
        #expect(broken.count == valid.count)
        let file = try folder.write(broken, to: "broken.stl")
        try folder.touch(file, Date(timeIntervalSince1970: 4_000))
        var h = Harness()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let node = h.add(ImportMeshNode.self, [NodeSetting.meshFile: .meshFile(reference)])
        let first = try await h.run([node]).error(node)
        #expect(first != nil)
        // Good bytes of the same size and date: the remembered failure answers, nothing is read.
        try folder.write(valid, to: "broken.stl")
        try folder.touch(file, Date(timeIntervalSince1970: 4_000))
        #expect(try await h.run([node]).error(node) == first)
        try folder.touch(file, Date(timeIntervalSince1970: 5_000))
        #expect(try await h.run([node]).error(node) == nil)
    }

    @Test func twoNodesOnOneFileShareTheRead() async throws {
        let cache = ImportedMeshCache(budgetBytes: 1 << 20)
        let counter = ReadCounter()
        let stamp = ImageStamp.embedded(ImageHash(of: Data("same".utf8)), isPresent: true)
        let read: @Sendable () throws -> [ImportedMesh] = {
            counter.increment()
            return [try STLReader.read(Self.stl(Self.tetra), isCancelled: { false })]
        }
        let one = try await cache.meshes(for: stamp, read: read)
        let two = try await cache.meshes(for: stamp, read: read)
        #expect(counter.value == 1)
        #expect(one.map(\.mesh.positions) == two.map(\.mesh.positions))
        #expect(await cache.count == 1)
    }

    @Test func theCacheRemembersAFailureNotAReadErrorAndTrimsToItsBudget() async throws {
        let cache = ImportedMeshCache(budgetBytes: 100)
        let stamp = ImageStamp.embedded(ImageHash(of: Data("bad".utf8)), isPresent: true)
        let counter = ReadCounter()
        let failing: @Sendable () throws -> [ImportedMesh] = {
            counter.increment()
            throw MeshImportProblem.endsEarly
        }
        for _ in 0..<2 { await #expect(throws: MeshImportProblem.endsEarly) { try await cache.meshes(for: stamp, read: failing) } }
        #expect(counter.value == 1)
        let unreadable: @Sendable () throws -> [ImportedMesh] = {
            counter.increment()
            throw MeshImportProblem.unreadable(name: "x", reason: "busy")
        }
        let other = ImageStamp.embedded(ImageHash(of: Data("busy".utf8)), isPresent: true)
        for _ in 0..<2 { await #expect(throws: MeshImportProblem.self) { try await cache.meshes(for: other, read: unreadable) } }
        #expect(counter.value == 3)
        #expect(await cache.problemCount == 1)
        // A mesh bigger than the whole budget is read but not kept.
        let big = ImageStamp.embedded(ImageHash(of: Data("big".utf8)), isPresent: true)
        _ = try await cache.meshes(for: big) {
            [try STLReader.read(Self.stl(Self.tetra + Self.tetra.map { ($0.0 + 20, $0.1 + 20, $0.2 + 20) }), isCancelled: { false })]
        }
        #expect(await cache.count == 0)
    }

    @Test func aNonNumberPlacementRefuses() async throws {
        let cases: [Plane] = [
            Plane(origin: .zero, normal: .zero, xAxis: .unitX),
            Plane(origin: .zero, normal: .unitZ, xAxis: .unitZ),
            Plane(origin: Vector3(.nan, 0, 0), normal: .unitZ, xAxis: .unitX),
        ]
        for plane in cases {
            let (h, node, images) = embedded(Self.stl(Self.tetra), ["placement": .plane(plane)])
            #expect(try await h.run([node], images: images).error(node) == "“placement” has no direction.", "\(plane)")
        }
    }

    @Test func anOutOfRangeUnitRefuses() async throws {
        let (h, node, images) = embedded(Self.stl(Self.tetra), ["units": .integer(9)])
        #expect(try await h.run([node], images: images).error(node) == "“units” must be From file, mm, cm, m or in.")
    }

    @Test func theNodeIsAMeshSourceWithAFileControl() {
        #expect(ImportMeshNode.category == .mesh && ImportMeshNode.outputs.map(\.type) == [.mesh])
        #expect(ImportMeshNode.typeID == "creator.importMesh" && ImportMeshNode.displayName == "Import Mesh")
        #expect(ImportMeshNode.readsMeshQuality == false)
        #expect(ImportUnits.options == ["From file", "mm", "cm", "m", "in"])
        #expect(ImportMeshNode.inspector.first?.controls == [.meshFile(NodeSetting.meshFile)])
        #expect(BuiltInNodes.registry[ImportMeshNode.typeID] != nil)
    }
}

final class ReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
