import CreatorGraph
import Foundation

/// Reads binary and ASCII STL (mesh import spec, Reading). STL is untrusted input: the size and the triangle count are checked before
/// anything is allocated, every way a file can be wrong is a `MeshImportProblem`, and nothing here can trap. The facet normal is
/// ignored (the winding says which side is out); coordinates are taken as millimetres; vertices are welded by exact position.
public enum STLReader {
    private static let cancellationInterval = 64_000
    private static let headerSize = 84
    private static let triangleSize = 50

    /// `isCancelled` is asked every 64,000 triangles of a binary file and every 64 KB of an ASCII one; a cancelled read throws
    /// `CancellationError`.
    public static func read(_ data: Data, isCancelled: () -> Bool) throws -> ImportedMesh {
        try read(data, triangleLimit: MeshImportLimits.maxTriangles, isCancelled: isCancelled)
    }

    /// `read` with the triangle limit as a parameter, so a test can reach the limit without a file of millions of triangles.
    static func read(_ data: Data, triangleLimit: Int, isCancelled: () -> Bool) throws -> ImportedMesh {
        guard data.count <= MeshImportLimits.maxFileBytes else { throw MeshImportProblem.tooLarge }
        let corners: [SIMD3<Float>]
        switch try format(of: data, triangleLimit: triangleLimit) {
        case .binary(let count):
            corners = try binaryCorners(data, count: count, isCancelled: isCancelled)
        case .ascii:
            corners = try asciiCorners(data, triangleLimit: triangleLimit, isCancelled: isCancelled)
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

    /// How a binary header's triangle count sits against the file's size.
    enum BinaryFit: Equatable {
        /// The size is exactly the header plus that many triangles.
        case exact
        /// A count within the limit that the size does not reach: a binary STL cut short.
        case endsEarly
        /// Anything else, which is not a binary STL (a count above the limit that the size cannot hold is a stray number).
        case doesNotFit
    }

    /// Judges a header's `count` against the file's `size` without allocating anything. Only an exact fit above the limit is
    /// `tooManyTriangles`: the file really holds that many.
    static func binaryFit(count: Int, size: Int, triangleLimit: Int) throws -> BinaryFit {
        let expected = headerSize + triangleSize * count
        if expected == size {
            guard count <= triangleLimit else { throw MeshImportProblem.tooManyTriangles(count) }
            return .exact
        }
        return count <= triangleLimit && expected > size ? .endsEarly : .doesNotFit
    }

    /// How much of the start of a file is looked at to take it for ASCII without a `solid` line.
    private static let sniffSize = 1_024

    private static func format(of data: Data, triangleLimit: Int) throws -> Format {
        let bytes = Array(data.prefix(sniffSize))
        // A zip (a 3MF, or anything else) is no STL however its first bytes read as a count.
        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) || bytes.starts(with: [0x50, 0x4B, 0x05, 0x06]) {
            throw MeshImportProblem.notAMeshFile
        }
        let count = bytes.count >= headerSize ? Int(le32(bytes, at: 80)) : nil
        var fit = BinaryFit.doesNotFit
        if let count {
            fit = try binaryFit(count: count, size: data.count, triangleLimit: triangleLimit)
            if fit == .exact { return .binary(count: count) }
        }
        // Text never holds a zero byte; a name or a byte order mark may hold bytes of 0x80 and up, so only a zero rules ASCII out
        // for a file that starts with "solid". A file without that line is ASCII when a `facet` or `vertex` word is near its start.
        let header = bytes.prefix(headerSize)
        if !header.contains(0), startsWithSolid(bytes) { return .ascii }
        if !bytes.contains(0), hasFacetWord(bytes) { return .ascii }
        let looksBinary = bytes.count >= headerSize && (header.contains(0) || header.contains { $0 >= 0x80 })
        if looksBinary, fit == .endsEarly { throw MeshImportProblem.endsEarly }
        throw MeshImportProblem.notAMeshFile
    }

    private static func le32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    private static func isSpace(_ byte: UInt8) -> Bool { byte == 0x20 || (byte >= 0x09 && byte <= 0x0D) }

    private static func lowered(_ byte: UInt8) -> UInt8 { byte >= 0x41 && byte <= 0x5A ? byte | 0x20 : byte }

    private static let solidWord = Array("solid".utf8)
    private static let facetWord = Array("facet".utf8)
    private static let vertexWord = Array("vertex".utf8)

    /// Whether `bytes[range]` is `word` (lower case) in any case.
    private static func isWord(_ bytes: some RandomAccessCollection<UInt8>, _ word: [UInt8]) -> Bool {
        bytes.count == word.count && zip(bytes, word).allSatisfy { lowered($0) == $1 }
    }

    private static func startsWithSolid(_ bytes: [UInt8]) -> Bool {
        var index = 0
        while index < bytes.count, isSpace(bytes[index]) { index += 1 }
        // A UTF-8 byte order mark may precede the word.
        if bytes.count >= index + 3, bytes[index] == 0xEF, bytes[index + 1] == 0xBB, bytes[index + 2] == 0xBF { index += 3 }
        let end = index + solidWord.count
        guard bytes.count >= end, isWord(bytes[index..<end], solidWord) else { return false }
        return bytes.count == end || isSpace(bytes[end])
    }

    /// Whether a `facet` or `vertex` word is among the bytes (the start of a file, so this is bounded).
    private static func hasFacetWord(_ bytes: [UInt8]) -> Bool {
        var index = 0
        while index < bytes.count {
            while index < bytes.count, isSpace(bytes[index]) { index += 1 }
            let start = index
            while index < bytes.count, !isSpace(bytes[index]) { index += 1 }
            // A word cut off by the end of the look is not judged.
            guard index < bytes.count || bytes.count < sniffSize else { return false }
            if start < index, isWord(bytes[start..<index], facetWord) || isWord(bytes[start..<index], vertexWord) { return true }
        }
        return false
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

    /// Splits ASCII text into words, counting lines. A line ends at LF, or at CR when the file has no LF at all.
    private struct Words {
        let bytes: UnsafeBufferPointer<UInt8>
        let crEndsLines: Bool
        var index = 0
        var line = 1
        var nextCheck = 64_000

        init(_ bytes: UnsafeBufferPointer<UInt8>) {
            self.bytes = bytes
            crEndsLines = bytes.baseAddress.map { memchr($0, 0x0A, bytes.count) == nil } ?? true
        }

        /// The next word's range, with `line` its line; `nil` at the end. Asks `isCancelled` every 64 KB of input.
        mutating func next(isCancelled: () -> Bool) throws -> Range<Int>? {
            while index < bytes.count, STLReader.isSpace(bytes[index]) {
                if bytes[index] == 0x0A || (crEndsLines && bytes[index] == 0x0D) { line += 1 }
                index += 1
                try checkCancellation(isCancelled)
            }
            guard index < bytes.count else { return nil }
            let start = index
            while index < bytes.count, !STLReader.isSpace(bytes[index]) { index += 1 }
            try checkCancellation(isCancelled)
            return start..<index
        }

        private mutating func checkCancellation(_ isCancelled: () -> Bool) throws {
            guard index >= nextCheck else { return }
            nextCheck = index + 64_000
            if isCancelled() { throw CancellationError() }
        }
    }

    /// Every `vertex` word starts a vertex, whatever lines the words are on; the three words after it are its numbers.
    private static func asciiCorners(_ data: Data, triangleLimit: Int, isCancelled: () -> Bool) throws -> [SIMD3<Float>] {
        try data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var words = Words(bytes)
            var corners: [SIMD3<Float>] = []
            while let word = try words.next(isCancelled: isCancelled) {
                guard isWord(bytes[word], vertexWord) else { continue }
                let keywordLine = words.line
                var point = SIMD3<Float>.zero
                for axis in 0..<3 {
                    guard let number = try words.next(isCancelled: isCancelled) else {
                        throw MeshImportProblem.badNumber(line: keywordLine)
                    }
                    guard let value = ASCIINumber.parse(bytes, number) else { throw MeshImportProblem.badNumber(line: words.line) }
                    point[axis] = value
                }
                corners.append(point)
                if corners.count % 3 == 0, corners.count / 3 > triangleLimit {
                    throw MeshImportProblem.tooManyTriangles(corners.count / 3)
                }
            }
            guard corners.count % 3 == 0 else { throw MeshImportProblem.endsEarly }
            return corners
        }
    }
}
