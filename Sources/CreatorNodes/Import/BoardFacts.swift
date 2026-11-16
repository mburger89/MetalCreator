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

    static func facts(file: String, board: KiCadBoard, size: Vector2Size, thickness: Double, drilled: Int, mounting: Int) -> [PayloadFact] {
        [
            PayloadFact("File", file),
            PayloadFact("KiCad version", versionName(board.version)),
            PayloadFact("Size", "\(size.width.display) × \(size.height.display) mm"),
            PayloadFact("Thickness", "\(thickness.display) mm"),
            PayloadFact("Copper layers", board.copperLayers.display),
            PayloadFact("Holes", "\(drilled.display) drilled, \(mounting.display) mounting"),
            PayloadFact("Components", "\(board.footprints.count.display) placed"),
        ]
    }

    struct Vector2Size {
        var width: Double
        var height: Double
    }
}
