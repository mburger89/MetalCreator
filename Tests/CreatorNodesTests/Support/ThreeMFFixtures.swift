import CreatorImplicit
import Foundation

/// Small 3MF packages for the node's tests, written with the app's own `ZipWriter` (stored, so every platform makes the same bytes).
enum ThreeMFFixtures {
    typealias Face = (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)

    /// A package with one object per entry of `objects`, each built as an unwelded list of `faces`, in `unit`.
    ///
    /// `types` names each object's `type` (default `model`); `extra` is added to every object's attributes (`pid="1"` marks colour
    /// data the reader ignores).
    static func package(_ objects: [[Face]], unit: String = "millimeter", types: [String] = [],
                        extra: String = "") throws -> Data {
        var resources = "", build = ""
        for (index, faces) in objects.enumerated() {
            var vertices = "", triangles = ""
            for (face, base) in zip(faces, stride(from: 0, to: faces.count * 3, by: 3)) {
                for p in [face.0, face.1, face.2] { vertices += "<vertex x=\"\(p.x)\" y=\"\(p.y)\" z=\"\(p.z)\"/>" }
                triangles += "<triangle v1=\"\(base)\" v2=\"\(base + 1)\" v3=\"\(base + 2)\"/>"
            }
            let type = index < types.count ? types[index] : "model"
            resources += "<object id=\"\(index + 1)\" type=\"\(type)\" \(extra)><mesh><vertices>\(vertices)</vertices>"
                + "<triangles>\(triangles)</triangles></mesh></object>"
            build += "<item objectid=\"\(index + 1)\"/>"
        }
        let model = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<model unit=\"\(unit)\" "
            + "xmlns=\"http://schemas.microsoft.com/3dmanufacturing/core/2015/02\"><resources>\(resources)</resources>"
            + "<build>\(build)</build></model>"
        let relationships = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships "
            + "xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Target=\"/3D/3dmodel.model\" "
            + "Id=\"rel0\" Type=\"http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel\"/></Relationships>"
        let url = URL.temporaryDirectory.appending(path: "mc-fixture-\(UUID().uuidString).3mf")
        defer { try? FileManager.default.removeItem(at: url) }
        var zip = try ZipWriter(destination: url)
        for (name, text) in [("_rels/.rels", relationships), ("3D/3dmodel.model", model)] {
            try zip.beginEntry(name, method: .stored)
            try zip.write(Array(text.utf8))
            try zip.endEntry()
        }
        try zip.finish()
        return try Data(contentsOf: url)
    }
}
