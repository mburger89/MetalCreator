// Test fixture file: small KiCad 10 boards written as text, for the Import KiCad Board tests.
import Foundation

enum KiCadBoardText {
    /// A footprint with one drilled pad at its origin: a round hole, or a slot `slot` long (its width `drill`, along x).
    struct Part {
        var reference: String
        var x: Double
        var y: Double
        var library = "MountingHole:MountingHole_3.2mm_M3"
        var drill = 3.2
        var slot: Double?
        var plated = false
        /// The footprint's angle, its side and whether it has a pad (a part with models and no hole has none).
        var angle = 0.0
        var back = false
        var hasPad = true
        var models: [Model] = []
    }

    /// A `(model …)` line of a footprint.
    struct Model {
        var path: String
        var offset = (0.0, 0.0, 0.0)
        var scale = (1.0, 1.0, 1.0)
        var rotate = (0.0, 0.0, 0.0)
        var hidden = false

        var text: String {
            "    (model \"\(path)\" (offset (xyz \(offset.0) \(offset.1) \(offset.2))) (scale (xyz \(scale.0) \(scale.1) \(scale.2))) "
                + "(rotate (xyz \(rotate.0) \(rotate.1) \(rotate.2)))\(hidden ? " (hide yes)" : ""))\n"
        }
    }

    static let header = "(kicad_pcb (version 20260206) (generator \"pcbnew\")\n"

    static func stroke(_ id: String) -> String { "(layer \"Edge.Cuts\") (stroke (width 0.15) (type default)) (uuid \"\(id)\")" }

    static func uuid(_ n: Int) -> String { String(format: "00000000-0000-0000-0000-%012d", n) }

    static func footprint(_ part: Part, number: Int) -> String {
        let side = part.back ? "B.Cu" : "F.Cu"
        var text = "  (footprint \"\(part.library)\" (layer \"\(side)\") (uuid \"\(uuid(9000 + number))\") "
            + "(at \(part.x) \(part.y) \(part.angle))\n"
        text += "    (property \"Reference\" \"\(part.reference)\" (at 0 -4 0) (layer \"F.Cu\"))\n"
        let kind = part.plated ? "thru_hole" : "np_thru_hole"
        text += part.models.map(\.text).joined()
        if !part.hasPad {
            return text + "  )\n"
        }
        if let slot = part.slot {
            text += "    (pad \"1\" \(kind) oval (at 0 0) (size \(slot + 1) \(part.drill + 1)) (drill oval \(slot) \(part.drill)) "
                + "(layers \"*.Cu\" \"*.Mask\"))\n"
        } else {
            text += "    (pad \"\" \(kind) circle (at 0 0) (size \(part.drill) \(part.drill)) (drill \(part.drill)) "
                + "(layers \"*.Cu\" \"*.Mask\"))\n"
        }
        return text + "  )\n"
    }

    static let corners = [(4.0, 4.0), (96.0, 4.0), (96.0, 76.0), (4.0, 76.0)]

    static func fourMounting() -> [Part] {
        corners.enumerated().map { Part(reference: "H\($0.offset + 1)", x: $0.element.0, y: $0.element.1) }
    }

    /// A 100 x 80 rectangle (file corners (0,0) to (100,80)) with `parts`.
    static func rectangle(parts: [Part] = fourMounting(), thickness: Double? = 1.6, aux: (Double, Double)? = nil,
                          extra: String = "") -> String {
        var text = header
        if let thickness { text += "  (general (thickness \(thickness)))\n" }
        if let aux { text += "  (setup (aux_axis_origin \(aux.0) \(aux.1)))\n" }
        for (i, line) in [(0, 0, 100, 0), (100, 0, 100, 80), (100, 80, 0, 80), (0, 80, 0, 0)].enumerated() {
            text += "  (gr_line (start \(line.0) \(line.1)) (end \(line.2) \(line.3)) \(stroke(uuid(i))))\n"
        }
        for (i, part) in parts.enumerated() { text += footprint(part, number: i) }
        return text + extra + ")\n"
    }

    /// A 100 x 80 board with 5 mm rounded corners (arcs as start, mid, end), its top edge a `gr_curve`, and a circular cutout of
    /// radius 10 at (50, 40).
    static func rounded() -> String {
        let r = 5.0, k = r * (1 - 0.5.squareRoot()) // the mid point of a corner arc is k in from each side of the corner
        func arc(_ s: (Double, Double), _ m: (Double, Double), _ e: (Double, Double), _ n: Int) -> String {
            "  (gr_arc (start \(s.0) \(s.1)) (mid \(m.0) \(m.1)) (end \(e.0) \(e.1)) \(stroke(uuid(100 + n))))\n"
        }
        func line(_ a: (Double, Double), _ b: (Double, Double), _ n: Int) -> String {
            "  (gr_line (start \(a.0) \(a.1)) (end \(b.0) \(b.1)) \(stroke(uuid(200 + n))))\n"
        }
        var text = header + "  (general (thickness 1.6))\n"
        text += "  (gr_curve (pts (xy 5 0) (xy 35 0) (xy 65 0) (xy 95 0)) \(stroke(uuid(300))))\n"
        text += arc((95, 0), (100 - k, k), (100, 5), 1)
        text += line((100, 5), (100, 75), 1)
        text += arc((100, 75), (100 - k, 80 - k), (95, 80), 2)
        text += line((95, 80), (5, 80), 2)
        text += arc((5, 80), (k, 80 - k), (0, 75), 3)
        text += line((0, 75), (0, 5), 3)
        text += arc((0, 5), (k, k), (5, 0), 4)
        text += "  (gr_circle (center 50 40) (end 60 40) \(stroke(uuid(400))))\n"
        return text + ")\n"
    }

    /// A rectangle with two circular cutouts of radius 5, at file (25, 40) and (`secondX`, 40), the second named `secondID`.
    static func twoCutouts(secondX: Double, secondID: Int = 501) -> String {
        rectangle(parts: [], extra:
            "  (gr_circle (center 25 40) (end 30 40) \(stroke(uuid(500))))\n"
            + "  (gr_circle (center \(secondX) 40) (end \(secondX + 5) 40) \(stroke(uuid(secondID))))\n")
    }

    static func via(x: Double, y: Double) -> String {
        "  (via (at \(x) \(y)) (size 0.8) (drill 0.4) (layers \"F.Cu\" \"B.Cu\") (uuid \"\(uuid(7000))\"))\n"
    }
}
