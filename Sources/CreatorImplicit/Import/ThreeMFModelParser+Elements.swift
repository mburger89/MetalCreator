import CreatorGraph

/// The parser's elements below `model`: which context each opens, and the objects, meshes, vertices, triangles, components and build
/// items themselves.
extension ThreeMFModelParser {
    /// The context a core element opens inside `parent`, after reading what it holds.
    mutating func childContext(_ local: Range<Int>, tag: XMLScanner.Tag, in parent: Context) throws -> Context {
        switch parent {
        case .model: return scanner.equals(local, "resources") ? .resources : scanner.equals(local, "build") ? .build : .skipped
        case .resources: return try inResources(local, tag)
        case .object: return try inObject(local)
        case .mesh: return scanner.equals(local, "vertices") ? .vertices : scanner.equals(local, "triangles") ? .triangles : .skipped
        case .vertices, .triangles, .components, .build:
            try leaf(local, tag: tag, in: parent)
            return .skipped
        case .skipped: return .skipped
        }
    }

    /// An element with nothing under it that is read: a vertex, triangle, component or build item.
    private mutating func leaf(_ local: Range<Int>, tag: XMLScanner.Tag, in parent: Context) throws {
        switch parent {
        case .vertices: if scanner.equals(local, "vertex") { try vertex(tag) }
        case .triangles: if scanner.equals(local, "triangle") { try triangle(tag) }
        case .components: if scanner.equals(local, "component") { try component(tag) }
        case .build: if scanner.equals(local, "item") { try item(tag) }
        default: break
        }
    }

    private mutating func inResources(_ local: Range<Int>, _ tag: XMLScanner.Tag) throws -> Context {
        if scanner.equals(local, "object") {
            try startObject(tag)
            return .object
        }
        // Base materials are a core element; textures and colour groups belong to the Materials extension.
        if scanner.equals(local, "basematerials") { model.ignoredExtras = true }
        return .skipped
    }

    private mutating func inObject(_ local: Range<Int>) throws -> Context {
        if scanner.equals(local, "mesh") {
            guard !model.objects[current].hasMesh else { throw Self.damaged("an object has two meshes.") }
            model.objects[current].hasMesh = true
            highestIndex = 0
            return .mesh
        }
        return scanner.equals(local, "components") ? .components : .skipped
    }

    // MARK: Objects and meshes

    private mutating func startObject(_ tag: XMLScanner.Tag) throws {
        var object = ThreeMFModel.Object()
        var sawID = false
        for attribute in scanner.attributes(of: tag) {
            if scanner.equals(attribute.name, "id") {
                guard let id = scanner.integer(attribute.value) else { throw Self.damaged("an object's id isn't a whole number.") }
                object.id = id
                sawID = true
            } else if scanner.equals(attribute.name, "pid") || scanner.equals(attribute.name, "pindex") {
                model.ignoredExtras = true
            } else {
                try prefixedAttribute(attribute)
            }
        }
        guard sawID else { throw Self.damaged("an object has no id.") }
        guard model.objectIndex[object.id] == nil else { throw Self.damaged("two objects have the id \(object.id).") }
        object.vertexStart = model.vertices.count
        object.triangleStart = model.triangles.count / 3
        object.componentStart = model.components.count
        current = model.objects.count
        model.objectIndex[object.id] = current
        model.objects.append(object)
    }

    mutating func finishMesh() throws {
        let object = model.objects[current]
        let vertexCount = model.vertices.count - object.vertexStart
        let triangleCount = model.triangles.count / 3 - object.triangleStart
        if triangleCount > 0, Int(highestIndex) >= vertexCount {
            throw Self.damaged("a triangle refers to a vertex the object doesn't have.")
        }
        model.objects[current].vertexCount = vertexCount
        model.objects[current].triangleCount = triangleCount
    }

    mutating func finishObject() {
        model.objects[current].componentCount = model.components.count - model.objects[current].componentStart
    }

