/// The kernel's side of NS-5 (back to solids: Sew, Thicken, Offset Surface, Cap Planar Holes and Split Solid).

/// Which way a Thicken grows from its sheet (R3): `front` toward the sheet's normal, `back` against it, `both` half each way.
public enum ThickenSide: Int, Sendable, CaseIterable {
    case front = 0
    case back = 1
    case both = 2
}

/// What sewing made (R6). `body` is one value holding every solid and sheet of the result.
public struct SewResult: Sendable {
    public var body: Solid
    /// The closed solids in `body`.
    public var solids: Int
    /// The connected open pieces in `body` (each open shell, each loose face, each closed shell that made no valid solid).
    public var sheets: Int
    /// Closed shells that made no valid solid and stay sheets (counted in `sheets` too).
    public var unclosable: Int

    public init(body: Solid, solids: Int, sheets: Int, unclosable: Int) {
        self.body = body
        self.solids = solids
        self.sheets = sheets
        self.unclosable = unclosable
    }
}

/// What capping a sheet's flat holes made (R12).
public struct CapResult: Sendable {
    public var body: Solid
    /// The caps added.
    public var capped: Int
    /// The free loops that aren't flat and stay open.
    public var notFlat: Int

    public init(body: Solid, capped: Int, notFlat: Int) {
        self.body = body
        self.capped = capped
        self.notFlat = notFlat
    }
}

/// A solid divided by tools (R13): its pieces, ordered by `SheetPieces.ordered`, and the warnings the division gave.
public struct SolidSplit: Sendable {
    public var pieces: [Solid]
    public var warnings: [String]

    public init(pieces: [Solid], warnings: [String]) {
        self.pieces = pieces
        self.warnings = warnings
    }
}

extension Solid {
    /// Whether some face is not on an open shell (R17): the value holds a closed solid, perhaps beside sheets. A closed bare shell's
    /// faces are on an open shell, so it doesn't count.
    public var holdsClosedSolid: Bool { topology.faces.contains { !$0.isOnOpenShell } }
}

extension Kernel {
    public func sewn(_ bodies: [Solid], tolerance: Double, tag: NodeTag) async throws -> SewResult {
        throw KernelError.unsupported("sewing")
    }

    public func offsetSurface(_ sheet: Solid, distance: Double, tag: NodeTag) async throws -> Solid {
        throw KernelError.unsupported("offsetting surfaces")
    }

    public func thickened(_ sheet: Solid, distance: Double, side: ThickenSide, tag: NodeTag) async throws -> Solid {
        throw KernelError.unsupported("thickening")
    }

    public func cappingPlanarHoles(_ sheet: Solid, tag: NodeTag) async throws -> CapResult {
        throw KernelError.unsupported("capping holes")
    }

    public func splitSolid(_ solid: Solid, by tools: [Solid], tag: NodeTag) async throws -> SolidSplit {
        throw KernelError.unsupported("splitting solids")
    }
}
