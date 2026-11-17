import CreatorGraph

/// Reads the elements of an X3D document into `X3DNode`s with `XMLScanner`. Elements that make no geometry (appearances, metadata,
/// the head) are skipped whole; geometry the reader does not make stays as a leaf so the result can say it skipped something.
struct X3DBuilder {
    static let maximumElements = 4_000_000

    /// Elements whose children are read.
    private static let containers: Set<String> = [
        "X3D", "Scene", "Transform", "Group", "StaticGroup", "Collision", "Billboard", "Anchor", "Switch", "LOD", "Shape",
        "IndexedFaceSet", "IndexedTriangleSet",
    ]
    /// Elements kept as leaves.
    private static let leaves: Set<String> = ["Coordinate", "CoordinateDouble", "Box"]

    var scanner: XMLScanner
    let isCancelled: () -> Bool
    private var work = 0

    init(scanner: XMLScanner, isCancelled: @escaping () -> Bool) {
        self.scanner = scanner
        self.isCancelled = isCancelled
    }

    private struct State {
        var stack: [(node: X3DNode, def: String?)] = []
        var defined: [String: X3DNode] = [:]
        var root: X3DNode?
        var skipping = 0
        var elements = 0
    }

    /// The `X3D` element and everything under it that is read.
    mutating func build() throws -> X3DNode {
        var state = State()
        while let event = try scanner.next() {
            try tick()
            switch event {
            case .end:
                if state.skipping > 0 {
                    state.skipping -= 1
                } else if let done = state.stack.popLast(), let name = done.def {
                    state.defined[name] = done.node
                }
            case .start(let tag):
                if state.skipping > 0 {
                    state.skipping += 1
                } else {
                    try start(tag, &state)
                }
            }
        }
        guard let root = state.root else { throw X3DReader.notX3D }
        return root
    }

    private func isKept(_ type: String) -> Bool {
        Self.containers.contains(type) || Self.leaves.contains(type) || Self.isUnread(type)
    }

    private mutating func start(_ tag: XMLScanner.Tag, _ state: inout State) throws {
        state.elements += 1
        guard state.elements <= Self.maximumElements else { throw X3DReader.tooComplex }
        let type = localName(tag.name)
        if state.root == nil, type != "X3D" { throw X3DReader.notX3D }
        let parent = state.stack.last?.node
        guard isKept(type) else {
            // Appearance, Metadata, head: nothing here is read; a Switch still counts the place.
            if let parent, parent.type == "Switch" { parent.children.append(X3DNode(type: type)) }
            state.skipping = 1
            return
        }
        if let parent, !Self.containers.contains(parent.type) {
            state.skipping = 1
            return
        }
        let node = X3DNode(type: type)
        let (def, use) = try attributes(of: tag, into: node)
        if let use {
            guard let shared = state.defined[use], shared.type == type else { throw X3DReader.undefinedShape }
            parent?.children.append(shared)
            state.skipping = 1
            return
        }
        parent?.children.append(node)
        if state.root == nil { state.root = node }
        if Self.containers.contains(type) {
            state.stack.append((node, def))
        } else {
            if let def { state.defined[def] = node }
            state.skipping = 1
        }
    }

    static func isUnread(_ type: String) -> Bool { VRMLScene.isUnread(type) || unreadX3D.contains(type) }

    private static let unreadX3D: Set<String> = [
        "TriangleSet", "TriangleFanSet", "TriangleStripSet", "IndexedTriangleFanSet", "IndexedTriangleStripSet", "IndexedQuadSet",
        "QuadSet", "Sphere", "Cone", "Cylinder", "ElevationGrid", "Extrusion", "IndexedLineSet", "LineSet", "PointSet", "Text",
        "Inline", "NurbsPatchSurface",
    ]

    private mutating func tick() throws {
        work += 1
        if work % 65_536 == 0, isCancelled() { throw CancellationError() }
    }

    /// The element or attribute name without its `prefix:`.
    private func localName(_ range: Range<Int>) -> String {
        var start = range.lowerBound
        for index in range where scanner.bytes[index] == UInt8(ascii: ":") { start = index + 1 }
        return scanner.text(start..<range.upperBound)
    }

    /// Reads a tag's attributes into `node`; returns its `DEF` and `USE` names.
    private mutating func attributes(of tag: XMLScanner.Tag, into node: X3DNode) throws -> (def: String?, use: String?) {
        var def: String?
        var use: String?
        for attribute in scanner.attributes(of: tag) {
            let name = localName(attribute.name)
            if name == "DEF" {
                def = try scanner.decoded(attribute.value)
            } else if name == "USE" {
                use = try scanner.decoded(attribute.value)
            } else if !Self.isUnread(node.type) {
                try read(attribute, named: name, into: node)
            }
        }
        return (def, use)
    }

    private mutating func read(_ attribute: XMLScanner.Attribute, named name: String, into node: X3DNode) throws {
        if name == "ccw" {
            node.counterClockwise = !scanner.equals(attribute.value, "false")
            return
        }
        guard Self.numeric.contains(name) else { return }
        let values = try numbers(attribute.value)
        switch name {
        case "translation": node.translation = values
        case "rotation": node.rotation = values
        case "scale": node.scale = values
        case "scaleOrientation": node.scaleOrientation = values
        case "center": node.center = values
        default: store(values, named: name, into: node)
        }
    }

    private func store(_ values: [Float], named name: String, into node: X3DNode) {
        switch name {
        case "size": node.size = values
        case "point": node.point = values
        case "whichChoice": node.whichChoice = values.first ?? -1
        default: node.index = values
        }
    }

    private static let numeric: Set<String> = [
        "translation", "rotation", "scale", "scaleOrientation", "center", "size", "point", "coordIndex", "index", "whichChoice",
    ]

    /// The numbers of a list separated by white space or commas, read straight from the document's bytes.
    private mutating func numbers(_ range: Range<Int>) throws -> [Float] {
        var result: [Float] = []
        var index = range.lowerBound
        let bytes = scanner.bytes
        while index < range.upperBound {
            while index < range.upperBound, XMLScanner.isSpace(bytes[index]) || bytes[index] == UInt8(ascii: ",") { index += 1 }
            let start = index
            while index < range.upperBound, !(XMLScanner.isSpace(bytes[index]) || bytes[index] == UInt8(ascii: ",")) { index += 1 }
            guard index > start else { break }
            guard let value = scanner.float(start..<index) else { throw X3DReader.badNumber }
            result.append(value)
            try tick()
        }
        return result
    }
}
