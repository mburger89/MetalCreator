import CreatorGeometry
import Foundation

extension KiCadBoardReader {
    static func readFootprint(_ item: SExpression, version: Int, pads: inout Int, limits: KiCadLimits,
                              edges: inout [EdgeItem]) throws -> Footprint {
        let (place, usesTransform) = try placement(of: item)
        var holes: [DrilledHole] = []
        var padCount = 0
        guard case .list(let children) = item else { throw KiCadProblem("This isn't a KiCad board file.") }
        for child in children {
            switch child.keyword {
            case "pad":
                pads += 1
                padCount += 1
                guard pads <= limits.maxPads else {
                    throw KiCadProblem("This board has more than \(count(limits.maxPads)) pads.")
                }
                if let hole = try hole(of: child, place: place, usesTransform: usesTransform) { holes.append(hole) }
            default:
                edges += try edgeItems(in: child, place: place, version: version)
            }
        }
        var footprint = Footprint(
            reference: reference(of: item),
            libraryID: item.text(at: 1) ?? "",
            uuid: identifier(of: item),
            isBack: item.child("layer")?.text(at: 1) == "B.Cu",
            place: place,
            holes: holes,
            padCount: padCount,
            models: item.children("model").compactMap(model(of:)))
        footprint.embeddedModels = item.children("embedded_files").flatMap { embeddedModels(in: $0, version: version) }
        return footprint
    }

    /// `(at x y a)`, or `(transform (translate x y) (rotate a) (scale sx sy))` from 20260616.
    private static func placement(of footprint: SExpression) throws -> (Placement2D, Bool) {
        if let transform = footprint.child("transform") {
            var place = Placement2D()
            if let translate = transform.child("translate"), let origin = try point(translate) { place.origin = origin }
            place.angle = try number(transform.child("rotate"), 1) ?? 0
            if let scale = transform.child("scale"), let sx = Double(scale.text(at: 1) ?? "") {
                let sy = Double(scale.text(at: 2) ?? "") ?? sx
                place.scale = Vector2(sx.isFinite && sx > 0 ? sx : 1, sy.isFinite && sy > 0 ? sy : 1)
            }
            return (place, true)
        }
        guard let at = footprint.child("at"), let origin = try point(at) else { return (.identity, false) }
        return (Placement2D(origin: origin, angle: try number(at, 3) ?? 0), false)
    }

    private static func reference(of footprint: SExpression) -> String {
        if let property = footprint.children("property").first(where: { $0.text(at: 1) == "Reference" }),
           let value = property.text(at: 2) { return value }
        if let text = footprint.children("fp_text").first(where: { $0.text(at: 1) == "reference" }),
           let value = text.text(at: 2) { return value }
        return ""
    }

    // MARK: Pads

    private static func hole(of pad: SExpression, place: Placement2D, usesTransform: Bool) throws -> DrilledHole? {
        guard let drill = pad.child("drill"), let at = pad.child("at"), let local = try point(at) else { return nil }
        let isOval = drill.text(at: 1) == "oval"
        let first = try number(drill, isOval ? 2 : 1)
        // KiCad writes `(drill oval 1.0)` when the height equals the width.
        let second = isOval ? try number(drill, 3) ?? first : first
        guard let width = first, let height = second, width > 0, height > 0 else { return nil }

        // The pad's angle is absolute in an `at` footprint and in the library frame in a `transform` one (ruling).
        let fileAngle = try number(at, 3) ?? 0
        let angle = usesTransform ? fileAngle + place.angle : fileAngle
        var center = try placed(place, local)
        if let offset = drill.child("offset"), let shift = try point(offset) {
            center += Placement2D.turn(shift, byDegrees: angle)
            guard abs(center.x) <= 1e6, abs(center.y) <= 1e6 else { throw outOfRange }
        }
        let number = pad.text(at: 1) ?? ""
        let plated = pad.text(at: 2) != "np_thru_hole"
        guard isOval, width != height else {
            return DrilledHole(center: center, diameter: width, isPlated: plated, padNumber: number)
        }
        let longAlongX = width > height
        return DrilledHole(center: center, diameter: min(width, height), slotLength: max(width, height),
                           angle: normalised(longAlongX ? angle : angle + 90), isPlated: plated, padNumber: number)
    }

    /// Degrees in [0, 360).
    private static func normalised(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    // MARK: Models

    private static func model(of model: SExpression) -> ModelReference? {
        guard let path = model.text(at: 1) else { return nil }
        // Before KiCad 5 the offset was `(at (xyz …))` in inches; the parser has no version check (facts §5).
        let offset = xyz(model.child("offset")) ?? xyz(model.child("at")).map { $0 * 25.4 } ?? Vector3(0, 0, 0)
        return ModelReference(path: path, offset: offset, scale: xyz(model.child("scale")) ?? Vector3(1, 1, 1),
                              rotation: xyz(model.child("rotate")) ?? Vector3(0, 0, 0), isHidden: model.hasFlag("hide"))
    }

    private static func xyz(_ holder: SExpression?) -> Vector3? {
        guard let vector = holder?.child("xyz"), let x = vector.number(at: 1), let y = vector.number(at: 2),
              let z = vector.number(at: 3) else { return nil }
        return Vector3(x, y, z)
    }
}
