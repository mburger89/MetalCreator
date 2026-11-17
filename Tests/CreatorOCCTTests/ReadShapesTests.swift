#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorOCCT

/// NS-1 Task 8: `readShapes` sorts a model file into solids, sheets and curves.
struct ReadShapesTests {
    private func box(_ kernel: OCCTKernel) async throws -> Solid {
        let square = Profile2D(plane: .xy, segments: [
            .line(Vector2(0, 0), Vector2(10, 0)), .line(Vector2(10, 0), Vector2(10, 6)),
            .line(Vector2(10, 6), Vector2(0, 6)), .line(Vector2(0, 6), Vector2(0, 0)),
        ])
        return try await kernel.extrude(square, distance: 4, mode: .oneSided, tag: newTag())
    }

    /// A 10 x 10 mm square sheet in the plane z = 20, built from a closed wire.
    private func sheet(_ kernel: OCCTKernel) async throws -> Solid {
        let corners = [Vector3(0, 0, 20), Vector3(10, 0, 20), Vector3(10, 10, 20), Vector3(0, 10, 20)]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: newTag())
        return try await kernel.planarSurface([loop], tag: newTag())
    }

    /// A 30 mm open wire of two lines, away from the others.
    private func wire(_ kernel: OCCTKernel) async throws -> Curve {
        let points = [Vector3(40, 0, 0), Vector3(55, 0, 0), Vector3(55, 15, 0)]
        return try await kernel.makeCurve([.line(points[0], points[1]), .line(points[1], points[2])], tag: newTag())
    }

    private enum Fixture { case step(unit: String), iges(unit: String) }

    /// The bytes of a file holding `shapes`, written by OpenCascade itself.
    private func file(_ shapes: [OCCTShape], as fixture: Fixture) throws -> Data {
        let directory = URL.temporaryDirectory.appending(path: "read-shapes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "model")
        try OCCTKernel.serialized { () throws in
            let whole = shapes.count == 1 ? shapes[0] : try OCCTShape.compound(shapes)
            switch fixture {
            case .step(let unit): try whole.writeSTEP(to: url, unit: unit)
            case .iges(let unit): try whole.writeIGES(to: url, unit: unit)
            }
        }
        return try Data(contentsOf: url)
    }

    @Test func aBoxIsASolid() async throws {
        let kernel = OCCTKernel()
        let data = try file([try await kernel.shape(of: try await box(kernel))], as: .step(unit: "MM"))
        let tag = newTag()
        let read = try await kernel.readShapes(data, format: .step, tag: tag)
        #expect(read.solids.count == 1 && read.sheets.isEmpty && read.curves.isEmpty)
        #expect(read.fileUnitMillimetres == 1)
        let solid = try #require(read.solids.first)
        #expect(solid.topology.faces.count == 6)
        for (index, face) in solid.topology.faces.enumerated() {
            #expect(face.tags == [TopoTag(tag, .imported(face: index))])
        }
        #expect(try await kernel.properties(of: solid).volume.isApproximatelyEqual(to: 240, relativeTolerance: 1e-6))
    }

    @Test func aSheetIsASheetWithNamedBoundaryEdges() async throws {
        let kernel = OCCTKernel()
        let data = try file([try await kernel.shape(of: try await sheet(kernel))], as: .step(unit: "MM"))
        let tag = newTag()
        let read = try await kernel.readShapes(data, format: .step, tag: tag)
        #expect(read.solids.isEmpty && read.curves.isEmpty)
        let sheet = try #require(read.sheets.first)
        #expect(read.sheets.count == 1 && sheet.topology.faces.count == 1)
        let boundary = sheet.topology.edges.enumerated().filter { $0.element.isBoundary }
        #expect(boundary.count == 4)
        for (index, edge) in boundary {
            #expect(edge.tags == [TopoTag(tag, .boundary(.imported(edge: index)))])
        }
        #expect(sheet.bounds.min.z.isApproximatelyEqual(to: 20, absoluteTolerance: 1e-6))
    }

    @Test func aWireIsACurve() async throws {
        let kernel = OCCTKernel()
        let data = try file([try await kernel.curveShape(of: try await wire(kernel)),
        ], as: .step(unit: "MM"))
        let read = try await kernel.readShapes(data, format: .step, tag: newTag())
        #expect(read.solids.isEmpty && read.sheets.isEmpty)
        let length = read.curves.reduce(0) { $0 + $1.length }
        #expect(length.isApproximatelyEqual(to: 30, relativeTolerance: 1e-6))
    }

    @Test func oneFileWithAllThreeSortsEachIntoItsList() async throws {
        let kernel = OCCTKernel()
        let shapes = [
            try await kernel.shape(of: try await box(kernel)), try await kernel.shape(of: try await sheet(kernel)),
            try await kernel.curveShape(of: try await wire(kernel)),
        ]
        let data = try file(shapes, as: .step(unit: "MM"))
        let read = try await kernel.readShapes(data, format: .step, tag: newTag())
        #expect(read.solids.count == 1)
        #expect(read.sheets.count == 1)
        #expect(read.curves.reduce(0) { $0 + $1.length }.isApproximatelyEqual(to: 30, relativeTolerance: 1e-6))
        #expect(read.solids[0].topology.faces.count == 6)
        #expect(read.sheets[0].topology.faces.count == 1)
    }

    @Test func anIgesSheetReadsASheet() async throws {
        let kernel = OCCTKernel()
        let data = try file([try await kernel.shape(of: try await sheet(kernel))], as: .iges(unit: "MM"))
        let read = try await kernel.readShapes(data, format: .iges, tag: newTag())
        #expect(read.solids.isEmpty)
        #expect(read.sheets.count == 1)
        #expect(read.sheets[0].topology.edges.contains { $0.isBoundary })
        #expect(read.fileUnitMillimetres == 1)
    }

    @Test func aStepWrittenInInchesReportsItsUnit() async throws {
        let kernel = OCCTKernel()
        let data = try file([try await kernel.shape(of: try await box(kernel))], as: .step(unit: "INCH"))
        let read = try await kernel.readShapes(data, format: .step, tag: newTag())
        #expect(read.fileUnitMillimetres == 25.4)
        // The reader converts to millimetres, so the box keeps its size.
        #expect(try #require(read.solids.first).bounds.max.x.isApproximatelyEqual(to: 10, absoluteTolerance: 1e-6))
    }

    @Test func anIgesWrittenInInchesReportsItsUnit() async throws {
        let kernel = OCCTKernel()
        let data = try file([try await kernel.shape(of: try await box(kernel))], as: .iges(unit: "IN"))
        let read = try await kernel.readShapes(data, format: .iges, tag: newTag())
        #expect(read.fileUnitMillimetres.isApproximatelyEqual(to: 25.4, relativeTolerance: 1e-9))
        // OpenCascade writes a solid to IGES as its faces, which read back as six sheets; the reader converts to millimetres.
        #expect(read.solids.isEmpty && read.sheets.count == 6)
        #expect(read.sheets.map(\.bounds.max.x).max()?.isApproximatelyEqual(to: 10, absoluteTolerance: 1e-6) == true)
    }

    @Test func refusesGarbageInTheShimsWords() async throws {
        let kernel = OCCTKernel()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52])
        await #expect(throws: KernelError.invalidInput("The STEP model couldn't be read.")) {
            try await kernel.readShapes(png, format: .step, tag: newTag())
        }
        await #expect(throws: KernelError.invalidInput("The IGES model couldn't be read.")) {
            try await kernel.readShapes(png, format: .iges, tag: newTag())
        }
        await #expect(throws: KernelError.invalidInput("The STEP model couldn't be read.")) {
            try await kernel.readShapes(Data(), format: .step, tag: newTag())
        }
    }

    @Test func scalingACurveScalesItsLength() async throws {
        let kernel = OCCTKernel()
        let curve = try await wire(kernel)
        let scaled = try await kernel.scaled(curve, by: 2, tag: newTag())
        #expect(scaled.length.isApproximatelyEqual(to: 60, relativeTolerance: 1e-9))
        await #expect(throws: KernelError.invalidInput("The scale must be greater than 0.")) {
            try await kernel.scaled(curve, by: 0, tag: newTag())
        }
    }

    @Test func scalingASheetKeepsItsBoundaryNames() async throws {
        let kernel = OCCTKernel()
        let data = try file([try await kernel.shape(of: try await sheet(kernel))], as: .step(unit: "MM"))
        let read = try await kernel.readShapes(data, format: .step, tag: newTag())
        let scaled = try await kernel.scaled(read.sheets[0], by: Vector3(2, 2, 2), tag: newTag())
        #expect(scaled.topology.edges.map(\.tags) == read.sheets[0].topology.edges.map(\.tags))
    }
}

private extension Double {
    func isApproximatelyEqual(to other: Double, relativeTolerance: Double = 0, absoluteTolerance: Double = 0) -> Bool {
        abs(self - other) <= max(relativeTolerance * abs(other), absoluteTolerance)
    }
}
#endif
