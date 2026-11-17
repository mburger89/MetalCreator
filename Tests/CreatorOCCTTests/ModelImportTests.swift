import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorOCCT

/// Reading a STEP or IGES model from bytes, scaling it and joining several (KiCad import, KI-2 task 4).
struct ModelImportTests {
    private func lShape(_ kernel: OCCTKernel) async throws -> Solid {
        let points = [Vector2(0, 0), Vector2(20, 0), Vector2(20, 5), Vector2(5, 5), Vector2(5, 15), Vector2(0, 15)]
        let segments = points.indices.map { Segment2D.line(points[$0], points[($0 + 1) % points.count]) }
        return try await kernel.extrude(Profile2D(plane: .xy, segments: segments), distance: 3, mode: .oneSided, tag: newTag())
    }

    private func folder() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "model-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func stepBytes(of solid: Solid, _ kernel: OCCTKernel) async throws -> Data {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "part.step")
        try await kernel.export([solid], format: .step, to: url)
        return try Data(contentsOf: url)
    }

    private func igesBytes(of solid: Solid, _ kernel: OCCTKernel) async throws -> Data {
        let shape = try await kernel.shape(of: solid)
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "part.iges")
        try OCCTKernel.serialized { () throws in try shape.writeIGES(to: url) }
        return try Data(contentsOf: url)
    }

    @Test func readsStepFromBytes() async throws {
        let kernel = OCCTKernel()
        let original = try await lShape(kernel)
        let tag = newTag()
        let model = try await kernel.readModel(try await stepBytes(of: original, kernel), format: .step, tag: tag)
        #expect(model.topology.faces.count == original.topology.faces.count)
        #expect(try await kernel.properties(of: model).volume.isApproximatelyEqual(to: 20 * 5 * 3 + 5 * 10 * 3, relativeTolerance: 1e-6))
        for (index, face) in model.topology.faces.enumerated() {
            #expect(face.tags == [TopoTag(tag, .imported(face: index))])
        }
    }

    @Test func readsIgesFromBytes() async throws {
        let kernel = OCCTKernel()
        let original = try await lShape(kernel)
        let model = try await kernel.readModel(try await igesBytes(of: original, kernel), format: .iges, tag: newTag())
        #expect(model.topology.faces.count == original.topology.faces.count)
        #expect(try await kernel.properties(of: model).volume.isApproximatelyEqual(to: 20 * 5 * 3 + 5 * 10 * 3, relativeTolerance: 1e-3))
    }

    @Test func refusesGarbage() async throws {
        let kernel = OCCTKernel()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52])
        await #expect(throws: KernelError.invalidInput("The STEP model couldn't be read.")) {
            try await kernel.readModel(png, format: .step, tag: newTag())
        }
        await #expect(throws: KernelError.invalidInput("The IGES model couldn't be read.")) {
            try await kernel.readModel(png, format: .iges, tag: newTag())
        }
        await #expect(throws: KernelError.invalidInput("The STEP model couldn't be read.")) {
            try await kernel.readModel(Data(), format: .step, tag: newTag())
        }
    }

    @Test func refusesEmptyStep() async throws {
        let text = """
        ISO-10303-21;
        HEADER;
        FILE_DESCRIPTION(('empty'),'2;1');
        FILE_NAME('empty.step','2026-01-01T00:00:00',(''),(''),'','','');
        FILE_SCHEMA(('AUTOMOTIVE_DESIGN { 1 0 10303 214 1 1 1 1 }'));
        ENDSEC;
        DATA;
        ENDSEC;
        END-ISO-10303-21;

        """
        await #expect(throws: KernelError.invalidInput("The model contains no shapes.")) {
            try await OCCTKernel().readModel(Data(text.utf8), format: .step, tag: newTag())
        }
    }

    @Test func scalesUniformly() async throws {
        let kernel = OCCTKernel()
        let model = try await readL(kernel)
        let big = try await kernel.scaled(model, by: Vector3(2, 2, 2), tag: newTag())
        expectScaled(big, from: model, by: Vector3(2, 2, 2))
        #expect(try await kernel.properties(of: big).volume.isApproximatelyEqual(
            to: 8 * kernel.properties(of: model).volume, relativeTolerance: 1e-9))
        #expect(big.topology.faces.map(\.kind) == model.topology.faces.map(\.kind))
    }

    @Test func scalesUnevenly() async throws {
        let kernel = OCCTKernel()
        let model = try await readL(kernel)
        let factors = Vector3(1, 2, 3)
        let stretched = try await kernel.scaled(model, by: factors, tag: newTag())
        expectScaled(stretched, from: model, by: factors)
        #expect(try await kernel.properties(of: stretched).volume.isApproximatelyEqual(
            to: 6 * kernel.properties(of: model).volume, relativeTolerance: 1e-6))
    }

    @Test func refusesBadScale() async throws {
        let kernel = OCCTKernel()
        let model = try await readL(kernel)
        for bad in [Vector3(0, 1, 1), Vector3(1, -1, 1), Vector3(1, 1, .nan), Vector3(.infinity, 1, 1)] {
            await #expect(throws: KernelError.invalidInput("The scale must be greater than 0.")) {
                try await kernel.scaled(model, by: bad, tag: newTag())
            }
        }
    }

    @Test func compoundKeepsTags() async throws {
        let kernel = OCCTKernel()
        let first = try await readL(kernel)
        let moved = try await kernel.transform(lShape(kernel), by: Transform(translation: Vector3(100, 0, 0)), tag: newTag())
        let read = try await kernel.readModel(try await stepBytes(of: moved, kernel), format: .step, tag: newTag())
        let secondTag = NodeTag(node: NodeID(), item: 0)
        var secondTopology = read.topology
        for index in secondTopology.faces.indices {
            secondTopology.faces[index].tags = [TopoTag(secondTag, .imported(face: (1 << 32) + index))]
        }
        let second = Solid(topology: secondTopology, bounds: read.bounds, storage: read.storage)
        let both = try await kernel.compound([first, second], tag: newTag())
        #expect(both.topology.faces.suffix(second.topology.faces.count).map(\.tags) == second.topology.faces.map(\.tags))
        #expect(both.topology.faces.map(\.tags) == (first.topology.faces + second.topology.faces).map(\.tags))
        let sum = try await kernel.properties(of: first).volume + kernel.properties(of: second).volume
        #expect(try await kernel.properties(of: both).volume.isApproximatelyEqual(to: sum, relativeTolerance: 1e-9))
    }

    @Test func compoundRefusesSharedGeometry() async throws {
        let kernel = OCCTKernel()
        let model = try await readL(kernel)
        await #expect(throws: KernelError.self) { try await kernel.compound([model, model], tag: newTag()) }
    }

    @Test func readsInchIgesAsMillimetres() async throws {
        let kernel = OCCTKernel()
        let original = try await lShape(kernel)
        let shape = try await kernel.shape(of: original)
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "inch.igs")
        try OCCTKernel.serialized { () throws in try shape.writeIGES(to: url, unit: "IN") }
        let model = try await kernel.readModel(try Data(contentsOf: url), format: .iges, tag: newTag())
        #expect(model.bounds == original.bounds || (model.bounds.max - original.bounds.max).length < 1e-3)
        #expect(try await kernel.properties(of: model).volume.isApproximatelyEqual(to: 20 * 5 * 3 + 5 * 10 * 3, relativeTolerance: 1e-3))
    }

    @Test func fakeKernelRefuses() async throws {
        let fake = FakeKernel()
        let solid = try await fake.extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: 1, mode: .oneSided, tag: newTag())
        await #expect(throws: KernelError.unsupported("reading 3D models")) {
            try await fake.readModel(Data(), format: .step, tag: newTag())
        }
        await #expect(throws: KernelError.unsupported("scaling")) { try await fake.scaled(solid, by: Vector3(1, 1, 1), tag: newTag()) }
        await #expect(throws: KernelError.unsupported("compounds")) { try await fake.compound([solid], tag: newTag()) }
    }

    private func readL(_ kernel: OCCTKernel) async throws -> Solid {
        try await kernel.readModel(try await stepBytes(of: try await lShape(kernel), kernel), format: .step, tag: newTag())
    }

    /// Same tags face for face, and each face centroid the original one scaled (so the face order is kept).
    private func expectScaled(_ scaled: Solid, from original: Solid, by factors: Vector3) {
        #expect(scaled.topology.faces.count == original.topology.faces.count)
        for (new, old) in zip(scaled.topology.faces, original.topology.faces) {
            #expect(new.tags == old.tags)
            let expected = Vector3(old.centroid.x * factors.x, old.centroid.y * factors.y, old.centroid.z * factors.z)
            #expect((new.centroid - expected).length < 1e-6)
        }
    }
}

private extension Double {
    func isApproximatelyEqual(to other: Double, relativeTolerance: Double) -> Bool {
        abs(self - other) <= relativeTolerance * abs(other)
    }
}
