import CreatorGeometry
import CreatorImplicit

/// What the three lattice nodes output (implicit spec §3.4, Errata D18): the lattice cut to the region, and with a skin the region's own
/// wall as well, `Shell(region, inward, skin) ∪ (lattice ∩ Offset(region, −skin))`, which turns lightweighting into one node. The
/// union is the kernel's smooth union of radius `blend`, so a sheet that meets the skin tangentially leaves no wedge narrower than a
/// mesh cell; a blend of 0 is the sharp union.
enum LatticeFill {
    /// - Parameters:
    ///   - region: the solid to fill.
    ///   - lattice: the lattice, already cut to the region's box.
    ///   - skin: the wall thickness in millimetres, 0 for none.
    ///   - blend: the radius in millimetres of the smooth union that joins the skin and the lattice. It has no effect without a skin.
    static func fill(region: ImplicitSolid, lattice: ImplicitSolid, skin: Double, blend: Double) -> ImplicitSolid {
        guard skin > 0 else { return .intersect([region, lattice], blend: .constant(0)) }
        let wall = ImplicitSolid.shell(region, thickness: .constant(skin), side: .inward)
        let inside = ImplicitSolid.offset(region, distance: .constant(-skin))
        return .union([wall, .intersect([lattice, inside], blend: .constant(0))], blend: .constant(blend))
    }
}
