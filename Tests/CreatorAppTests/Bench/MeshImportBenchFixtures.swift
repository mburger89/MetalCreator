import CreatorImplicit
import Foundation

/// The files of `MeshImportBench`: triangles by index, written to a temporary file in chunks (a 10-million-triangle STL is
/// 500 MB, so nothing here holds a whole file's worth of triangles).
enum Fixture {
    typealias Triangle = (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)

    /// A file's triangles and the format to write them in.
    enum Kind {
        case binary(Source), ascii(Source), threeMF(Source)
    }

    /// `count` triangles, each made by `triangle(i)`; `vertices` is the grid behind a height field, `nil` for a soup.
    struct Source {
        var count: Int
        var triangle: @Sendable (Int) -> Triangle
        var grid: Int?
    }

    /// A height field: a square grid of `n × n` vertices 0.1 mm apart under a smooth bump, two triangles a cell, counterclockwise from
    /// above. About `count` triangles (the grid is as large as that allows).
    static func field(_ count: Int) -> Source {
        let cells = Int((Double(count) / 2).squareRoot())
        let side = cells + 1
        @Sendable func point(_ column: Int, _ row: Int) -> SIMD3<Float> {
            let x = Float(column) * 0.1, y = Float(row) * 0.1
            return SIMD3(x, y, 5 * sin(x * 0.7) * cos(y * 0.5))
        }
        return Source(count: 2 * cells * cells, triangle: { index in
            let cell = index / 2
            let (column, row) = (cell % cells, cell / cells)
            let (a, b, c, d) = (point(column, row), point(column + 1, row), point(column + 1, row + 1), point(column, row + 1))
            return index % 2 == 0 ? (a, b, c) : (a, c, d)
        }, grid: side)
    }

    /// Triangles that share no vertex: each 1 mm triangle stands in its own 2 mm cell of a plane, so a mesh of `count` triangles has
    /// `3 × count` distinct vertices (the most a mesh may hold is 30 million) and every edge is open.
    static func soup(_ count: Int) -> Source {
        let columns = 4_096
        return Source(count: count, triangle: { index in
            let x = Float(index % columns) * 2, y = Float(index / columns) * 2
            let h = Float(index % 7) * 0.1
            return (SIMD3(x, y, 0), SIMD3(x + 1, y, h), SIMD3(x, y + 1, h + 0.05))
        }, grid: nil)
    }

    /// Writes `kind` to a fresh temporary file and returns it.
    static func write(_ kind: Kind) throws -> URL {
        switch kind {
        case .binary(let source): try writeBinary(source)
        case .ascii(let source): try writeASCII(source)
        case .threeMF(let source): try writeThreeMF(source)
        }
    }

    private static func destination(_ ext: String) -> URL {
        URL.temporaryDirectory.appending(path: "mesh-import-bench-\(UUID().uuidString).\(ext)")
    }

    private static func chunks(of source: Source, size: Int = 100_000, _ body: (Range<Int>) throws -> Void) rethrows {
        var start = 0
        while start < source.count {
            let end = min(start + size, source.count)
            try body(start..<end)
            start = end
        }
    }

    static func writeBinary(_ source: Source) throws -> URL {
        let url = destination("stl")
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var header = Data(count: 80)
        withUnsafeBytes(of: UInt32(source.count).littleEndian) { header.append(contentsOf: $0) }
        try handle.write(contentsOf: header)
        try chunks(of: source) { range in
            var data = Data(capacity: range.count * 50)
            for index in range {
                let (a, b, c) = source.triangle(index)
                var floats: [Float] = [0, 0, 0, a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z]
                floats.withUnsafeMutableBytes { data.append(contentsOf: $0) }
                data.append(contentsOf: [0, 0])
            }
            try handle.write(contentsOf: data)
        }
        return url
    }

    static func writeASCII(_ source: Source) throws -> URL {
        let url = destination("stl")
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.write(contentsOf: Data("solid bench\n".utf8))
        try chunks(of: source, size: 20_000) { range in
            var text = ""
            for index in range {
                let (a, b, c) = source.triangle(index)
                text += "facet normal 0 0 1\n outer loop\n"
                for p in [a, b, c] { text += "  vertex \(p.x) \(p.y) \(p.z)\n" }
                text += " endloop\nendfacet\n"
            }
            try handle.write(contentsOf: Data(text.utf8))
        }
        try handle.write(contentsOf: Data("endsolid bench\n".utf8))
        return url
    }

    /// A 3MF of one object: the grid's vertices once and the triangles by index (a soup has no grid, so its vertices are listed per triangle).
    static func writeThreeMF(_ source: Source) throws -> URL {
        let url = destination("3mf")
        var writer = ThreeMFWriter(destination: url)
        try writer.beginObject(name: "Bench")
        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        positions.reserveCapacity(source.count * 3)
        var lookup: [SIMD3<Float>: UInt32] = [:]
        for index in 0..<source.count {
            let (a, b, c) = source.triangle(index)
            for p in [a, b, c] {
                if let found = lookup[p] {
                    indices.append(found)
                } else {
                    let new = UInt32(positions.count)
                    lookup[p] = new
                    positions.append(p)
                    indices.append(new)
                }
            }
        }
        try writer.add(MeshWindow(positions: positions, triangles: indices, globalIndex: Array(0..<UInt32(positions.count)), firstNew: 0))
        try writer.endObject()
        try writer.finish()
        return url
    }
}
