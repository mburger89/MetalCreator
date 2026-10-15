/// A `MeshSink` that keeps the whole mesh in memory, up to a limit (implicit spec Errata D12): Mesh to Solid takes a stream this way.
public struct MeshCollector: MeshSink {
    /// The collector was given more triangles than its limit.
    public struct Overflow: Error, Equatable, Sendable {}

    public private(set) var positions: [SIMD3<Float>] = []
    public private(set) var triangles: [UInt32] = []
    public let limit: Int

    public init(limit: Int = .max) {
        self.limit = limit
    }

    public var triangleCount: Int { triangles.count / 3 }
    public var vertexCount: Int { positions.count }

    public mutating func beginObject(name: String) throws {}

    public mutating func add(_ window: MeshWindow) throws {
        guard triangleCount + window.triangleCount <= limit else { throw Overflow() }
        for (local, global) in window.globalIndex.enumerated() where global >= window.firstNew {
            positions.append(window.positions[local])
        }
        triangles += window.triangles.map { window.globalIndex[Int($0)] }
    }

    public mutating func endObject() throws {}

    public mutating func finish() throws {}

    public mutating func cancel() {}
}

/// A `MeshSink` that only counts.
public struct MeshCounter: MeshSink {
    public private(set) var triangleCount = 0
    public private(set) var vertexCount = 0

    public init() {}

    public mutating func beginObject(name: String) throws {}

    public mutating func add(_ window: MeshWindow) throws {
        triangleCount += window.triangleCount
        vertexCount += window.globalIndex.filter { $0 >= window.firstNew }.count
    }

    public mutating func endObject() throws {}

    public mutating func finish() throws {}

    public mutating func cancel() {}
}
