import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// The read-only facts a node lists about a control net (NURBS spec, control points): shared by Edit Surface, Edit Curve and the
/// rebuild nodes. Pure formatting, no kernel.
enum ControlNetFacts {
    /// "Degree: 3 × 3", "Control points: 6 × 8", "Knots: 4 × 6" (distinct knots in each direction), "Rational: no", and a line
    /// saying so when the surface was a plane, cylinder or the like before conversion.
    static func surface(_ net: BSplineSurface3D, kind: SurfaceKind?) -> [PayloadFact] {
        var facts = [
            PayloadFact("Degree", "\(net.degreeU.display) × \(net.degreeV.display)"),
            PayloadFact("Control points", "\(net.uCount.display) × \(net.vCount.display)"),
            PayloadFact("Knots", "\(net.knotsU.count.display) × \(net.knotsV.count.display)"),
            PayloadFact("Rational", net.weights == nil ? "no" : "yes"),
        ]
        if let kind { facts.append(PayloadFact("Converted", "Converted exactly from \(article(for: kind.rawValue))")) }
        return facts
    }

    /// The same for a curve: "Degree: 3", "Control points: 12", "Knots: 9", "Rational: no".
    static func curve(_ net: BSplineCurve3D, kind: CurvePieceKind?) -> [PayloadFact] {
        var facts = [
            PayloadFact("Degree", net.degree.display),
            PayloadFact("Control points", net.poles.count.display),
            PayloadFact("Knots", net.knots.count.display),
            PayloadFact("Rational", net.weights == nil ? "no" : "yes"),
        ]
        if let kind { facts.append(PayloadFact("Converted", "Converted exactly from \(article(for: kind.rawValue))")) }
        return facts
    }

    /// "a cylinder.", "an offset surface."-style ending for a kind's name.
    private static func article(for name: String) -> String {
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        return (vowels.contains(name.first ?? "x") ? "an " : "a ") + name + "."
    }

    /// "3 control point moves no longer fit" or "1 control point move no longer fits", ending in `place` and a period.
    static func staleWarning(count: Int, place: String) -> String {
        count == 1
            ? "1 control point move no longer fits \(place)."
            : "\(count.display) control point moves no longer fit \(place)."
    }
}
