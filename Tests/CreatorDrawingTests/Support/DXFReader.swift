import Foundation

/// One record of a DXF section: a group code 0 and the pairs that follow it.
struct DXFRecord {
    var type: String
    var pairs: [(code: Int, value: String)]

    func first(_ code: Int) -> String? { pairs.first { $0.code == code }?.value }
    func all(_ code: Int) -> [String] { pairs.filter { $0.code == code }.map(\.value) }
    func number(_ code: Int) -> Double? { first(code).flatMap { Double($0) } }
    var layer: String? { first(8) }
    /// The record's handle: code 5, or 105 for a DIMSTYLE.
    var handle: String? { first(5) ?? first(105) }
}

/// A test-only reader of the ASCII DXF the writer makes (plan R24): pairs, sections, the header variables, tables, the
/// objects, and the links AutoCAD needs.
struct DXFReader {
    let pairs: [(code: Int, value: String)]
    private(set) var sections: [String: [DXFRecord]] = [:]
    private(set) var header: [String: [(code: Int, value: String)]] = [:]

    init(data: Data) throws {
        let pairs = try Self.parse(data)
        self.pairs = pairs
        guard pairs.last.map({ $0.code == 0 && $0.value == "EOF" }) == true else { throw ReaderError.noEOF }
        var current: String?
        var chunk: [(code: Int, value: String)] = []
        for pair in pairs {
            if pair.code == 0 && pair.value == "SECTION" {
                current = nil
            } else if current == nil {
                if pair.code == 2 {
                    current = pair.value
                    chunk = []
                }
            } else if pair.code == 0 && pair.value == "ENDSEC" {
                if current == "HEADER" { header = Self.variables(chunk) } else { sections[current ?? ""] = Self.records(chunk) }
                current = nil
            } else {
                chunk.append(pair)
            }
        }
    }

    private static func parse(_ data: Data) throws -> [(code: Int, value: String)] {
        guard let text = String(data: data, encoding: .utf8) else { throw ReaderError.notText }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        guard lines.count % 2 == 0 else { throw ReaderError.oddLineCount }
        var pairs: [(code: Int, value: String)] = []
        var index = 0
        while index < lines.count {
            guard let code = Int(lines[index].trimmingCharacters(in: .whitespaces)) else { throw ReaderError.badCode(index) }
            pairs.append((code, lines[index + 1]))
            index += 2
        }
        return pairs
    }

    private static func variables(_ chunk: [(code: Int, value: String)]) -> [String: [(code: Int, value: String)]] {
        var result: [String: [(code: Int, value: String)]] = [:]
        var name: String?
        for pair in chunk {
            if pair.code == 9 {
                name = pair.value
                result[pair.value] = []
            } else if let name {
                result[name, default: []].append(pair)
            }
        }
        return result
    }

    private static func records(_ chunk: [(code: Int, value: String)]) -> [DXFRecord] {
        var result: [DXFRecord] = []
        for pair in chunk {
            if pair.code == 0 {
                result.append(DXFRecord(type: pair.value, pairs: []))
            } else if !result.isEmpty {
                result[result.count - 1].pairs.append(pair)
            }
        }
        return result
    }

    enum ReaderError: Error { case notText, oddLineCount, badCode(Int), noEOF }

    func records(_ section: String) -> [DXFRecord] { sections[section] ?? [] }

    // MARK: Header

    func headerValue(_ name: String, code: Int? = nil) -> String? {
        guard let values = header[name] else { return nil }
        if let code { return values.first { $0.code == code }?.value }
        return values.first?.value
    }

    var handseed: Int? { headerValue("$HANDSEED", code: 5).flatMap { Int($0, radix: 16) } }

    // MARK: Tables

    func table(_ name: String) -> [DXFRecord] {
        var inTable = false
        var result: [DXFRecord] = []
        for record in records("TABLES") {
            if record.type == "TABLE" {
                inTable = record.first(2) == name
            } else if record.type == "ENDTAB" {
                inTable = false
            } else if inTable {
                result.append(record)
            }
        }
        return result
    }

