import Foundation

/// One element of an SVG: its name, attributes (in written order) and text.
struct SVGElement {
    var name: String
    var attributes: [(name: String, value: String)]
    var text = ""

    func attribute(_ key: String) -> String? { attributes.first { $0.name == key }?.value }
}

/// A small reader for the writer's own SVG: every element in document order with its attributes, and the `<g id>` order.
/// It decodes the five XML entities in attribute values and text. Tests only.
struct SVGStructureReader {
    private(set) var elements: [SVGElement] = []

    init(data: Data) throws {
        let text = String(bytes: data, encoding: .utf8) ?? ""
        var index = text.startIndex
        while let open = text[index...].firstIndex(of: "<") {
            guard let close = text[open...].firstIndex(of: ">") else { throw SVGReaderError.unterminated }
            let body = String(text[text.index(after: open)..<close])
            index = text.index(after: close)
            if body.hasPrefix("?") || body.hasPrefix("/") { continue }
            let selfClosing = body.hasSuffix("/")
            var element = try Self.parse(selfClosing ? String(body.dropLast()) : body)
            if !selfClosing, let end = text[index...].range(of: "</\(element.name)>"), !text[index..<end.lowerBound].contains("<") {
                element.text = Self.unescaped(String(text[index..<end.lowerBound]))
            }
            elements.append(element)
        }
    }

    var groupIDs: [String] { elements.filter { $0.name == "g" }.compactMap { $0.attribute("id") } }

    func elements(named name: String) -> [SVGElement] { elements.filter { $0.name == name } }

    private static func parse(_ body: String) throws -> SVGElement {
        var scanner = body[...]
        let name = String(scanner.prefix { $0 != " " })
        scanner = scanner.dropFirst(name.count)
        var attributes: [(String, String)] = []
        while let equals = scanner.firstIndex(of: "=") {
            let key = String(scanner[..<equals]).trimmingCharacters(in: .whitespaces)
            let afterEquals = scanner.index(after: equals)
            guard afterEquals < scanner.endIndex, scanner[afterEquals] == "\"" else { throw SVGReaderError.badAttribute }
            let valueStart = scanner.index(after: afterEquals)
            guard let valueEnd = scanner[valueStart...].firstIndex(of: "\"") else { throw SVGReaderError.badAttribute }
            attributes.append((key, unescaped(String(scanner[valueStart..<valueEnd]))))
            scanner = scanner[scanner.index(after: valueEnd)...]
        }
        return SVGElement(name: name, attributes: attributes)
    }

    private static func unescaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
    }
}

enum SVGReaderError: Error {
    case unterminated
    case badAttribute
}
