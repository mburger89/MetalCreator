/// ISO 286-1 and 286-2 tables, in micrometres, one value per size range (plan R11). Arrays, never dictionaries.
enum ISO286Tables {
    /// Upper bounds of "over a up to and including b" for the 13 ranges, in millimetres.
    static let rangeUpperBounds: [Double] = [3, 6, 10, 18, 30, 50, 80, 120, 180, 250, 315, 400, 500]

    /// The IT values of grades 4 to 11 (IT4 is for the hole deviation Δ only).
    static let it4: [Double] = [3, 4, 4, 5, 6, 7, 8, 10, 12, 14, 16, 18, 20]
    static let it5: [Double] = [4, 5, 6, 8, 9, 11, 13, 15, 18, 20, 23, 25, 27]
    static let it6: [Double] = [6, 8, 9, 11, 13, 16, 19, 22, 25, 29, 32, 36, 40]
    static let it7: [Double] = [10, 12, 15, 18, 21, 25, 30, 35, 40, 46, 52, 57, 63]
    static let it8: [Double] = [14, 18, 22, 27, 33, 39, 46, 54, 63, 72, 81, 89, 97]
    static let it9: [Double] = [25, 30, 36, 43, 52, 62, 74, 87, 100, 115, 130, 140, 155]
    static let it10: [Double] = [40, 48, 58, 70, 84, 100, 120, 140, 160, 185, 210, 230, 250]
    static let it11: [Double] = [60, 75, 90, 110, 130, 160, 190, 220, 250, 290, 320, 360, 400]

    /// Fundamental deviations of the shafts f and g (es, negative) and the lower deviations of k, n and p (ei).
    static let fEs: [Double] = [-6, -10, -13, -16, -20, -25, -30, -36, -43, -50, -56, -62, -68]
    static let gEs: [Double] = [-2, -4, -5, -6, -7, -9, -10, -12, -14, -15, -17, -18, -20]
    static let kEi: [Double] = [0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4, 5]
    static let nEi: [Double] = [4, 8, 10, 12, 15, 17, 20, 23, 27, 31, 34, 37, 40]
    static let pEi: [Double] = [6, 12, 15, 18, 22, 26, 32, 37, 43, 50, 56, 62, 68]

    /// Shaft s has its own, finer ranges above 50 mm.
    static let sUpperBounds: [Double] = [
        3, 6, 10, 18, 30, 50, 65, 80, 100, 120, 140, 160, 180, 200, 225, 250, 280, 315, 355, 400, 450, 500,
    ]
    static let sEi: [Double] = [
        14, 19, 23, 28, 35, 43, 53, 59, 71, 79, 92, 100, 108, 122, 130, 140, 158, 170, 190, 208, 232, 252,
    ]

    static func rangeIndex(of size: Double, in bounds: [Double]) -> Int? {
        guard size > 0 else { return nil }
        return bounds.firstIndex { size <= $0 }
    }

    static func it(grade: Int) -> [Double]? {
        switch grade {
        case 4: it4
        case 5: it5
        case 6: it6
        case 7: it7
        case 8: it8
        case 9: it9
        case 10: it10
        case 11: it11
        default: nil
        }
    }
}
