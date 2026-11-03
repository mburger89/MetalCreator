import CreatorGraph

/// The one budget for what the model parser keeps or walks (mesh import spec, Limits): a file of 2 GB of XML may say anything, so each
/// thing it can make us hold or visit has a cap here, and a refusal comes before the allocation or the loop that would pass it.
struct ThreeMFLimits {
    /// Triangles stored, and after instancing.
    var triangles = MeshImportLimits.maxTriangles
    /// Objects, components and build items together (each keeps a record, and each component or item may keep a transform).
    var records = 250_000
    /// Parts in other files of the package that the root model may name.
    var parts = 4_096
    /// Inflated model bytes over the root and every part together.
    var modelBytes = ZipReader.defaultLimit
    /// Vertices stored: a mesh may share its vertices, but not by more than this many to a triangle.
    var vertices: Int

    init(triangles: Int = MeshImportLimits.maxTriangles, records: Int = 250_000, parts: Int = 4_096,
         modelBytes: Int = ZipReader.defaultLimit) {
        self.triangles = triangles
        self.records = records
        self.parts = parts
        self.modelBytes = modelBytes
        vertices = 3 * triangles
    }

    /// What is left of the budget once `model` is kept: the limits for the next part.
    func remaining(after model: ThreeMFModel) -> ThreeMFLimits {
        var left = self
        left.triangles = max(0, triangles - model.triangles.count / 3)
        left.vertices = max(0, vertices - model.vertices.count)
        left.records = max(0, records - model.recordCount)
        return left
    }

    /// The `xmlns` declarations in force at once (the lookup for every element scans them).
    static let declarations = 256
    /// The words `requiredextensions` may list.
    static let extensions = 64
    /// The numbers in a transform.
    static let transformNumbers = 12
}

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
        var hasComponents = false
        /// A support structure (type support, solidsupport or other): never part of the part.
        var leftOut = false
    }

    struct Component {
        /// An index into `objects` once `resolve()` has run; the file's ID before.
        var object: Int
        /// An index into `transforms`, or -1 for none.
        var transform: Int
        /// An index into `paths` when the root model names a part in another file, else -1 (this model's own object).
        var path = -1
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
    /// The distinct part names the root's components and build items give in `path`, in first-seen order.
    var paths: [String] = []
    /// Objects, components and build items kept, against `ThreeMFLimits.records`.
    var recordCount = 0

    /// Replaces the IDs in components and build items with indices, refusing one that names no object. Those that name a part in
    /// another file wait for `resolvePaths(_:)`; a part's build items are not valid (Production extension) and are left alone.
    mutating func resolve(items resolvesItems: Bool = true) throws {
        for index in components.indices where components[index].path < 0 {
            components[index].object = try Self.lookup(components[index].object, in: objectIndex)
        }
        guard resolvesItems else { return }
        for index in items.indices where items[index].path < 0 {
            items[index].object = try Self.lookup(items[index].object, in: objectIndex)
        }
    }

    /// Resolves the references that name a part: `targets[i]` maps an object ID to its index for the part `paths[i]` names.
    mutating func resolvePaths(_ targets: [[Int: Int]]) throws {
        for index in components.indices where components[index].path >= 0 {
            components[index].object = try Self.lookup(components[index].object, in: targets[components[index].path])
        }
        for index in items.indices where items[index].path >= 0 {
            items[index].object = try Self.lookup(items[index].object, in: targets[items[index].path])
        }
    }

    /// Appends a part's objects, vertices, triangles and components after this model's, as they were in the part. Returns the part's
    /// object IDs mapped to their indices here. Its build items and path list are not kept.
    mutating func append(part: ThreeMFModel) -> [Int: Int] {
        let objectBase = objects.count, vertexBase = vertices.count, triangleBase = triangles.count / 3
        let componentBase = components.count, transformBase = transforms.count
        for var object in part.objects {
            object.vertexStart += vertexBase
            object.triangleStart += triangleBase
            object.componentStart += componentBase
            objects.append(object)
        }
        vertices.append(contentsOf: part.vertices)
        triangles.append(contentsOf: part.triangles)
        for var component in part.components {
            component.object += objectBase
            if component.transform >= 0 { component.transform += transformBase }
            components.append(component)
        }
        transforms.append(contentsOf: part.transforms)
        ignoredExtras = ignoredExtras || part.ignoredExtras
        recordCount += part.recordCount
        return part.objectIndex.mapValues { $0 + objectBase }
    }

    private static func lookup(_ id: Int, in objectIndex: [Int: Int]) throws -> Int {
        guard let index = objectIndex[id] else {
            throw MeshImportProblem.malformedModel("it refers to object \(id), which it doesn't have.")
        }
        return index
    }
}