    private mutating func vertex(_ tag: XMLScanner.Tag) throws {
        var point = SIMD3<Float>.zero
        var seen = 0
        for attribute in scanner.attributes(of: tag) where attribute.name.count == 1 {
            let slot: Int
            switch scanner.bytes[attribute.name.lowerBound] {
            case UInt8(ascii: "x"): slot = 0
            case UInt8(ascii: "y"): slot = 1
            case UInt8(ascii: "z"): slot = 2
            default: continue
            }
            guard let value = scanner.float(attribute.value) else {
                throw Self.damaged("a vertex has a coordinate that isn't a finite number.")
            }
            point[slot] = value
            seen |= 1 << slot
        }
        guard seen == 0b111 else { throw Self.damaged("a vertex is missing a coordinate.") }
        guard model.vertices.count < 3 * triangleLimit else { throw Self.damaged("it has more vertices than a mesh this app opens.") }
        model.vertices.append(point)
    }

    private mutating func triangle(_ tag: XMLScanner.Tag) throws {
        var corners: [UInt32] = [0, 0, 0, 0]
        var seen = 0
        for attribute in scanner.attributes(of: tag) {
            let name = attribute.name
            let first = scanner.bytes[name.lowerBound]
            if name.count == 2, first == UInt8(ascii: "v"), let which = vertexSlot(scanner.bytes[name.lowerBound + 1]) {
                guard let index = scanner.integer(attribute.value), index <= Int(UInt32.max) else {
                    throw Self.damaged("a triangle has a vertex number that isn't a whole number.")
                }
                corners[which] = UInt32(index)
                seen |= 1 << which
            } else if (name.count == 2 && first == UInt8(ascii: "p")) || scanner.equals(name, "pid") {
                model.ignoredExtras = true
            } else {
                try prefixedAttribute(attribute)
            }
        }
        guard seen == 0b1110 else { throw Self.damaged("a triangle is missing a vertex.") }
        highestIndex = max(highestIndex, corners[1], corners[2], corners[3])
        let stored = model.triangles.count / 3
        guard stored < triangleLimit else { throw MeshImportProblem.tooManyTriangles(stored + 1) }
        model.triangles.append(contentsOf: corners[1...3])
    }

    /// 1, 2 or 3 for the digit of `v1`, `v2` and `v3`.
    private func vertexSlot(_ digit: UInt8) -> Int? {
        digit >= UInt8(ascii: "1") && digit <= UInt8(ascii: "3") ? Int(digit - UInt8(ascii: "0")) : nil
    }

    // MARK: Components and build items

    private mutating func component(_ tag: XMLScanner.Tag) throws {
        guard model.components.count < Self.maximumComponents else { throw Self.damaged("it has more components than this app opens.") }
        let (id, transform) = try reference(tag, "a component")
        model.components.append(ThreeMFModel.Component(object: id, transform: transform))
    }

    private mutating func item(_ tag: XMLScanner.Tag) throws {
        guard model.items.count < Self.maximumComponents else { throw Self.damaged("it has more build items than this app opens.") }
        let (id, transform) = try reference(tag, "a build item")
        model.items.append(ThreeMFModel.Component(object: id, transform: transform))
    }

    /// The `objectid` and `transform` of a component or build item.
    private mutating func reference(_ tag: XMLScanner.Tag, _ what: String) throws -> (id: Int, transform: Int) {
        var id: Int?
        var transform = -1
        for attribute in scanner.attributes(of: tag) {
            if scanner.equals(attribute.name, "objectid") {
                guard let value = scanner.integer(attribute.value) else { throw Self.damaged("\(what)'s objectid isn't a whole number.") }
                id = value
            } else if scanner.equals(attribute.name, "transform") {
                model.transforms.append(try parseTransform(attribute.value))
                transform = model.transforms.count - 1
            } else {
                try prefixedAttribute(attribute)
            }
        }
        guard let id else { throw Self.damaged("\(what) names no object.") }
        return (id, transform)
    }

    private func parseTransform(_ value: Range<Int>) throws -> ThreeMFTransform {
        let words = words(in: value)
        let numbers = words.compactMap { scanner.double($0) }
        guard words.count == 12, numbers.count == 12 else { throw Self.damaged("a transform isn't twelve finite numbers.") }
        let transform = ThreeMFTransform(numbers)
        guard transform.isInvertible else { throw Self.damaged("a transform flattens the part, or isn't a finite number.") }
        return transform
    }
}
