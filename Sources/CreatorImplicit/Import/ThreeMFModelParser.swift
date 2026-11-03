import CreatorGraph
import Foundation

/// Reads a `.model` part into a `ThreeMFModel` with `XMLScanner` (mesh import spec, Reading). Namespaces are resolved here, by the
/// declarations in force at each element: the prefix is whatever the file chose, and an element or attribute is the core's, the
/// Production extension's and so on by its namespace URI alone. Elements of a namespace this reader does not know are skipped with
/// their children; colours, materials, slices and beam lattices set `ignoredExtras`; a Production `path` (a part in another file) is
/// refused. Vertices and triangles, which are most of the file, are read without allocating. The pieces are in
/// `ThreeMFModelParser+Namespaces` and `ThreeMFModelParser+Elements`.
struct ThreeMFModelParser {
    static let cancellationInterval = 1 << 16

    var scanner: XMLScanner
    let limits: ThreeMFLimits
    let isCancelled: () -> Bool
    var model = ThreeMFModel()
    var declarations: [Declaration] = []
    var contexts: [Context] = []
    var sawModel = false
    var current = -1
    var highestIndex: UInt32 = 0
    var events = 0
    /// Attribute bytes walked since the last ask about cancellation: one element may hold megabytes of them.
    var attributeBytes = 0
    /// Objects, components and build items kept so far, against `limits.records`.
    var records = 0

    private init(scanner: XMLScanner, limits: ThreeMFLimits, isCancelled: @escaping () -> Bool) {
        self.scanner = scanner
        self.limits = limits
        self.isCancelled = isCancelled
    }

    /// The model in `bytes`. `isCancelled` is asked every 65,536 elements.
    static func parse(_ bytes: UnsafeRawBufferPointer, limits: ThreeMFLimits, isCancelled: @escaping () -> Bool) throws -> ThreeMFModel {
        if looksLikeUTF16(bytes) { throw MeshImportProblem.malformedModel("it is UTF-16 text, which isn't supported.") }
        var parser = ThreeMFModelParser(scanner: XMLScanner(bytes: bytes), limits: limits, isCancelled: isCancelled)
        try parser.run()
        try parser.model.resolve()
        return parser.model
    }

    private static func looksLikeUTF16(_ bytes: UnsafeRawBufferPointer) -> Bool {
        guard bytes.count >= 2 else { return false }
        return (bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF) || bytes[0] == 0 || bytes[1] == 0
    }

    static func damaged(_ reason: String) -> MeshImportProblem { .malformedModel(reason) }

    /// Counts one more object, component or build item against the budget.
    mutating func keepRecord() throws {
        guard records < limits.records else { throw Self.damaged("it has more objects and parts than this app opens.") }
        records += 1
    }

    /// Counts an attribute against the walk since cancellation was last asked, and asks again every `cancellationInterval` bytes, so one
    /// element with megabytes of attributes can still be stopped.
    mutating func meter(_ attribute: XMLScanner.Attribute) throws {
        attributeBytes &+= attribute.value.upperBound - attribute.name.lowerBound + 1
        if attributeBytes >= Self.cancellationInterval {
            attributeBytes = 0
            if isCancelled() { throw CancellationError() }
        }
    }

    private mutating func run() throws {
        while let event = try scanner.next() {
            if events % Self.cancellationInterval == 0, isCancelled() { throw CancellationError() }
            events += 1
            switch event {
            case .start(let tag): try start(tag)
            case .end: try end()
            }
        }
        guard sawModel else { throw Self.damaged("it isn't a 3MF model.") }
    }

    private mutating func start(_ tag: XMLScanner.Tag) throws {
        guard let parent = contexts.last else {
            try startModel(tag)
            return
        }
        guard parent != .skipped else {
            contexts.append(.skipped)
            return
        }
        try declare(tag, at: contexts.count + 1)
        let (space, local) = split(tag.name)
        switch space {
        case .core:
            contexts.append(try childContext(local, tag: tag, in: parent))
        case .materials, .beamLattice, .slice:
            model.ignoredExtras = true
            contexts.append(.skipped)
        case .secureContent:
            throw MeshImportProblem.encrypted
        case .production, .unknown:
            contexts.append(.skipped)
        }
    }

    private mutating func end() throws {
        guard let closed = contexts.popLast() else { return }
        while let last = declarations.last, last.level > contexts.count { declarations.removeLast() }
        switch closed {
        case .object: finishObject()
        case .mesh: try finishMesh()
        default: break
        }
    }

    // MARK: The model element

    private mutating func startModel(_ tag: XMLScanner.Tag) throws {
        guard !sawModel else { throw Self.damaged("it has more than one model.") }
        try declare(tag, at: 1)
        let (space, local) = split(tag.name)
        guard space == .core, scanner.equals(local, "model") else { throw Self.damaged("it isn't a 3MF model.") }
        sawModel = true
        contexts.append(.model)
        var sawUnit = false, sawRequired = false
        for attribute in scanner.attributes(of: tag) {
            try meter(attribute)
            if scanner.equals(attribute.name, "unit") {
                guard !sawUnit else { throw Self.damaged("the model has two units.") }
                sawUnit = true
                model.unit = try unit(attribute.value)
            } else if scanner.equals(attribute.name, "requiredextensions") {
                guard !sawRequired else { throw Self.damaged("the model lists its required extensions twice.") }
                sawRequired = true
                try requireExtensions(attribute.value)
            }
        }
    }

    private func unit(_ value: Range<Int>) throws -> Double {
        let table: [(StaticString, Double)] = [
            ("micron", 0.001), ("millimeter", 1), ("centimeter", 10), ("inch", 25.4), ("foot", 304.8), ("meter", 1000),
        ]
        for (name, millimetres) in table where scanner.equals(value, name) { return millimetres }
        throw Self.damaged("its unit isn't micron, millimeter, centimeter, inch, foot or meter.")
    }

    /// `requiredextensions` lists prefixes declared on the model; the core specification says a consumer that does not support one
    /// must not open the file. The Production and Materials extensions are supported (the first as far as it can be: a part in
    /// another file is refused where it is used; the second by ignoring what it adds). The words are read one at a time and there
    /// are at most `ThreeMFLimits.extensions` of them.
    private func requireExtensions(_ value: Range<Int>) throws {
        var listed = 0
        for prefix in words(in: value) {
            listed += 1
            guard listed <= ThreeMFLimits.extensions else { throw Self.damaged("it requires more extensions than any file lists.") }
            guard let declaration = declarations.last(where: { scanner.equal($0.prefix, prefix) }) else {
                throw MeshImportProblem.unsupportedExtension(scanner.quoted(prefix))
            }
            switch declaration.namespace {
            case .core, .production, .materials: continue
            case .secureContent: throw MeshImportProblem.encrypted
            case .beamLattice, .slice, .unknown: throw MeshImportProblem.unsupportedExtension(scanner.quoted(declaration.uri))
            }
        }
    }

    /// A lazy sequence of the ranges of the white-space separated words in a range.
    struct Words: Sequence, IteratorProtocol {
        let bytes: UnsafeRawBufferPointer
        var index: Int
        let end: Int

        mutating func next() -> Range<Int>? {
            while index < end, XMLScanner.separates(bytes[index]) { index += 1 }
            let start = index
            while index < end, !XMLScanner.separates(bytes[index]) { index += 1 }
            return index > start ? start..<index : nil
        }
    }

    func words(in value: Range<Int>) -> Words { Words(bytes: scanner.bytes, index: value.lowerBound, end: value.upperBound) }
}
