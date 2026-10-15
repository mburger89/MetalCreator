import Foundation

/// Writes a 3MF (implicit spec §5.3): an OPC zip with `[Content_Types].xml`, `_rels/.rels` and `3D/3dmodel.model`, unit millimetre, one
/// `<object>` per object (the Output node's name) and a `<build>` item for each. The model's XML puts every vertex before any
/// triangle, but windows arrive with both, so each object's vertices and triangles are written to two temporary files as they come
/// and joined, entry by entry, into the zip when the file is finished (`ZipWriter`, deflated where it can be). Vertices have six
/// significant digits. Memory is the size of a window.
public struct ThreeMFWriter: MeshSink {
    private struct Object {
        var name: String
        var vertices: URL
        var triangles: URL
        var vertexHandle: FileHandle
        var triangleHandle: FileHandle
    }

    private let destination: URL
    private let temporaryFolder: URL
    private var finished: [Object] = []
    private var open: Object?
    private var vertexBuffer: [UInt8] = []
    private var triangleBuffer: [UInt8] = []
    public private(set) var triangleCount = 0
    public private(set) var vertexCount = 0

    /// `temporaryFolder` holds the spill files while an object is open; tests pass their own to check nothing is left behind.
    public init(destination: URL, temporaryFolder: URL = FileManager.default.temporaryDirectory) {
        self.destination = destination
        self.temporaryFolder = temporaryFolder
    }

    public mutating func beginObject(name: String) throws {
        guard open == nil else { throw ZipError.misuse("the last object is still open") }
        let folder = temporaryFolder
        let stem = "mc-3mf-\(UUID().uuidString)"
        let (vertices, triangles) = (folder.appending(path: "\(stem).vertices"), folder.appending(path: "\(stem).triangles"))
        guard FileManager.default.createFile(atPath: vertices.path, contents: nil),
              FileManager.default.createFile(atPath: triangles.path, contents: nil) else {
            throw ZipError.writeFailed("the temporary folder can't be written to.")
        }
        open = Object(name: name, vertices: vertices, triangles: triangles, vertexHandle: try FileHandle(forWritingTo: vertices),
                      triangleHandle: try FileHandle(forWritingTo: triangles))
        vertexCount = 0
    }

    public mutating func add(_ window: MeshWindow) throws {
        guard open != nil else { throw ZipError.misuse("no object is open") }
        let first = window.firstNew
        for (local, global) in window.globalIndex.enumerated() where global >= first {
            let p = window.positions[local]
            vertexBuffer += Array("<vertex x=\"".utf8)
            ThreeMFText.append(p.x, to: &vertexBuffer)
            vertexBuffer += Array("\" y=\"".utf8)
            ThreeMFText.append(p.y, to: &vertexBuffer)
            vertexBuffer += Array("\" z=\"".utf8)
            ThreeMFText.append(p.z, to: &vertexBuffer)
            vertexBuffer += Array("\"/>\n".utf8)
            vertexCount += 1
        }
        for base in stride(from: 0, to: window.triangles.count - 2, by: 3) {
            triangleBuffer += Array("<triangle v1=\"".utf8)
            ThreeMFText.append(window.globalIndex[Int(window.triangles[base])], to: &triangleBuffer)
            triangleBuffer += Array("\" v2=\"".utf8)
            ThreeMFText.append(window.globalIndex[Int(window.triangles[base + 1])], to: &triangleBuffer)
            triangleBuffer += Array("\" v3=\"".utf8)
            ThreeMFText.append(window.globalIndex[Int(window.triangles[base + 2])], to: &triangleBuffer)
            triangleBuffer += Array("\"/>\n".utf8)
            triangleCount += 1
        }
        if vertexBuffer.count + triangleBuffer.count >= 1 << 20 { try flush() }
    }

    public mutating func endObject() throws {
        try flush()
        guard let object = open else { throw ZipError.misuse("no object is open") }
        try object.vertexHandle.close()
        try object.triangleHandle.close()
        finished.append(object)
        open = nil
    }

    public mutating func finish() throws {
        guard open == nil else { throw ZipError.misuse("the last object is still open") }
        defer { removeTemporaries() }
        var zip = try ZipWriter(destination: destination)
        do {
            try Self.write(&zip, "[Content_Types].xml", Self.contentTypes)
            try Self.write(&zip, "_rels/.rels", Self.relationships)
            try zip.beginEntry("3D/3dmodel.model")
            try zip.write(Array(Self.modelHeader.utf8))
            for (index, object) in finished.enumerated() {
                let name = ThreeMFText.attribute(object.name)
                try zip.write(Array("<object id=\"\(index + 1)\" type=\"model\" name=\"\(name)\"><mesh>\n<vertices>\n".utf8))
                try Self.copy(object.vertices, into: &zip)
                try zip.write(Array("</vertices>\n<triangles>\n".utf8))
                try Self.copy(object.triangles, into: &zip)
                try zip.write(Array("</triangles>\n</mesh></object>\n".utf8))
            }
            let items = finished.indices.map { "<item objectid=\"\($0 + 1)\"/>" }.joined()
            try zip.write(Array("</resources>\n<build>\(items)</build>\n</model>\n".utf8))
            try zip.endEntry()
            try zip.finish()
        } catch {
            zip.cancel()
            throw error
        }
    }

    public mutating func cancel() {
        if let object = open {
            try? object.vertexHandle.close()
            try? object.triangleHandle.close()
            finished.append(object)
            open = nil
        }
        removeTemporaries()
    }

    // MARK: Pieces

    private mutating func flush() throws {
        guard let object = open else { return }
        do {
            try object.vertexHandle.write(contentsOf: vertexBuffer)
            try object.triangleHandle.write(contentsOf: triangleBuffer)
        } catch {
            throw ZipError.writeFailed(error.localizedDescription)
        }
        vertexBuffer.removeAll(keepingCapacity: true)
        triangleBuffer.removeAll(keepingCapacity: true)
    }

    private mutating func removeTemporaries() {
        for object in finished {
            try? FileManager.default.removeItem(at: object.vertices)
            try? FileManager.default.removeItem(at: object.triangles)
        }
        finished = []
    }

    private static func write(_ zip: inout ZipWriter, _ name: String, _ text: String) throws {
        try zip.beginEntry(name)
        try zip.write(Array(text.utf8))
        try zip.endEntry()
    }

    /// Streams a temporary file into the open entry, a megabyte at a time.
    private static func copy(_ url: URL, into zip: inout ZipWriter) throws {
        let reader = try FileHandle(forReadingFrom: url)
        defer { try? reader.close() }
        while let chunk = try reader.read(upToCount: 1 << 20), !chunk.isEmpty { try zip.write(Array(chunk)) }
    }

    static let contentTypes = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/></Types>

        """

    static let relationships = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>\
        </Relationships>

        """

    static let modelHeader = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
        <resources>

        """
}
