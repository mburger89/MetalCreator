import Testing
@testable import CreatorSketch

struct LinearAlgebraTests {
    @Test func leastSquaresSolvesASquareSystemExactly() throws {
        let a = DenseMatrix([[2, 1], [1, 3]], columns: 2)
        let x = try #require(HouseholderQR.leastSquares(a, [3, 5]))
        #expect(isClose(x[0], 0.8, tolerance: 1e-12))
        #expect(isClose(x[1], 1.4, tolerance: 1e-12))
    }

    @Test func leastSquaresFitsAnOverdeterminedSystem() throws {
        // Fit y = c to 1, 2, 3, 6: the mean, 3.
        let a = DenseMatrix([[1], [1], [1], [1]], columns: 1)
        let x = try #require(HouseholderQR.leastSquares(a, [1, 2, 3, 6]))
        #expect(isClose(x[0], 3, tolerance: 1e-12))
    }

    @Test func leastSquaresRejectsARankDeficientMatrix() {
        #expect(HouseholderQR.leastSquares(DenseMatrix([[1, 2], [2, 4]], columns: 2), [1, 2]) == nil)
    }

    @Test func rankCountsIndependentRows() {
        #expect(RankRevealingQR(DenseMatrix([[1, 0, 0], [0, 1, 0], [1, 1, 0]], columns: 3)).rank == 2)
        #expect(RankRevealingQR(DenseMatrix([[1, 2], [3, 4]], columns: 2)).rank == 2)
        #expect(RankRevealingQR(DenseMatrix([[0, 0], [0, 0]], columns: 2)).rank == 0)
        #expect(RankRevealingQR(DenseMatrix(rows: 3, columns: 0)).rank == 0)
    }

    @Test func rangeBasisIsOrthonormalAndSpansTheColumns() {
        // Columns (1,1,0) and (2,2,0) span the line through (1,1,0).
        let qr = RankRevealingQR(DenseMatrix([[1, 2], [1, 2], [0, 0]], columns: 2))
        #expect(qr.rank == 1)
        #expect(isClose(qr.outsideSquaredNorm(ofUnitVector: 0), 0.5, tolerance: 1e-12))
        #expect(isClose(qr.outsideSquaredNorm(ofUnitVector: 1), 0.5, tolerance: 1e-12))
        #expect(isClose(qr.outsideSquaredNorm(ofUnitVector: 2), 1, tolerance: 1e-12))
    }
}
