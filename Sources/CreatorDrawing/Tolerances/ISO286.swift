/// The deviations of a fit from the nominal size, in millimetres.
public struct FitLimits: Hashable, Sendable {
    public var upper: Double
    public var lower: Double

    public init(upper: Double, lower: Double) {
        self.upper = upper
        self.lower = lower
    }
}

/// ISO 286 limits and fits (plan R11): sizes over 0 up to 500 mm, grades IT5 to IT11.
public enum ISO286 {
    static let sizeSentence = "ISO 286 fits are given here for sizes over 0 up to 500 mm."
    static let gradeSentence = "ISO 286 grades here run from IT5 to IT11."

    /// The standard tolerance IT of `grade` at `size`, in millimetres.
    public static func standardTolerance(grade: Int, size: Double) throws(DrawingRefusal) -> Double {
        guard FitDesignation.grades.contains(grade), let values = ISO286Tables.it(grade: grade) else {
            throw DrawingRefusal(sentence: gradeSentence)
        }
        let index = try rangeIndex(size)
        return values[index] / 1000
    }

    public static func limits(of fit: FitDesignation, size: Double) throws(DrawingRefusal) -> FitLimits {
        let grade = fit.grade
        guard FitDesignation.grades.contains(grade), let values = ISO286Tables.it(grade: grade) else {
            throw DrawingRefusal(sentence: gradeSentence)
        }
        let index = try rangeIndex(size)
        let it = values[index]
        // All arithmetic in micrometres, divided once at the end.
        let micro: (upper: Double, lower: Double)
        switch fit {
        case .shaft(let letter, _):
            micro = shaft(letter, grade: grade, size: size, index: index, it: it)
        case .hole(let letter, _):
            micro = hole(letter, grade: grade, index: index, it: it)
        }
        return FitLimits(upper: micro.upper / 1000, lower: micro.lower / 1000)
    }

    private static func rangeIndex(_ size: Double) throws(DrawingRefusal) -> Int {
        guard let index = ISO286Tables.rangeIndex(of: size, in: ISO286Tables.rangeUpperBounds) else {
            throw DrawingRefusal(sentence: sizeSentence)
        }
        return index
    }

    private static func shaft(
        _ letter: ShaftFitLetter, grade: Int, size: Double, index: Int, it: Double
    ) -> (upper: Double, lower: Double) {
        switch letter {
        case .h: return (0, -it)
        case .js: return (it / 2, -it / 2)
        case .f: return (ISO286Tables.fEs[index], ISO286Tables.fEs[index] - it)
        case .g: return (ISO286Tables.gEs[index], ISO286Tables.gEs[index] - it)
        case .k:
            let ei = grade <= 7 ? ISO286Tables.kEi[index] : 0
            return (ei + it, ei)
        case .n: return (ISO286Tables.nEi[index] + it, ISO286Tables.nEi[index])
        case .p: return (ISO286Tables.pEi[index] + it, ISO286Tables.pEi[index])
        case .s:
            let sIndex = ISO286Tables.rangeIndex(of: size, in: ISO286Tables.sUpperBounds) ?? ISO286Tables.sEi.count - 1
            let ei = ISO286Tables.sEi[sIndex]
            return (ei + it, ei)
        }
    }

    private static func hole(_ letter: HoleFitLetter, grade: Int, index: Int, it: Double) -> (upper: Double, lower: Double) {
        // Δ is used only above 3 mm; the first range has its own rule for K, N and P.
        let delta: Double = {
            guard index > 0, let previous = ISO286Tables.it(grade: grade - 1) else { return 0 }
            return it - previous[index]
        }()
        switch letter {
        case .H: return (it, 0)
        case .JS: return (it / 2, -it / 2)
        case .F: return (-ISO286Tables.fEs[index] + it, -ISO286Tables.fEs[index])
        case .G: return (-ISO286Tables.gEs[index] + it, -ISO286Tables.gEs[index])
        case .K:
            let es = index == 0 ? 0 : (grade <= 8 ? -ISO286Tables.kEi[index] + delta : 0)
            return (es, es - it)
        case .N:
            let es = index == 0 ? -4 : (grade <= 8 ? -ISO286Tables.nEi[index] + delta : 0)
            return (es, es - it)
        case .P:
            let es = index == 0 ? -6 : (grade <= 7 ? -ISO286Tables.pEi[index] + delta : -ISO286Tables.pEi[index])
            return (es, es - it)
        }
    }
}
