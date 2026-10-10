/// The 0.1 mm grid `OCCTKernel.largestValidBlend` searches and the messages that report it.
enum BlendGrid {
    /// One step of the grid, in millimetres.
    static let step = 0.1

    /// The most tenths of a millimetre a search starts from, so a huge size can't overflow `Int`.
    static let mostTenths = 1_000_000

    /// Slack for products like `0.3 * 10` that land a hair above a whole number.
    private static let slack = 1e-9

    /// The first count of tenths of a millimetre at or above `size` (0 for a size that is not positive): the search
    /// tries only counts below it, so it names a size below the one asked for. A size on the grid is exact even when
    /// float arithmetic put it a hair over (`0.1 + 0.2`, which `ceil` alone would round up to 4 tenths). The slack also
    /// means a size within 1e-9 above a grid value counts as that value, so for an off-grid size the maximum named is
    /// conservative: it can be a step below a size that would still build.
    static func firstFailingTenths(for size: Double) -> Int {
        // Not a positive number (NaN, minus infinity, zero, negative): no size to try, and `Int(.nan)` would trap.
        guard size > 0 else { return 0 }
        return Int(min((size * 10 - slack).rounded(.up), Double(mostTenths)))
    }

    /// Whether a search for `size` tries the smallest grid size, 0.1 mm. When it didn't, finding none says nothing
    /// about 0.1 mm.
    static func triesSmallest(below size: Double) -> Bool {
        firstFailingTenths(for: size) > 1
    }
}
