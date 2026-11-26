import Foundation

/// One content-stream operator with its operand tokens (strings keep their parentheses).
/// The bytes as text (the writer's files are ASCII apart from one comment line).
func pdfText(_ bytes: some Sequence<UInt8>) -> String {
    String(bytes: Array(bytes), encoding: .isoLatin1) ?? ""
}

struct PDFOperator: Equatable {
    var name: String
    var operands: [String]
}

struct PDFPage {
    var mediaBox: [Double]
    var operators: [PDFOperator]
}

struct PDFStructureError: Error, CustomStringConvertible {
    var description: String
}

/// A minimal reader for the writer's own PDFs: it checks the header, the classic xref (20-byte entries) and the trailer,
/// and returns each page's MediaBox and content operators. Tests only.
struct PDFStructureReader {
    let bytes: [UInt8]
    private(set) var size = 0
    private(set) var root = 0
    private(set) var offsets: [Int] = []
    private(set) var xrefBytes: [UInt8] = []
    private(set) var pages: [PDFPage] = []
    private(set) var pageCount = 0

    init(data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.starts(with: Array("%PDF-1.7\n".utf8)) else { throw PDFStructureError(description: "header") }
        let text = pdfText(bytes)
        guard let startRange = text.range(of: "startxref\n", options: .backwards) else {
            throw PDFStructureError(description: "startxref")
        }
        let tail = text[startRange.upperBound...]
        guard let xrefOffset = Int(tail.prefix { $0.isNumber }) else { throw PDFStructureError(description: "xref offset") }
        let table = bytes[xrefOffset...]
        guard table.starts(with: Array("xref\n".utf8)) else { throw PDFStructureError(description: "xref keyword") }
        let afterKeyword = Array(table.dropFirst(5))
        guard let lineEnd = afterKeyword.firstIndex(of: 10) else { throw PDFStructureError(description: "xref subsection") }
        let subsection = pdfText(afterKeyword[..<lineEnd]).split(separator: " ")
        guard subsection.count == 2, subsection[0] == "0", let count = Int(subsection[1]) else {
            throw PDFStructureError(description: "xref subsection")
        }
        let entries = Array(afterKeyword[(lineEnd + 1)...])
        guard entries.count >= count * 20 else { throw PDFStructureError(description: "short xref") }
        xrefBytes = Array(entries[..<(count * 20)])
        try readEntries(count: count)
        let trailer = pdfText(entries[(count * 20)...])
        size = Self.integer(after: "/Size ", in: trailer) ?? -1
        root = Self.integer(after: "/Root ", in: trailer) ?? -1
        pageCount = Self.integer(after: "/Count ", in: objectText(2)) ?? 0
        pages = try readPages(objectCount: 4 + 2 * pageCount)
    }

    private mutating func readEntries(count: Int) throws {
    for index in 0..<count {
        let entry = Array(xrefBytes[index * 20..<(index + 1) * 20])
        guard entry[18] == 0x20, entry[19] == 0x0A else { throw PDFStructureError(description: "entry end \(index)") }
        let line = pdfText(entry[..<18])
        if index == 0 {
            guard line == "0000000000 65535 f" else { throw PDFStructureError(description: "free entry") }
            continue
        }
        guard line.hasSuffix(" 00000 n"), let offset = Int(line.prefix(10)) else {
            throw PDFStructureError(description: "entry \(index)")
        }
        guard bytes[offset...].starts(with: Array("\(index) 0 obj\n".utf8)) else {
            throw PDFStructureError(description: "offset of object \(index)")
        }
        offsets.append(offset)
    }
    }

    var objectCount: Int { offsets.count }

    func objectText(_ number: Int) -> String {
        let start = offsets[number - 1]
        let end = number < offsets.count ? offsets[number] : bytes.count
        return pdfText(bytes[start..<end])
    }

    private static func integer(after key: String, in text: String) -> Int? {
        guard let range = text.range(of: key) else { return nil }
        return Int(text[range.upperBound...].prefix { $0.isNumber })
    }

    private func readPages(objectCount: Int) throws -> [PDFPage] {
        var result: [PDFPage] = []
        var number = 5
        while number + 1 <= objectCount {
            let page = objectText(number)
            guard let open = page.range(of: "/MediaBox ["), let close = page[open.upperBound...].firstIndex(of: "]") else {
                throw PDFStructureError(description: "MediaBox")
            }
            let box = page[open.upperBound..<close].split(separator: " ").compactMap { Double($0) }
            let content = objectText(number + 1)
            guard let streamStart = content.range(of: "stream\n"), let streamEnd = content.range(of: "\nendstream") else {
                throw PDFStructureError(description: "stream")
            }
            let body = String(content[streamStart.upperBound..<streamEnd.lowerBound])
            result.append(PDFPage(mediaBox: box, operators: Self.operators(in: body)))
            number += 2
        }
        return result
    }

    static func operators(in content: String) -> [PDFOperator] {
        var result: [PDFOperator] = []
        var operands: [String] = []
        for item in tokens(in: content) {
            let isOperand = item.hasPrefix("(") || item.hasPrefix("/") || item.hasPrefix("[") || item.hasSuffix("]")
                || Double(item) != nil
            if isOperand {
                operands.append(item)
            } else {
                result.append(PDFOperator(name: item, operands: operands))
                operands = []
            }
        }
        return result
    }

    private static func tokens(in content: String) -> [String] {
        var tokens: [String] = []
        var token = ""
        var characters = content.makeIterator()
        while let character = characters.next() {
            if character == "(" {
                var string = "("
                var depth = 1
                while depth > 0, let next = characters.next() {
                    string.append(next)
                    if next == "\\", let escaped = characters.next() { string.append(escaped); continue }
                    if next == "(" { depth += 1 } else if next == ")" { depth -= 1 }
                }
                tokens.append(string)
            } else if character == " " || character == "\n" {
                if !token.isEmpty { tokens.append(token); token = "" }
            } else {
                token.append(character)
            }
        }
        if !token.isEmpty { tokens.append(token) }
        return tokens
    }
}
