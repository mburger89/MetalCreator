import CreatorKernel
import Foundation

extension ImplicitSolid: CustomStringConvertible {
    /// A one-line recipe like `Field.description` (implicit spec §2.1), such as
    /// `intersect(shell(implicit(Bracket), inward 2 mm), sphere(radius 40 mm))`. The inspector shows it; a socket's tooltip shows
    /// `description(limit: 80)`. Numbers are written in `Locale.messages`, millimetres with a "mm".
    public var description: String {
        switch self {
        case .sphere(let radius):
            return "sphere(radius \(Self.mm(radius)))"
        case .box(let half, let cornerRadius):
            let size = [half.x, half.y, half.z].map { ($0 * 2).millimetreText(locale: .messages) }.joined(separator: " × ")
            return "box(\(size) mm" + (cornerRadius > 0 ? ", corner radius \(Self.mm(cornerRadius)))" : ")")
        case .cylinder(let radius, let halfHeight):
            return "cylinder(radius \(Self.mm(radius)), height \(Self.mm(halfHeight * 2)))"
        case .moved(let child, _):
            return "place(\(child.description))"
        case .union(let children, let blend):
            return Self.combination("union", children, blend)
        case .subtract(let children, let blend):
            return Self.combination("subtract", children, blend)
        case .intersect(let children, let blend):
            return Self.combination("intersect", children, blend)
        case .offset(let child, let distance):
            return "offset(\(child.description), \(Self.text(distance)))"
        case .shell(let child, let thickness, let side):
            return "shell(\(child.description), \(side.name.lowercased()) \(Self.text(thickness)))"
        case .baked(_, let label):
            return "implicit(\(label))"
        case .isosurface(let grading, let level, let maxSlope, _):
            return "isosurface(\(grading.field.description), level \(level.millimetreText(locale: .messages)), "
                + "max slope \(maxSlope.millimetreText(locale: .messages)))"
        case .tpms(let lattice):
            return "\(lattice.type.name.lowercased())(cell \(Self.text(lattice.cells.size)), \(lattice.form.name.lowercased()), "
                + "t = \(Self.text(lattice.thickness))\(Self.stretchText(lattice.cells)))"
        }
    }

    /// The recipe cut to `limit` characters, ending in "…" when it was cut.
    public func description(limit: Int) -> String {
        let text = description
        guard text.count > limit else { return text }
        return String(text.prefix(max(limit - 1, 0))) + "…"
    }

    private static func combination(_ name: String, _ children: [ImplicitSolid], _ blend: Grading) -> String {
        let inner = children.map(\.description).joined(separator: ", ")
        if let value = blend.constantValue, value == 0 { return "\(name)(\(inner))" }
        return "\(name)(\(inner), blend \(text(blend)))"
    }

    /// A setting: a constant in millimetres, else the field's recipe.
    static func text(_ grading: Grading) -> String {
        grading.constantValue.map(mm) ?? grading.field.description
    }

    /// A size in millimetres, with a true minus sign.
    static func mm(_ value: Double) -> String {
        "\(value.millimetreText(locale: .messages).replacing("-", with: "−")) mm"
    }

    /// ", stretch x : y : z" for cells that are not cubes, else nothing.
    static func stretchText(_ cells: LatticeCells) -> String {
        let stretch = cells.stretch
        guard abs(stretch.x - 1) > 1e-9 || abs(stretch.y - 1) > 1e-9 || abs(stretch.z - 1) > 1e-9 else { return "" }
        let parts = [stretch.x, stretch.y, stretch.z].map { $0.millimetreText(locale: .messages) }
        return ", stretch " + parts.joined(separator: " : ")
    }
}
