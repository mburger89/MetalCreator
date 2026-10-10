import Testing
@testable import CreatorOCCT

/// The search's grid: which sizes it tries, and when "even by 0.1 mm" is true.
struct BlendGridTests {
    @Test(arguments: [(3.0, 30), (2.5, 25), (0.7, 7), (0.1, 1), (0.15, 2), (0.05, 1), (1.25, 13)])
    func theFirstFailingCountIsTheSizeInTenthsRoundedUp(size: Double, tenths: Int) {
        #expect(BlendGrid.firstFailingTenths(for: size) == tenths)
    }

    /// `0.1 + 0.2` is 0.30000000000000004: `ceil(size * 10)` would give 4 and the search would try 0.3 mm, the size asked.
    @Test func aSizeAHairOverTheGridIsStillOnIt() {
        #expect(0.1 + 0.2 != 0.3)
        #expect(BlendGrid.firstFailingTenths(for: 0.1 + 0.2) == 3)
        #expect(BlendGrid.firstFailingTenths(for: 2.3 + 0.1) == 24)
    }

    @Test func aTinyOrHugeSizeStaysInRange() {
        #expect(BlendGrid.firstFailingTenths(for: 1e-12) == 0)
        #expect(BlendGrid.firstFailingTenths(for: .greatestFiniteMagnitude) == BlendGrid.mostTenths)
    }

    @Test func theSmallestSizeIsTriedOnlyBelowASizeAboveIt() {
        #expect(!BlendGrid.triesSmallest(below: 0.1))
        #expect(!BlendGrid.triesSmallest(below: 0.05))
        #expect(BlendGrid.triesSmallest(below: 0.15))
        #expect(BlendGrid.triesSmallest(below: 3))
    }
}
