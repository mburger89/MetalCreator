import CreatorGeometry
import Foundation

/// Reads a `.kicad_pcb` file into a `KiCadBoard`, every point y up.
public enum KiCadBoardReader {
    public static func read(_ data: Data, limits: KiCadLimits = .standard, isCancelled: () -> Bool = { false }) throws -> KiCadBoard {
        if data.starts(with: Data("PCBNEW-BOARD".utf8)) {
            throw KiCadProblem("This is an old KiCad board (.brd). Open it in KiCad and save it as a .kicad_pcb, then try again.")
        }
        let root = try SExpressionReader.read(data, limits: limits, isCancelled: isCancelled)
        guard root.keyword == "kicad_pcb" else { throw KiCadProblem("This isn't a KiCad board file.") }

        var board = try header(of: root)
        var pads = 0
        guard case .list(let items) = root else { return board }
        for item in items {
            guard let keyword = item.keyword else { continue }
            switch keyword {
            case "footprint", "module":
                if isCancelled() { throw CancellationError() }
                try requireRoom(for: board.footprints.count, limits: limits)
                board.footprints.append(
                    try readFootprint(item, version: board.version, pads: &pads, limits: limits, edges: &board.edgeItems))
            case "via":
                if let via = try readVia(item) { board.vias.append(via) }
            default:
                board.edgeItems += try edgeItems(in: item, place: .identity, version: board.version)
            }
        }
        return board
    }

    private static func header(of root: SExpression) throws -> KiCadBoard {
        var board = KiCadBoard()
        if let text = root.child("version")?.text(at: 1) {
            guard let value = Double(text), let version = Int(exactly: value), (0...99_999_999).contains(version) else {
                throw outOfRange
            }
            board.version = version
        }
        board.generator = root.child("generator")?.text(at: 1) ?? root.child("host")?.text(at: 1)
        board.thickness = thickness(of: root)
        board.copperLayers = copperLayerCount(of: root)
        if let origin = root.child("setup")?.child("aux_axis_origin") { board.auxAxisOrigin = try point(origin) }
        return board
    }

    private static func requireRoom(for footprints: Int, limits: KiCadLimits) throws {
        guard footprints < limits.maxFootprints else {
            throw KiCadProblem("This board has more than \(count(limits.maxFootprints)) footprints.")
        }
    }

    static func count(_ number: Int) -> String {
        number.formatted(.number.locale(Locale(identifier: "en_US")))
    }

    // MARK: Header

    private static func thickness(of root: SExpression) -> Double? {
        if let value = root.child("general")?.child("thickness")?.number(at: 1), value > 0 { return value }
        guard let stackup = root.child("setup")?.child("stackup") else { return nil }
        let sum = stackup.children("layer").reduce(0.0) { total, layer in
            total + (layer.child("thickness")?.number(at: 1) ?? 0)
        }
        return sum > 0 ? sum : nil
    }

    private static func copperLayerCount(of root: SExpression) -> Int {
        guard case .list(let entries)? = root.child("layers") else { return 0 }
        return entries.dropFirst().filter { $0.text(at: 1)?.hasSuffix(".Cu") == true }.count
    }

    // MARK: Vias

    private static func readVia(_ via: SExpression) throws -> DrilledHole? {
        guard let at = via.child("at"), let center = try point(at),
              let drill = try number(via.child("drill"), 1), drill > 0 else { return nil }
        return DrilledHole(center: center, diameter: drill, isPlated: true)
    }

    // MARK: Shared readers

    static let outOfRange = KiCadProblem("The board file has a number out of range.")

    /// The number at `index`: nil when absent or not a number, a refusal when non-finite or beyond 1e6 (mm or degrees).
    static func number(_ list: SExpression?, _ index: Int) throws -> Double? {
        guard let text = list?.text(at: index), let value = Double(text) else { return nil }
        guard value.isFinite, abs(value) <= 1e6 else { throw outOfRange }
        return value
    }

    /// A list's first two numbers as a y-up point.
    static func point(_ list: SExpression) throws -> Vector2? {
        guard let x = try number(list, 1), let y = try number(list, 2) else { return nil }
        return Vector2(x, -y)
    }

    static func point(_ parent: SExpression, _ name: String) throws -> Vector2? {
        guard let child = parent.child(name) else { return nil }
        return try point(child)
    }

    /// `place.apply(local)`, refused when it leaves the range.
    static func placed(_ place: Placement2D, _ local: Vector2) throws -> Vector2 {
        let result = place.apply(local)
        guard result.x.isFinite, result.y.isFinite, abs(result.x) <= 1e6, abs(result.y) <= 1e6 else { throw outOfRange }
        return result
    }

    static func identifier(of item: SExpression) -> String? {
        item.child("uuid")?.text(at: 1) ?? item.child("tstamp")?.text(at: 1)
    }
}
