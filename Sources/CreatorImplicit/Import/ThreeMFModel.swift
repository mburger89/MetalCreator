import CreatorGraph

/// What a 3MF's model part holds, flat: every object's vertices, triangles and components in a few arrays, indexed by ranges, so a
/// file of millions of triangles is a handful of allocations (mesh import spec, Reading). Objects are numbered in file order;
/// `ThreeMFModelParser` makes one.
struct ThreeMFModel {
    struct Object {
        var id = 0
        var vertexStart = 0
        var vertexCount = 0
        /// In triangles (three indices each) into `triangles`.
        var triangleStart = 0
        var triangleCount = 0
        var componentStart = 0
        var componentCount = 0
        var hasMesh = false
    }

    struct Component {
        /// An index into `objects` once `resolve()` has run; the file's ID before.
        var object: Int
        /// An index into `transforms`, or -1 for none.
        var transform: Int
    }

    /// Millimetres per file unit.
    var unit = 1.0
    var objects: [Object] = []
    var vertices: [SIMD3<Float>] = []
    /// Vertex indices local to the object, three per triangle.
    var triangles: [UInt32] = []
    var components: [Component] = []
    var transforms: [ThreeMFTransform] = []
    var items: [Component] = []
    /// Whether the file held colours, materials, textures, slices or beam lattices, all of which are dropped.
    var ignoredExtras = false
    var objectIndex: [Int: Int] = [:]

    /// Replaces the IDs in components and build items with indices, refusing one that names no object.
    mutating func resolve() throws {
        for index in components.indices { components[index].object = try lookup(components[index].object) }
        for index in items.indices { items[index].object = try lookup(items[index].object) }
    }

    private func lookup(_ id: Int) throws -> Int {
        guard let index = objectIndex[id] else {
            throw MeshImportProblem.malformedModel("it refers to object \(id), which it doesn't have.")
        }
        return index
    }
}
