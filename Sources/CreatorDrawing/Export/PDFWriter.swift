import CreatorGeometry
import Foundation

/// A written PDF and the typed texts its lettering had to replace with "?" (plan R13).
public struct PDFOutput: Sendable {
    public var data: Data
    public var replacedTexts: [String]

    public init(data: Data, replacedTexts: [String]) {
        self.data = data
        self.replacedTexts = replacedTexts
    }
}

/// Writes sheet pictures as a PDF 1.7 file, one page per picture, true size (plan R23). The bytes depend on nothing but
/// the pictures and the title: no dates, no `/ID`, no platform formatter.
public enum PDFWriter {
    private static let pointsPerMillimetre = 72.0 / 25.4
    private static let contentScale = "2.834645669"

    public static func write(_ pages: [SheetPicture], title: String) -> PDFOutput {
        let style = DrawingStyle.iso
        var objects: [[UInt8]] = []
        let kids = (0..<pages.count).map { "\(5 + 2 * $0) 0 R" }.joined(separator: " ")
        objects.append(Array("<< /Type /Catalog /Pages 2 0 R >>".utf8))
        objects.append(Array("<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>".utf8))
        objects.append(Array("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>".utf8))
        objects.append(Array("<< /Producer (MetalCreator) /Title \(titleString(title)) >>".utf8))
        for (index, page) in pages.enumerated() {
            let width = PDFNumber.format(page.size.x * pointsPerMillimetre, decimals: 4)
            let height = PDFNumber.format(page.size.y * pointsPerMillimetre, decimals: 4)
            objects.append(
                Array(
                    ("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(width) \(height)] "
                        + "/Resources << /Font << /F1 3 0 R >> >> /Contents \(6 + 2 * index) 0 R >>").utf8))
            let content = Array(contentStream(for: page, style: style).utf8)
            var stream = Array("<< /Length \(content.count) >>\nstream\n".utf8)
            stream += content
            stream += Array("\nendstream".utf8)
            objects.append(stream)
        }

        var bytes: [UInt8] = Array("%PDF-1.7\n%".utf8) + [0xE2, 0xE3, 0xCF, 0xD3, 0x0A]
        var offsets: [Int] = []
        for (index, body) in objects.enumerated() {
            offsets.append(bytes.count)
            bytes += Array("\(index + 1) 0 obj\n".utf8)
            bytes += body
            bytes += Array("\nendobj\n".utf8)
        }
        let xrefStart = bytes.count
        var xref = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            let digits = String(offset)
            xref += String(repeating: "0", count: 10 - digits.count) + digits + " 00000 n \n"
        }
        xref += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R /Info 4 0 R >>\nstartxref\n\(xrefStart)\n%%EOF\n"
        bytes += Array(xref.utf8)
        return PDFOutput(data: Data(bytes), replacedTexts: ReplacedTexts.collect(pages.flatMap(\.texts)))
    }

    // MARK: Content

    private static func n(_ value: Double) -> String { PDFNumber.format(value, decimals: 4) }

    private static func contentStream(for page: SheetPicture, style: DrawingStyle) -> String {
        var out = "\(contentScale) 0 0 \(contentScale) 0 0 cm\n0 J 1 j 0 G 0 g\n"
        for stroke in page.strokes where !stroke.segments.isEmpty {
            out += "\(n(stroke.width)) w\n"
            switch stroke.pattern {
            case .solid: out += "[] 0 d\n"
            case .hidden: out += "[\(n(style.hiddenDash)) \(n(style.hiddenGap))] 0 d\n"
            }
            out += path(of: stroke.segments)
            out += "S\n"
        }
        for text in page.texts where !text.run.bytes.isEmpty {
            let em = text.height / Double(HelveticaMetrics.capHeight) * 1000
            out += "BT /F1 \(n(em)) Tf \(n(text.origin.x)) \(n(text.origin.y)) Td (\(escaped(text.run.bytes))) Tj ET\n"
        }
        return out
    }

    private static func path(of segments: [SheetSegment]) -> String {
        var out = ""
        var current: Vector2?
        func connect(to start: Vector2) {
            if let current, abs(current.x - start.x) < 1e-9, abs(current.y - start.y) < 1e-9 { return }
            out += "\(n(start.x)) \(n(start.y)) m\n"
        }
        for segment in segments {
            switch segment {
            case let .line(a, b):
                connect(to: a)
                out += "\(n(b.x)) \(n(b.y)) l\n"
                current = b
            case let .polyline(points):
                guard let first = points.first else { continue }
                connect(to: first)
                for point in points.dropFirst() { out += "\(n(point.x)) \(n(point.y)) l\n" }
                current = points.last
            case .arc, .ellipse:
                let pieces = segment.cubics()
                guard let first = pieces.first else { continue }
                connect(to: first.start)
                for piece in pieces {
                    out += "\(n(piece.control1.x)) \(n(piece.control1.y)) \(n(piece.control2.x)) \(n(piece.control2.y)) "
                    out += "\(n(piece.end.x)) \(n(piece.end.y)) c\n"
                }
                current = pieces.last?.end
            }
        }
        return out
    }

    private static func escaped(_ bytes: [UInt8]) -> String {
        var out = ""
        for byte in bytes {
            switch byte {
            case UInt8(ascii: "("): out += "\\("
            case UInt8(ascii: ")"): out += "\\)"
            case UInt8(ascii: "\\"): out += "\\\\"
            case 32...126: out.unicodeScalars.append(Unicode.Scalar(byte))
            default:
                let octal = String(byte, radix: 8)
                out += "\\" + String(repeating: "0", count: 3 - octal.count) + octal
            }
        }
        return out
    }

    /// The title as a PDF text string: literal when ASCII, else UTF-16BE with a byte order mark in hex.
    private static func titleString(_ title: String) -> String {
        if title.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 }) {
            return "(" + escaped(Array(title.utf8)) + ")"
        }
        var hex = "FEFF"
        for unit in title.utf16 {
            let digits = String(unit, radix: 16, uppercase: true)
            hex += String(repeating: "0", count: 4 - digits.count) + digits
        }
        return "<" + hex + ">"
    }
}
