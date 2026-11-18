import CreatorGraph
import CreatorKernel

/// The refusals of nodes that need a closed solid, where a sheet (an open surface) wouldn't do (NURBS spec).
enum ClosedSolidCheck {
    /// Fillet and Chamfer: the edge set's solid must be closed.
    static func requireForBlend(_ solid: Solid, _ name: String) throws {
        guard !solid.hasOpenShell else {
            throw NodeError.invalidValue("\(name) needs a closed solid; Thicken or Sew the sheet first.")
        }
    }

    /// An input that takes closed solids only, named in curly quotes.
    static func requireInput(_ solid: Solid, _ input: String) throws {
        guard !solid.hasOpenShell else {
            throw NodeError.invalidValue("“\(input)” is an open surface; use Split or Trim, or Thicken or Sew it first.")
        }
    }
}
