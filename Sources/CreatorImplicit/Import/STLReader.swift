import CreatorGraph
import Foundation

/// Reads binary and ASCII STL (mesh import spec, Reading). STL is untrusted input: the size and the triangle count are checked before
/// anything is allocated, every way a file can be wrong is a `MeshImportProblem`, and nothing here can trap. The facet normal is
/// ignored (the winding says which side is out); coordinates are taken as millimetres; vertices are welded by exact position.
public enum STLReader {
    private static let cancellationInterval = 64_000
    private static let headerSize = 84
    private static let triangleSize = 50

    /// `isCancelled` is asked every 64,000 triangles; a cancelled read throws `CancellationError`.
    public static func read(_ data: Data, isCancelled: () -> Bool) throws -> ImportedMesh {
        guard data.count <= MeshImportLimits.maxFileBytes else { throw MeshImportProblem.tooLarge }
        let corners: [SIMD3<Float>]
        switch try format(of: data) {
        case .binary(let count):
            corners = try binaryCorners(data, count: count, isCancelled: isCancelled)
        case .ascii:
            corners = try asciiCorners(data, isCancelled: isCancelled)
        }
        guard !corners.isEmpty else { throw MeshImportProblem.noTriangles }
        let welded = ExactWeld.weld(corners: corners)
        guard !welded.triangles.isEmpty else { throw MeshImportProblem.noTriangles }
        let mesh = TriangleMesh(positions: welded.positions, triangles: welded.triangles)
        return ImportedMesh(mesh: mesh, droppedTriangles: welded.dropped, unit: nil, ignoredExtras: false)
    }

    private enum Format {
        case binary(count: Int)
        case ascii
    }

    private static func format(of data: Data) throws -> Format {
        let bytes = Array(data.prefix(headerSize))
        let count = bytes.count >= headerSize ? Int(le32(bytes, at: 80)) : nil
        if let count, headerSize + triangleSize * count == data.count {
            guard count <= MeshImportLimits.maxTriangles else { throw MeshImportProblem.tooManyTriangles(count) }
            return .binary(count: count)
        }
        // Text never holds a zero byte; a name or a byte order mark may hold bytes of 0x80 and up, so only a zero rules ASCII out
        // for a file that starts with "solid". Any other file needs a zero or such a byte before it is taken for a binary one.
        let hasZero = bytes.contains(0)
        if !hasZero, startsWithSolid(bytes) { return .ascii }
        let looksBinary = bytes.count >= headerSize && (hasZero || bytes.contains { $0 >= 0x80 })
        if looksBinary, let count {
            // A binary header whose count the size does not hold.
            guard count <= MeshImportLimits.maxTriangles else { throw MeshImportProblem.tooManyTriangles(count) }
            if headerSize + triangleSize * count > data.count { throw MeshImportProblem.endsEarly }
        }
        throw MeshImportProblem.notAMeshFile
    }

    private static func le32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || (byte >= 0x09 && byte <= 0x0D) }

    private static func startsWithSolid(_ bytes: [UInt8]) -> Bool {
        var index = 0
        while index < bytes.count, isSpace(bytes[index]) { index += 1 }
        // A UTF-8 byte order mark may precede the word.
        if bytes.count >= index + 3, bytes[index] == 0xEF, bytes[index + 1] == 0xBB, bytes[index + 2] == 0xBF { index += 3 }
        let word = Array("solid".utf8)
        guard bytes.count >= index + word.count, Array(bytes[index..<index + word.count]) == word else { return false }
        return bytes.count == index + word.count || isSpace(bytes[index + word.count])
    }

    // MARK: Binary

    private static func binaryCorners(_ data: Data, count: Int, isCancelled: () -> Bool) throws -> [SIMD3<Float>] {
        try data.withUnsafeBytes { raw in
            var corners: [SIMD3<Float>] = []
            corners.reserveCapacity(3 * count)
            for triangle in 0..<count {
                if triangle % cancellationInterval == 0, isCancelled() { throw CancellationError() }
                let base = headerSize + triangleSize * triangle + 12
                for corner in 0..<3 {
                    let at = base + 12 * corner
                    let point = SIMD3<Float>(
                        Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self))),
                        Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at + 4, as: UInt32.self))),
                        Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at + 8, as: UInt32.self))))
                    // A binary file has no line to name, so a NaN or infinity is the file not being a mesh.
                    guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { throw MeshImportProblem.notAMeshFile }
                    corners.append(point)
                }
            }
            return corners
        }
    }

    // MARK: ASCII

    private static func asciiCorners(_ data: Data, isCancelled: () -> Bool) throws -> [SIMD3<Float>] {
        try data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var corners: [SIMD3<Float>] = []
            var line = 1
            var index = 0
            let vertex = Array("vertex".utf8)
            while index < bytes.count {
                index = skipBlanks(bytes, from: index)
                let wordStart = index
                while index < bytes.count, !isSpace(bytes[index]) { index += 1 }
                if bytes[wordStart..<index].elementsEqual(vertex) {
                    let (point, next) = try readVertex(bytes, from: index, line: line)
                    corners.append(point)
                    index = next
                    if corners.count % 3 == 0 { try checkProgress(corners.count / 3, isCancelled: isCancelled) }
                }
                while index < bytes.count, bytes[index] != 0x0A { index += 1 }
                if index < bytes.count { index += 1; line += 1 }
            }
            guard corners.count % 3 == 0 else { throw MeshImportProblem.endsEarly }
            return corners
        }
    }

    private static func checkProgress(_ triangles: Int, isCancelled: () -> Bool) throws {
        if triangles > MeshImportLimits.maxTriangles { throw MeshImportProblem.tooManyTriangles(triangles) }
        if triangles % cancellationInterval == 0, isCancelled() { throw CancellationError() }
    }

    /// Skips spaces and tabs, stopping at a line end.
    private static func skipBlanks(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int {
        var index = start
        while index < bytes.count, bytes[index] != 0x0A, isSpace(bytes[index]) { index += 1 }
        return index
    }

    /// The three numbers after a `vertex` word, and where they end.
    private static func readVertex(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int, line: Int) throws -> (SIMD3<Float>, Int) {
        var index = start
        var point = SIMD3<Float>.zero
        for axis in 0..<3 {
            index = skipBlanks(bytes, from: index)
            let tokenStart = index
            while index < bytes.count, !isSpace(bytes[index]) { index += 1 }
            guard let value = ASCIINumber.parse(bytes, tokenStart..<index) else { throw MeshImportProblem.badNumber(line: line) }
            point[axis] = value
        }
        return (point, index)
    }
}
