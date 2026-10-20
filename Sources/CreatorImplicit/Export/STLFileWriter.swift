import Foundation

/// Binary STL written to a file as triangles arrive (implicit spec Errata D12), the same bytes `STLWriter` makes for the same
/// triangles: the 80-byte header, the count (patched in when the file is finished), then 50 bytes a triangle. It writes to a temporary
/// beside the destination and moves it into place in `finish()`.
public struct STLFileWriter: MeshSink {
    private let destination: URL
    private let partial: URL
    private var handle: FileHandle?
    private var buffer: [UInt8] = []
    public private(set) var triangleCount = 0
    public let vertexCount = 0

    public init(destination: URL) throws {
        self.destination = destination
        partial = destination.deletingLastPathComponent().appending(path: ".\(UUID().uuidString).partial")
        guard FileManager.default.createFile(atPath: partial.path, contents: nil) else {
            throw ZipError.writeFailed("the folder can't be written to.")
        }
        handle = try FileHandle(forWritingTo: partial)
        buffer = STLWriter.header + [0, 0, 0, 0]
    }

    public mutating func beginObject(name: String) throws {}

    public mutating func endObject() throws {}

    public mutating func add(_ window: MeshWindow) throws {
        buffer.reserveCapacity(buffer.count + 50 * window.triangleCount)
        for base in stride(from: 0, to: window.triangles.count - 2, by: 3) {
            let (a, b, c) = (window.positions[Int(window.triangles[base])], window.positions[Int(window.triangles[base + 1])],
                             window.positions[Int(window.triangles[base + 2])])
            let (u, v) = (b - a, c - a)
            let cross = SIMD3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
            let length = (cross * cross).sum().squareRoot()
            let normal = length > 0 ? cross / length : SIMD3<Float>.zero
            for vector in [normal, a, b, c] {
                for component in [vector.x, vector.y, vector.z] {
                    buffer += ZipWriter.u32(component.bitPattern)
                }
            }
            buffer += [0, 0]
            triangleCount += 1
        }
        if buffer.count >= 1 << 20 { try flush() }
    }

    public mutating func finish() throws {
        try flush()
        guard triangleCount <= Int(UInt32.max) else { throw ZipError.writeFailed("an STL file holds at most 4,294,967,295 triangles.") }
        do {
            try handle?.seek(toOffset: 80)
            try handle?.write(contentsOf: ZipWriter.u32(UInt32(triangleCount)))
            try handle?.close()
        } catch {
            throw ZipError.writeFailed(error.localizedDescription)
        }
        handle = nil
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
        try manager.moveItem(at: partial, to: destination)
    }

    public mutating func cancel() {
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: partial)
    }

    private mutating func flush() throws {
        guard !buffer.isEmpty else { return }
        do {
            try handle?.write(contentsOf: buffer)
        } catch {
            throw ZipError.writeFailed(error.localizedDescription)
        }
        buffer.removeAll(keepingCapacity: true)
    }
}
