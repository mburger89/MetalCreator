/// ISO 2768-1 general tolerances (plan R10): Table 1 for linear sizes, Table 2 for radii and chamfer heights.
public enum ISO2768 {
    /// Upper bounds of [0.5,3] (3,6] (6,30] (30,120] (120,400] (400,1000] (1000,2000] (2000,4000].
    private static let linearBounds: [Double] = [3, 6, 30, 120, 400, 1000, 2000, 4000]
    private static let fine: [Double?] = [0.05, 0.05, 0.1, 0.15, 0.2, 0.3, 0.5, nil]
    private static let medium: [Double?] = [0.1, 0.1, 0.2, 0.3, 0.5, 0.8, 1.2, 2]
    private static let coarse: [Double?] = [0.2, 0.3, 0.5, 0.8, 1.2, 2, 3, 4]
    private static let veryCoarse: [Double?] = [nil, 0.5, 1, 1.5, 2.5, 4, 6, 8]

    /// The permitted deviation (±, millimetres) of a length, nil outside the table.
    public static func linear(_ size: Double, class tolerance: ISO2768Class) -> Double? {
        guard size >= 0.5, let index = linearBounds.firstIndex(where: { size <= $0 }) else { return nil }
        switch tolerance {
        case .f: return fine[index]
        case .m: return medium[index]
        case .c: return coarse[index]
        case .v: return veryCoarse[index]
        }
    }

    /// The permitted deviation of an external radius or chamfer height, nil under 0.5 mm.
    public static func brokenEdge(_ size: Double, class tolerance: ISO2768Class) -> Double? {
        guard size >= 0.5 else { return nil }
        let index = size <= 3 ? 0 : (size <= 6 ? 1 : 2)
        switch tolerance {
        case .f, .m: return [0.2, 0.5, 1][index]
        case .c, .v: return [0.4, 1, 2][index]
        }
    }
}
