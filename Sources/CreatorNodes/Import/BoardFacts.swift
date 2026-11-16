import CreatorGraph
import CreatorPCB

/// What the inspector says about an imported board (KiCad import spec, Facts).
enum BoardFacts {
    /// "KiCad 10 (20260206)": the release a file version belongs to (the newest release whose version is not above it), then
    /// the number. Versions are the tips of each release's branch (format facts §6).
    static func versionName(_ version: Int) -> String {
        let releases: [(version: Int, name: String)] = [
            (20_261_031, "KiCad 11 development"), (20_260_206, "KiCad 10"), (20_241_229, "KiCad 9"), (20_240_108, "KiCad 8"),
            (20_221_018, "KiCad 7"), (20_211_014, "KiCad 6"), (20_171_130, "KiCad 5"),
        ]
        let name = releases.first { version >= $0.version }?.name ?? "KiCad 4"
        return "\(name) (\(version))"
    }

    static func facts(file: String, board: KiCadBoard, width: Double, height: Double, thickness: Double, holes: String) -> [PayloadFact] {
        [
            PayloadFact("File", file),
            PayloadFact("KiCad version", versionName(board.version)),
            PayloadFact("Size", "\(width.display) × \(height.display) mm"),
            PayloadFact("Thickness", "\(thickness.display) mm"),
            PayloadFact("Copper layers", board.copperLayers.display),
            PayloadFact("Holes", holes),
            PayloadFact("Components", "\(board.footprints.count.display) placed"),
        ]
    }

    /// "189 drilled, 4 mounting": pad holes only; vias, when the node includes them, add ", 120 vias".
    static func holesText(board: KiCadBoard, mounting: Int, includesVias: Bool) -> String {
        let drilled = board.footprints.reduce(0) { $0 + $1.holes.count }
        return "\(drilled.display) drilled, \(mounting.display) mounting" + (includesVias ? ", \(board.vias.count.display) vias" : "")
    }
}
