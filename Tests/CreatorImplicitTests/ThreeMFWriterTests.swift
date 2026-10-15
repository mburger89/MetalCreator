import CreatorGeometry
import Foundation
import Testing
@testable import CreatorImplicit

/// 3MF (implicit spec §5.3, §7): our zip, the core schema's elements, millimetres, named objects, six significant digits.
struct ThreeMFWriterTests {
    func temporary() -> URL {
        URL.temporaryDirectory.appending(path: "model-\(UUID().uuidString).3mf")
    }

    func text(_ value: Float) -> String {
        var bytes: [UInt8] = []
        ThreeMFText.append(value, to: &bytes)
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    @Test func numbersHaveSixSignificantDigitsLikeFormatStyleWritesThem() {
        let style = FloatingPointFormatStyle<Double>.number.precision(.significantDigits(1...6)).grouping(.never)
            .locale(Locale(identifier: "en_US"))
        let samples: [Float] = [
            1, -1, 0.5, 12.3456789, 123456.789, 0.000123456789, 1_234_567, -0.1, 7, 100, 0.0625, 3.14159265,
            -2718.28183, 99999.4, 1e-5, 4_000_000, 0.999999_6, 65_536.5, 33.333_333,
        ]
        for value in samples {
            #expect(text(value) == Double(value).formatted(style), "\(value)")
        }
        #expect(text(0) == "0" && text(-0.0) == "0" && text(.nan) == "0" && text(.infinity) == "0")
        #expect(text(1.5) == "1.5" && text(2) == "2" && text(-0.25) == "-0.25")
    }

    @Test func namesAreMadeSafeForXML() {
        #expect(ThreeMFText.attribute("Insole & <Co> \"x\" 'y'") == "Insole &amp; &lt;Co&gt; &quot;x&quot; &apos;y&apos;")
        #expect(ThreeMFText.attribute("a\u{0}b\u{7}c") == "abc")
        #expect(ThreeMFText.attribute("") == "Part" && ThreeMFText.attribute("   ") == "Part")
        #expect(ThreeMFText.attribute("Bracket Ünï") == "Bracket Ünï")
    }

    @Test func aFileReadsBackAsAnOPCPackageWithNamedObjectsInMillimetres() throws {
        let url = temporary()
        defer { try? FileManager.default.removeItem(at: url) }
        var writer = ThreeMFWriter(destination: url)
        let cube = MeshFixtures.cube
        try writer.beginObject(name: "Insole & <Co>")
        try writer.add(MeshWindow(positions: cube.positions, triangles: cube.triangles, startingAt: 0))
        try writer.endObject()
        let sphere = MeshFixtures.sphereMesh(radius: 5, subdivisions: 1)
        try writer.beginObject(name: "Ball")
        try writer.add(MeshWindow(positions: sphere.positions, triangles: sphere.triangles, startingAt: 0))
        try writer.endObject()
        try writer.finish()

        let zip = try ZipReader(contentsOf: url)
        #expect(zip.entries.map(\.name) == ["[Content_Types].xml", "_rels/.rels", "3D/3dmodel.model"])
        let types = String(bytes: try zip.contents(of: "[Content_Types].xml"), encoding: .utf8) ?? ""
        #expect(types.contains("application/vnd.ms-package.3dmanufacturing-3dmodel+xml") && types.contains("Extension=\"rels\""))
        let rels = String(bytes: try zip.contents(of: "_rels/.rels"), encoding: .utf8) ?? ""
        #expect(rels.contains("Target=\"/3D/3dmodel.model\"") && rels.contains("schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"))
        let model = try #require(ThreeMFReading.read(try zip.contents(of: "3D/3dmodel.model")))
        #expect(model.unit == "millimeter" && model.rootNamespace == "http://schemas.microsoft.com/3dmanufacturing/core/2015/02")
        #expect(model.objects.map(\.name) == ["Insole & <Co>", "Ball"] && model.objects.map(\.id) == [1, 2])
        #expect(model.buildItems == [1, 2])
        #expect(model.objects[0].vertices.count == 8 && model.objects[0].triangles.count == 12)
        #expect(model.objects[1].vertices.count == sphere.vertexCount && model.objects[1].triangles.count == sphere.triangleCount)
        for object in model.objects {
            let range = 0..<object.vertices.count
            #expect(object.triangles.allSatisfy { $0.allSatisfy(range.contains) }, "indices stay in the object")
        }
        #expect(model.objects[0].vertices[6] == SIMD3(1, 1, 1))
        #expect(writer.triangleCount == 12 + sphere.triangleCount)
    }

    @Test func aVertexTwoWindowsShareIsWrittenOnce() throws {
        // Two triangles sharing an edge, one per window: the second window brings one new vertex and reuses two.
        let url = temporary()
        defer { try? FileManager.default.removeItem(at: url) }
        var writer = ThreeMFWriter(destination: url)
        try writer.beginObject(name: "Strip")
        try writer.add(MeshWindow(positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)], triangles: [0, 1, 2],
                                  globalIndex: [0, 1, 2], firstNew: 0))
        try writer.add(MeshWindow(positions: [SIMD3(1, 0, 0), SIMD3(1, 1, 0), SIMD3(0, 1, 0)], triangles: [0, 1, 2],
                                  globalIndex: [1, 3, 2], firstNew: 3))
        #expect(writer.vertexCount == 4 && writer.triangleCount == 2)
        try writer.endObject()
        try writer.finish()
        let zip = try ZipReader(contentsOf: url)
        let model = try #require(ThreeMFReading.read(try zip.contents(of: "3D/3dmodel.model")))
        #expect(model.objects[0].vertices.count == 4 && model.objects[0].triangles == [[0, 1, 2], [1, 3, 2]])
    }

    @Test func theSameInputGivesTheSameBytes() throws {
        var files: [Data] = []
        for _ in 0..<2 {
            let url = temporary()
            defer { try? FileManager.default.removeItem(at: url) }
            var writer = ThreeMFWriter(destination: url)
            try writer.beginObject(name: "Cube")
            try writer.add(MeshWindow(positions: MeshFixtures.cube.positions, triangles: MeshFixtures.cube.triangles, startingAt: 0))
            try writer.endObject()
            try writer.finish()
            files.append(try Data(contentsOf: url))
        }
        #expect(files[0] == files[1])
    }

    @Test func aCancelledExportLeavesNoFileAndNoTemporaries() throws {
        let url = temporary()
        let folder = URL.temporaryDirectory.appending(path: "mc-3mf-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var writer = ThreeMFWriter(destination: url, temporaryFolder: folder)
        try writer.beginObject(name: "Half")
        try writer.add(MeshWindow(positions: MeshFixtures.cube.positions, triangles: MeshFixtures.cube.triangles, startingAt: 0))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2, "spill files exist while open")
        writer.cancel()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func anObjectOutOfOrderIsAnErrorNotACrash() throws {
        var writer = ThreeMFWriter(destination: temporary())
        #expect(throws: ZipError.misuse("no object is open")) { try writer.add(MeshWindow(positions: [], triangles: [], startingAt: 0)) }
        #expect(throws: ZipError.misuse("no object is open")) { try writer.endObject() }
        try writer.beginObject(name: "x")
        #expect(throws: ZipError.misuse("the last object is still open")) { try writer.beginObject(name: "y") }
        writer.cancel()
    }
}
