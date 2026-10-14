import CreatorGraph
import CreatorImplicit
import CreatorKernel

/// A baked solid's distance is exact only within its band (implicit spec §4.4); a shell or an offset that reaches past it is wrong
/// beyond it, so the node says so.
enum ImplicitReach {
    static func warnings(for solid: ImplicitSolid, reachedBy distance: Double) -> [String] {
        let reach = solid.exactReach
        guard reach.isFinite, distance > reach else { return [] }
        let (asked, measured) = (distance.millimetreText(locale: .messages), reach.millimetreText(locale: .messages))
        let text = "The distance reaches \(asked) mm from the surface, past the \(measured) mm To Implicit measured exactly, "
            + "so it may be inaccurate."
        return [text]
    }
}
