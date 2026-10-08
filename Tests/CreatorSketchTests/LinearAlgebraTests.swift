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
        // These leave a nonzero rounding residue in the dependent column.
        #expect(HouseholderQR.leastSquares(DenseMatrix([[1, 2], [2, 4], [3, 6]], columns: 2), [1, 2, 3]) == nil)
        #expect(HouseholderQR.leastSquares(DenseMatrix([[0.1, 0.3], [0.2, 0.6], [0.3, 0.9]], columns: 2), [1, 2, 3]) == nil)
        #expect(HouseholderQR.leastSquares(DenseMatrix([[1e6, 2e6], [2e6, 4e6], [3e6, 6e6]], columns: 2), [1, 2, 3]) == nil)
        #expect(HouseholderQR.leastSquares(DenseMatrix([[0, 0], [0, 0]], columns: 2), [1, 2]) == nil)
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

    @Test(arguments: [
        // Larger-norm column second: the pivot swap runs.
        [[1.0, 0], [0, 5], [0, 0]],
        // Rank 2 with a zero first column, in 3 dimensions.
        [[0.0, 1, 1], [0, 2, 0], [0, 0, 3]],
        [[1.0, 2, 3], [4, 5, 6], [7, 8, 9]],
        [[1.0, 2], [1, 2], [0, 0]],
    ])
    func rangeBasisHasOrthonormalColumnsThatReproduceTheMatrix(rows: [[Double]]) {
        let a = DenseMatrix(rows, columns: rows[0].count)
        let qr = RankRevealingQR(a)
        let q = qr.rangeBasis
        for p in 0..<qr.rank {
            for r in 0..<qr.rank {
                var dot = 0.0
                for i in 0..<a.rows { dot += q[i, p] * q[i, r] }
                #expect(isClose(dot, p == r ? 1 : 0, tolerance: 1e-12))
            }
        }
        // Each original column equals its projection onto the basis.
        for j in 0..<a.columns {
            var projection = Array(repeating: 0.0, count: a.rows)
            for p in 0..<qr.rank {
                var coefficient = 0.0
                for i in 0..<a.rows { coefficient += q[i, p] * a[i, j] }
                for i in 0..<a.rows { projection[i] += coefficient * q[i, p] }
            }
            for i in 0..<a.rows { #expect(isClose(projection[i], a[i, j], tolerance: 1e-12)) }
        }
    }

    @Test func rankOfTheSwapCasesIsCorrect() {
        #expect(RankRevealingQR(DenseMatrix([[1, 0], [0, 5], [0, 0]], columns: 2)).rank == 2)
        #expect(RankRevealingQR(DenseMatrix([[0, 1, 1], [0, 2, 0], [0, 0, 3]], columns: 3)).rank == 2)
        #expect(RankRevealingQR(DenseMatrix([[1, 2, 3], [4, 5, 6], [7, 8, 9]], columns: 3)).rank == 2)
    }
}
