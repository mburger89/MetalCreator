/// `MarchingCubesTable` as one flat array of 32-bit words, the buffer a GPU engine reads (implicit spec Errata D13), so the GPU meshes
/// with the very table the CPU does. The layout is part of the shader's source (`ImplicitMeshShaderLibrary`):
///
/// - words 0 ... 256: `starts`, where pattern `p`'s edges are `edges[starts[p] ..< starts[p + 1]]` (three edges a triangle);
/// - words 257 ... 268: the lower corner of each of the twelve edges, then 269 ... 280 the upper corner;
/// - words 281 on: `edges`, every pattern's triangles one after the other.
enum MarchingCubesBuffers {
    static let patternCount = 256
    static let startsOffset = 0
    static let lowerCornersOffset = patternCount + 1
    static let upperCornersOffset = lowerCornersOffset + 12
    static let edgesOffset = upperCornersOffset + 12

    static let words: [UInt32] = {
        var starts: [UInt32] = []
        var edges: [UInt32] = []
        for pattern in MarchingCubesTable.triangles {
            starts.append(UInt32(edges.count))
            edges += pattern.map(UInt32.init)
        }
        starts.append(UInt32(edges.count))
        return starts + MarchingCubesTable.edgeCorners.map { UInt32($0.0) } + MarchingCubesTable.edgeCorners.map { UInt32($0.1) } + edges
    }()
}
