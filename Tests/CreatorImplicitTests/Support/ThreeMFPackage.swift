import CreatorImplicit
import Foundation

/// Hand-written 3MF packages for the reader's tests: the XML is built as text and stored in a zip with `ZipReaderForeignTests.build`.
enum ThreeMFPackage {
    static let core = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"
    static let production = "http://schemas.microsoft.com/3dmanufacturing/production/2015/06"
    static let materials = "http://schemas.microsoft.com/3dmanufacturing/material/2015/02"
    static let beamLattice = "http://schemas.microsoft.com/3dmanufacturing/beamlattice/2017/02"
    static let slice = "http://schemas.microsoft.com/3dmanufacturing/slice/2015/07"
    static let modelType = "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"

    /// An `<object>` holding `mesh`, its vertices and triangles written out with `prefix` on every element.
    static func object(id: Int, mesh: TriangleMesh, prefix: String = "", attributes: String = "") -> String {
        var vertices = ""
        for p in mesh.positions { vertices += "<\(prefix)vertex x=\"\(p.x)\" y=\"\(p.y)\" z=\"\(p.z)\"/>" }
        var triangles = ""
        for base in stride(from: 0, to: mesh.triangles.count, by: 3) {
            let (a, b, c) = (mesh.triangles[base], mesh.triangles[base + 1], mesh.triangles[base + 2])
            triangles += "<\(prefix)triangle v1=\"\(a)\" v2=\"\(b)\" v3=\"\(c)\"/>"
        }
        return "<\(prefix)object id=\"\(id)\" \(attributes)><\(prefix)mesh><\(prefix)vertices>\(vertices)</\(prefix)vertices>"
            + "<\(prefix)triangles>\(triangles)</\(prefix)triangles></\(prefix)mesh></\(prefix)object>"
    }

    /// An object that places `parts` (object ID and optional transform) as components.
    static func assembly(id: Int, _ parts: [(Int, String?)]) -> String {
        let components = parts.map { part in
            "<component objectid=\"\(part.0)\"" + (part.1.map { " transform=\"\($0)\"" } ?? "") + "/>"
        }.joined()
        return "<object id=\"\(id)\"><components>\(components)</components></object>"
    }

    static func item(_ id: Int, _ transform: String? = nil) -> String {
        "<item objectid=\"\(id)\"" + (transform.map { " transform=\"\($0)\"" } ?? "") + "/>"
    }

    /// A whole `.model` document.
    static func model(resources: String, build: String, unit: String? = "millimeter", attributes: String = "",
                      namespaces: String = "xmlns=\"\(core)\"") -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<model " + (unit.map { "unit=\"\($0)\" " } ?? "") + "\(namespaces) \(attributes)>"
            + "<resources>\(resources)</resources><build>\(build)</build></model>"
    }

    static func relationships(target: String = "/3D/3dmodel.model", type: String = modelType) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Target=\"\(target)\" Id=\"rel0\" Type=\"\(type)\"/></Relationships>"
    }

    /// The zip: `[Content_Types].xml` is not read, so it is left out; `relationships` may be `nil` to leave `_rels/.rels` out.
    static func zip(model: String, entry: String = "3D/3dmodel.model", relationships: String? = relationships(),
                    flags: UInt16 = 0) -> Data {
        zip(modelBytes: Data(model.utf8), entry: entry, relationships: relationships, flags: flags)
    }

    static func zip(modelBytes: Data, entry: String = "3D/3dmodel.model", relationships: String? = relationships(),
                    flags: UInt16 = 0) -> Data {
        var items: [ZipReaderForeignTests.Item] = []
        if let relationships { items.append(.init(name: "_rels/.rels", body: Data(relationships.utf8))) }
        items.append(.init(name: entry, body: modelBytes, flags: flags))
        return ZipReaderForeignTests.build(items, zip64: false)
    }

    /// A package of one model with the usual relationship.
    static func package(resources: String, build: String, unit: String? = "millimeter", attributes: String = "",
                        namespaces: String = "xmlns=\"\(core)\"") -> Data {
        zip(model: model(resources: resources, build: build, unit: unit, attributes: attributes, namespaces: namespaces))
    }
}
