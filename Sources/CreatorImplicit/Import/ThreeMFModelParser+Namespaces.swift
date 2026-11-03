import CreatorGraph

/// The parser's namespaces: what a prefix stands for at an element, by the `xmlns` declarations above it.
extension ThreeMFModelParser {
    enum Namespace {
        case core, production, materials, beamLattice, slice, secureContent, unknown
    }

    struct Declaration {
        var level: Int
        var prefix: Range<Int>
        var namespace: Namespace
        var uri: Range<Int>
    }

    enum Context {
        case model, resources, object, mesh, vertices, triangles, components, build, skipped
    }

    func namespace(of uri: Range<Int>) -> Namespace {
        guard scanner.hasPrefix(uri, "http://schemas.microsoft.com/3dmanufacturing/") else { return .unknown }
        let known: [(StaticString, Namespace)] = [
            ("/core/", .core), ("/production/", .production), ("/material/", .materials), ("/beamlattice/", .beamLattice),
            ("/slice/", .slice), ("/securecontent/", .secureContent),
        ]
        return known.first { scanner.contains(uri, $0.0) }?.1 ?? .unknown
    }

    /// Records the `xmlns` and `xmlns:prefix` attributes of `tag` as in force from its level down.
    /// A prefix declared again at the same level replaces the first; at most `ThreeMFLimits.declarations` are in force at once.
    mutating func declare(_ tag: XMLScanner.Tag, at level: Int) throws {
        guard scanner.contains(tag.attributes, "xmlns") else { return }
        for attribute in scanner.attributes(of: tag) where scanner.hasPrefix(attribute.name, "xmlns") {
            let name = attribute.name
            let prefix: Range<Int>
            if name.count == 5 {
                prefix = name.lowerBound..<name.lowerBound
            } else if scanner.hasPrefix(name, "xmlns:") {
                prefix = (name.lowerBound + 6)..<name.upperBound
            } else {
                continue
            }
            let declaration = Declaration(level: level, prefix: prefix, namespace: namespace(of: attribute.value), uri: attribute.value)
            if let same = declarations.lastIndex(where: { $0.level == level && scanner.equal($0.prefix, prefix) }) {
                declarations[same] = declaration
            } else {
                guard declarations.count < ThreeMFLimits.declarations else {
                    throw Self.damaged("it declares more namespaces than any file does.")
                }
                declarations.append(declaration)
            }
        }
    }

    /// The namespace a name's prefix stands for; an unprefixed name is the default namespace, and with none declared the core's.
    func namespace(prefix: Range<Int>) -> Namespace {
        for declaration in declarations.reversed() where scanner.equal(declaration.prefix, prefix) { return declaration.namespace }
        return prefix.isEmpty ? .core : .unknown
    }

    /// A name split into its namespace and local name.
    func split(_ name: Range<Int>) -> (namespace: Namespace, local: Range<Int>) {
        guard let colon = colon(in: name) else { return (namespace(prefix: name.lowerBound..<name.lowerBound), name) }
        return (namespace(prefix: name.lowerBound..<colon), (colon + 1)..<name.upperBound)
    }

    private func colon(in name: Range<Int>) -> Int? {
        name.first { scanner.bytes[$0] == UInt8(ascii: ":") }
    }

    /// An attribute with a prefix: the Production extension's `path` points at another file; the other extensions' are dropped.
    mutating func prefixedAttribute(_ attribute: XMLScanner.Attribute) throws {
        guard let colon = colon(in: attribute.name) else { return }
        let prefix = attribute.name.lowerBound..<colon
        if scanner.equals(prefix, "xmlns") || scanner.equals(prefix, "xml") { return }
        let local = (colon + 1)..<attribute.name.upperBound
        switch namespace(prefix: prefix) {
        case .production: if scanner.equals(local, "path") { throw MeshImportProblem.otherFiles }
        case .materials, .beamLattice, .slice: model.ignoredExtras = true
        default: break
        }
    }
}
