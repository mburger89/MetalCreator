import Foundation
import Testing
@testable import CreatorImplicit

/// The streamed STL (implicit spec Errata D12) is the STL the in-memory writer makes.
struct STLFileWriterTests {
    func temporary() -> URL {
        URL.temporaryDirectory.appending(path: "stream-\(UUID().uuidString).stl")
    }

    @Test func windowsInAnyNumberMakeTheBytesOfTheWholeMesh() throws {
        let sphere = MeshFixtures.sphereMesh(radius: 5, subdivisions: 3)
        var whole = STLWriter()
        whole.add(sphere)
        let url = temporary()
        defer { try? FileManager.default.removeItem(at: url) }
        var writer = try STLFileWriter(destination: url)
        try writer.beginObject(name: "ignored")
        // The mesh in three pieces, each with the vertices it needs.
        let cuts = [0, 100, 300, sphere.triangleCount]
        for (start, end) in zip(cuts, cuts.dropFirst()) {
            let part = Array(sphere.triangles[(3 * start)..<(3 * end)])
            try writer.add(MeshWindow(positions: sphere.positions, triangles: part, startingAt: 0))
        }
        try writer.endObject()
        try writer.finish()
        #expect(try Data(contentsOf: url) == whole.data())
        #expect(writer.triangleCount == sphere.triangleCount)
    }

    @Test func aCancelledFileIsNotLeftBehind() throws {
        let url = temporary()
        var writer = try STLFileWriter(destination: url)
        try writer.add(MeshWindow(positions: MeshFixtures.cube.positions, triangles: MeshFixtures.cube.triangles, startingAt: 0))
        writer.cancel()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func anExistingFileIsReplaced() throws {
        let url = temporary()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("old".utf8).write(to: url)
        var writer = try STLFileWriter(destination: url)
        try writer.add(MeshWindow(positions: MeshFixtures.cube.positions, triangles: MeshFixtures.cube.triangles, startingAt: 0))
        try writer.finish()
        #expect(try Data(contentsOf: url).count == 84 + 50 * 12)
    }
}