    var layers: [DXFRecord] { table("LAYER") }
    var lineTypes: [DXFRecord] { table("LTYPE") }
    func layer(_ name: String) -> DXFRecord? { layers.first { $0.first(2) == name } }
    func blockRecord(_ name: String) -> DXFRecord? { table("BLOCK_RECORD").first { $0.first(2) == name } }

    // MARK: Entities and objects

    var entities: [DXFRecord] { records("ENTITIES") }
    var objects: [DXFRecord] { records("OBJECTS") }

    func object(_ handle: String) -> DXFRecord? { objects.first { $0.handle == handle } }

    /// A dictionary's name to handle entries.
    func entries(of dictionary: DXFRecord) -> [String: String] {
        var result: [String: String] = [:]
        var name: String?
        for pair in dictionary.pairs {
            if pair.code == 3 {
                name = pair.value
            } else if pair.code == 350 || pair.code == 360, let n = name {
                result[n] = pair.value
                name = nil
            }
        }
        return result
    }

    var rootDictionary: DXFRecord? { objects.first { $0.type == "DICTIONARY" && $0.first(330) == "0" } }

    // MARK: Handles

    var allRecords: [DXFRecord] {
        ["TABLES", "BLOCKS", "ENTITIES", "OBJECTS"].flatMap { records($0) }
    }

    var handles: [String] { allRecords.compactMap(\.handle) }

    var duplicateHandles: [String] {
        var seen: Set<String> = []
        return handles.filter { !seen.insert($0).inserted }
    }

    /// Every owner or pointer (330, 340, 350, 360, 390) that names a handle nobody has; 0 means none.
    var danglingReferences: [String] {
        let known = Set(handles)
        var missing: [String] = []
        for record in allRecords {
            for pair in record.pairs where [330, 340, 350, 360, 390].contains(pair.code) {
                if pair.value != "0" && !known.contains(pair.value) { missing.append("\(record.type) \(pair.code) \(pair.value)") }
            }
        }
        return missing
    }

    /// The AutoCAD links of plan R24; each failure is one sentence.
    var objectProblems: [String] {
        var problems: [String] = []
        guard let root = rootDictionary else { return ["no root dictionary"] }
        let rootEntries = entries(of: root)
        for name in ["ACAD_GROUP", "ACAD_LAYOUT", "ACAD_MLINESTYLE", "ACAD_PLOTSETTINGS", "ACAD_PLOTSTYLENAME"]
        where rootEntries[name].flatMap({ object($0) }) == nil {
            problems.append("root lacks \(name)")
        }
        guard let layoutHandle = rootEntries["ACAD_LAYOUT"], let layouts = object(layoutHandle) else { return problems }
        let layoutEntries = entries(of: layouts)
        if Set(layoutEntries.keys) != ["Model", "Layout1"] { problems.append("ACAD_LAYOUT names \(layoutEntries.keys.sorted())") }
        for (space, layoutName) in [("*Model_Space", "Model"), ("*Paper_Space", "Layout1")] {
            guard let block = blockRecord(space), let blockHandle = block.handle else {
                problems.append("no \(space)")
                continue
            }
            guard let layoutRef = block.first(340), let layout = object(layoutRef), layout.type == "LAYOUT" else {
                problems.append("\(space) has no LAYOUT")
                continue
            }
            if layoutEntries[layoutName] != layoutRef { problems.append("\(layoutName) is not \(space)'s layout") }
            let after = layout.pairs.drop { !($0.code == 100 && $0.value == "AcDbLayout") }
            if after.first(where: { $0.code == 330 })?.value != blockHandle { problems.append("\(layoutName) does not point back") }
            let order = after.first(where: { $0.code == 71 })?.value
            if order != (layoutName == "Model" ? "0" : "1") { problems.append("\(layoutName) tab order \(order ?? "-")") }
        }
        if let model = blockRecord("*Model_Space")?.handle {
            for entity in entities where entity.first(330) != model { problems.append("\(entity.type) is not owned by model space") }
        }
        return problems
    }
}
