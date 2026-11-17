import Foundation

/// Small hand-written boards in each KiCad era: a 100 x 80 rectangle (file corners (0,0) to (100,80)), a quarter arc
/// in its middle, and four MountingHole_3.2mm_M3 footprints H1 to H4 inset 4 mm. H2 is turned 90 degrees and has a second,
/// plated pad with an oval drill (1 x 2, offset 0.5 0) at library (2, 0), its own angle 90 in the file's absolute form.
enum BoardFixtures {
    enum Era: CaseIterable {
        case kicad4, kicad5, kicad6, kicad8, kicad10, kicad11

        var version: String {
            switch self {
            case .kicad4: "4"
            case .kicad5: "20171130"
            case .kicad6: "20211014"
            case .kicad8: "20240108"
            case .kicad10: "20260206"
            case .kicad11: "20261031"
            }
        }

        var isOld: Bool { self == .kicad4 || self == .kicad5 }
        var usesUUID: Bool { self == .kicad8 || self == .kicad10 || self == .kicad11 }
    }

    static let rectangleWithFourM3 = rectangleWithFourM3(.kicad10)

    static func rectangleWithFourM3(_ era: Era) -> String {
        let generator = era == .kicad4 || era == .kicad5 ? "(host pcbnew \"\(era.version)\")" : "(generator \"pcbnew\")"
        var text = "(kicad_pcb (version \(era.version)) \(generator)\n"
        text += "  (general (thickness 1.6))\n"
        text += "  (layers (0 \(name("F.Cu", era)) signal) (31 \(name("B.Cu", era)) signal) (44 \(name("Edge.Cuts", era)) user))\n"
        text += "  (setup (aux_axis_origin 0 0))\n"
        for (index, line) in [(0, 0, 100, 0), (100, 0, 100, 80), (100, 80, 0, 80), (0, 80, 0, 0)].enumerated() {
            text += "  (gr_line (start \(line.0) \(line.1)) (end \(line.2) \(line.3)) "
            text += tail(era, width: "0.15", id: "00000000-0000-0000-0000-00000000000\(index)", stamp: "5A00000\(index)") + "\n"
        }
        text += arc(era)
        let corners = [(4, 4), (96, 4), (96, 76), (4, 76)]
        for (index, corner) in corners.enumerated() {
            text += footprint(era, number: index + 1, x: corner.0, y: corner.1, angle: index == 1 ? 90 : 0)
        }
        return text + ")\n"
    }

    private static func name(_ layer: String, _ era: Era) -> String { era.isOld ? layer : "\"\(layer)\"" }

    /// The line or arc's closing items: the layer, the width or stroke, the identifier.
    private static func tail(_ era: Era, width: String, id: String, stamp: String) -> String {
        let layer = "(layer \(name("Edge.Cuts", era)))"
        switch era {
        case .kicad4, .kicad5: return "\(layer) (width \(width)) (tstamp \(stamp)))"
        case .kicad6: return "\(layer) (width \(width)) (tstamp \(id)))"
        default: return "\(layer) (stroke (width \(width)) (type default)) (uuid \"\(id)\"))"
        }
    }

    /// A quarter arc about (50, 40) from (60, 40) to (50, 50): legacy centre, start point and angle up to 20210925.
    private static func arc(_ era: Era) -> String {
        if era == .kicad4 || era == .kicad5 {
            return "  (gr_arc (start 50 40) (end 60 40) (angle 90) (layer Edge.Cuts) (width 0.15))\n"
        }
        let mid = "57.0710678118655 47.0710678118655"
        return "  (gr_arc (start 60 40) (mid \(mid)) (end 50 50) "
            + tail(era, width: "0.15", id: "00000000-0000-0000-0000-0000000000A0", stamp: "") + "\n"
    }

    private static func footprint(_ era: Era, number: Int, x: Int, y: Int, angle: Int) -> String {
        let keyword = era.isOld ? "module" : "footprint"
        let library = era.isOld ? "MountingHole:MountingHole_3.2mm_M3" : "\"MountingHole:MountingHole_3.2mm_M3\""
        let position = era == .kicad11 ? "(transform (translate \(x) \(y)) (rotate \(angle)) (scale 1 1))"
            : "(at \(x) \(y)\(angle == 0 ? "" : " \(angle)"))"
        let layer = "(layer \(name("F.Cu", era)))"
        let id = era.usesUUID ? "(uuid \"1111111\(number)-0000-0000-0000-000000000000\")" : "(tstamp 5B00000\(number))"
        let effects = "(effects (font (size 1.5 1.5) (thickness 0.15)))"
        var text = "  (\(keyword) \(library) \(layer) \(id) \(position)\n"
        if era.usesUUID {
            text += "    (property \"Reference\" \"H\(number)\" (at 0 -4 0) \(layer) \(effects))\n"
        } else {
            text += "    (fp_text reference H\(number) (at 0 -4) \(layer) \(effects))\n"
        }
        let padLayers = era.isOld ? "(layers *.Cu *.Mask)" : "(layers \"*.Cu\" \"*.Mask\")"
        text += "    (pad \"\" np_thru_hole circle (at 0 0) (size 3.2 3.2) (drill 3.2) \(padLayers))\n"
        if angle != 0 {
            // The pad's own angle is absolute in the `at` forms and in the library frame in the `transform` form.
            let padAngle = era == .kicad11 ? 0 : angle
            text += "    (pad \"1\" thru_hole oval (at 2 0 \(padAngle)) (size 2 3) (drill oval 1 2 (offset 0.5 0)) \(padLayers))\n"
        }
        text += "  )\n"
        return text
    }
}
