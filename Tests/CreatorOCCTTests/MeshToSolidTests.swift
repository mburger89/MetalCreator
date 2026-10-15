import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorOCCT

/// Mesh to Solid on OpenCascade (implicit spec §4.7, §7): valid, the mesh's volume, STEP-exportable, faces tagged by the operation.
struct MeshToSolidTests {
    let kernel = OCCTKernel()

    func solid(_ mesh: MeshSolidFixtures.Mesh, tag: NodeTag = newTag()) async throws -> Solid {
        try await kernel.meshToSolid(positions: mesh.positions, triangles: mesh.triangles, tag: tag)
    }

    func isValid(_ solid: Solid) async throws -> Bool {
        let shape = try await kernel.shape(of: solid)
        return OCCTKernel.serialized { shape.isValid }
    }

    @Test func aCubeOfTwelveTrianglesIsASolidOfSixFaces() async throws {
        let cube = MeshSolidFixtures.cube(size: 10)
        let made = try await solid(cube)
        let valid = try await isValid(made)
        #expect(made.topology.faces.count == 6, "the coplanar triangles are merged")
        #expect(valid)
        let properties = try await kernel.properties(of: made)
        #expect(abs(properties.volume - 1000) < 1e-6 && abs(properties.surfaceArea - 600) < 1e-6)
        #expect(abs(made.bounds.size.x - 10) < 1e-9 && abs(made.bounds.max.z - 10) < 1e-9)
    }

    @Test func aSphereKeepsEveryFacetAndTheMeshsVolume() async throws {
        let sphere = MeshSolidFixtures.sphere(radius: 5, subdivisions: 3)
        let made = try await solid(sphere)
        let valid = try await isValid(made)
        #expect(made.topology.faces.count == 512 && valid)
        let volume = try await kernel.properties(of: made).volume
        let expected = MeshSolidFixtures.volume(sphere)
        #expect(abs(volume - expected) / expected < 1e-6, "\(volume) against \(expected)")
    }

    @Test func aMeshWithACavityIsASolidWithAVoid() async throws {
        let cavity = MeshSolidFixtures.cube(size: 6, at: SIMD3(2, 2, 2), inside: true)
        let part = MeshSolidFixtures.joined(MeshSolidFixtures.cube(size: 10), cavity)
        let made = try await solid(part)
        let (valid, volume) = (try await isValid(made), try await kernel.properties(of: made).volume)
        #expect(made.topology.faces.count == 12 && valid)
        #expect(abs(volume - (1000 - 216)) < 1e-6)
    }

    @Test func twoSeparateCubesAreTwoSolids() async throws {
        let pair = MeshSolidFixtures.joined(MeshSolidFixtures.cube(size: 10), MeshSolidFixtures.cube(size: 4, at: SIMD3(20, 0, 0)))
        let made = try await solid(pair)
        let (valid, volume) = (try await isValid(made), try await kernel.properties(of: made).volume)
        #expect(made.topology.faces.count == 12 && valid)
        #expect(abs(volume - (1000 + 64)) < 1e-6)
    }

    @Test func everyFaceCarriesTheOperationsTag() async throws {
        let tag = newTag(item: 3)
        let made = try await solid(MeshSolidFixtures.cube(size: 10), tag: tag)
        #expect(made.topology.faces.allSatisfy { face in face.tags.contains { $0.node == tag.node && $0.item == 3 } })
        // A face is told from the others by its normal, as any solid's is.
        let top = made.topology.faces.filter { ($0.normal ?? .zero).dot(.unitZ) > 0.99 }
        #expect(top.count == 1)
    }

    @Test func theSolidExportsAsStepAndReadsBack() async throws {
        let made = try await solid(MeshSolidFixtures.sphere(radius: 5, subdivisions: 2))
        let url = URL.temporaryDirectory.appending(path: "mesh-to-solid-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: url) }
        try await kernel.export([made], format: .step, to: url)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        #expect(size > 1_000)
        let back = try OCCTKernel.serialized { try OCCTShape.readSTEP(url) }
        let expected = try await kernel.properties(of: made).volume
        let readBack = OCCTKernel.serialized { back.volume }
        #expect(abs(readBack - expected) / expected < 1e-6)
    }

    @Test func aMeshThatIsNotClosedSaysSo() async throws {
        var open = MeshSolidFixtures.cube(size: 10)
        open.triangles.removeLast(3)
        let error = await #expect(throws: KernelError.self) { try await solid(open) }
        #expect(error?.userMessage.contains("not closed") == true, "\(String(describing: error))")
    }

    @Test func aMeshWoundInsideOutSaysSo() async throws {
        let error = await #expect(throws: KernelError.self) { try await solid(MeshSolidFixtures.cube(size: 10, inside: true)) }
        #expect(error?.userMessage.contains("inside out") == true, "\(String(describing: error))")
    }

    @Test func tooFewTrianglesAndBadIndicesAreRefused() async {
        await #expect(throws: KernelError.invalidInput("A mesh needs at least four triangles to make a solid.")) {
            try await kernel.meshToSolid(positions: [.zero], triangles: [0, 0, 0], tag: newTag())
        }
        let broken = MeshSolidFixtures.Mesh(positions: MeshSolidFixtures.cube(size: 1).positions,
                                            triangles: MeshSolidFixtures.cube(size: 1).triangles.dropLast() + [99])
        let error = await #expect(throws: KernelError.self) { try await solid(broken) }
        #expect(error?.userMessage.contains("names a vertex it does not have") == true)
    }
}
