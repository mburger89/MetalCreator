import Testing

@testable import CreatorDrawing

struct ISO286Tests {
    private func check(_ fit: FitDesignation, _ size: Double, _ upper: Double, _ lower: Double) throws {
        let limits = try ISO286.limits(of: fit, size: size)
        #expect(abs(limits.upper - upper) < 1e-12)
        #expect(abs(limits.lower - lower) < 1e-12)
    }

    @Test func holeH7At20() throws { try check(.hole(.H, grade: 7), 20, 0.021, 0) }
    @Test func shaftG6At20() throws { try check(.shaft(.g, grade: 6), 20, -0.007, -0.020) }
    @Test func shaftF7At25() throws { try check(.shaft(.f, grade: 7), 25, -0.020, -0.041) }
    @Test func shaftK6At50() throws { try check(.shaft(.k, grade: 6), 50, 0.018, 0.002) }
    @Test func shaftN6At30() throws { try check(.shaft(.n, grade: 6), 30, 0.028, 0.015) }
    @Test func shaftP6At40() throws { try check(.shaft(.p, grade: 6), 40, 0.042, 0.026) }
    @Test func shaftS6At60() throws { try check(.shaft(.s, grade: 6), 60, 0.072, 0.053) }
    @Test func holeK7At20() throws { try check(.hole(.K, grade: 7), 20, 0.006, -0.015) }
    @Test func holeK8At20() throws { try check(.hole(.K, grade: 8), 20, 0.010, -0.023) }
    @Test func holeN7At20() throws { try check(.hole(.N, grade: 7), 20, -0.007, -0.028) }
    @Test func holeN9At20() throws { try check(.hole(.N, grade: 9), 20, 0, -0.052) }
    @Test func holeP7At20() throws { try check(.hole(.P, grade: 7), 20, -0.014, -0.035) }
    @Test func holeP8At20() throws { try check(.hole(.P, grade: 8), 20, -0.022, -0.055) }
    @Test func holeF8At10() throws { try check(.hole(.F, grade: 8), 10, 0.035, 0.013) }
    @Test func holeG7At10() throws { try check(.hole(.G, grade: 7), 10, 0.020, 0.005) }
    @Test func holeJS7At20() throws { try check(.hole(.JS, grade: 7), 20, 0.0105, -0.0105) }
    @Test func shaftJs6At20() throws { try check(.shaft(.js, grade: 6), 20, 0.0065, -0.0065) }

    @Test func smallSizesUseTheirOwnRule() throws {
        try check(.hole(.N, grade: 7), 2, -0.004, -0.014)
        try check(.hole(.K, grade: 7), 2, 0, -0.010)
        try check(.hole(.P, grade: 7), 2, -0.006, -0.016)
    }

    @Test func shaftH11At100() throws { try check(.shaft(.h, grade: 11), 100, 0, -0.220) }
    @Test func holeH11At500() throws { try check(.hole(.H, grade: 11), 500, 0.400, 0) }

    @Test func theRangeIsInclusiveAbove() throws {
        try check(.hole(.H, grade: 7), 18, 0.018, 0)
        try check(.hole(.H, grade: 7), 18.001, 0.021, 0)
    }

    @Test func outOfRangeIsRefused() {
        for size in [0.0, 500.001] {
            #expect(throws: DrawingRefusal(sentence: "ISO 286 fits are given here for sizes over 0 up to 500 mm.")) {
                try ISO286.limits(of: .hole(.H, grade: 7), size: size)
            }
        }
    }

    @Test func gradeOutOfRangeIsRefused() {
        for grade in [4, 12] {
            #expect(throws: DrawingRefusal(sentence: "ISO 286 grades here run from IT5 to IT11.")) {
                try ISO286.standardTolerance(grade: grade, size: 10)
            }
        }
    }

    @Test func everyITValueMatchesTheTable() throws {
        let uppers: [Double] = [3, 6, 10, 18, 30, 50, 80, 120, 180, 250, 315, 400, 500]
        let rows: [Int: [Double]] = [
            5: [4, 5, 6, 8, 9, 11, 13, 15, 18, 20, 23, 25, 27],
            6: [6, 8, 9, 11, 13, 16, 19, 22, 25, 29, 32, 36, 40],
            7: [10, 12, 15, 18, 21, 25, 30, 35, 40, 46, 52, 57, 63],
            8: [14, 18, 22, 27, 33, 39, 46, 54, 63, 72, 81, 89, 97],
            9: [25, 30, 36, 43, 52, 62, 74, 87, 100, 115, 130, 140, 155],
            10: [40, 48, 58, 70, 84, 100, 120, 140, 160, 185, 210, 230, 250],
            11: [60, 75, 90, 110, 130, 160, 190, 220, 250, 290, 320, 360, 400],
        ]
        for grade in 5...11 {
            for (index, size) in uppers.enumerated() {
                let value = try ISO286.standardTolerance(grade: grade, size: size)
                #expect(abs(value - rows[grade]![index] / 1000) < 1e-12)
            }
        }
    }
}
