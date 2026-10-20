import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A 3MF model read back with Foundation's XML parser, for the tests of the writer: the unit and each object's name, vertices and
/// triangles.
final class ThreeMFReading: NSObject, XMLParserDelegate {
    struct Object {
        var id = 0
        var name = ""
        var vertices: [SIMD3<Double>] = []
        var triangles: [[Int]] = []
    }

    private(set) var unit = ""
    private(set) var objects: [Object] = []
    private(set) var buildItems: [Int] = []
    private(set) var rootNamespace = ""

    /// Parses `data`; `nil` when it is not well-formed XML.
    static func read(_ data: Data) -> ThreeMFReading? {
        let reading = ThreeMFReading()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = reading
        return parser.parse() ? reading : nil
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        switch name {
        case "model":
            unit = attributes["unit"] ?? ""
            rootNamespace = attributes["xmlns"] ?? ""
        case "object":
            objects.append(Object(id: Int(attributes["id"] ?? "") ?? 0, name: attributes["name"] ?? ""))
        case "vertex":
            let value = { (key: String) in Double(attributes[key] ?? "") ?? .nan }
            objects[objects.count - 1].vertices.append(SIMD3(value("x"), value("y"), value("z")))
        case "triangle":
            objects[objects.count - 1].triangles.append(["v1", "v2", "v3"].map { Int(attributes[$0] ?? "") ?? -1 })
        case "item":
            buildItems.append(Int(attributes["objectid"] ?? "") ?? 0)
        default:
            break
        }
    }
}
