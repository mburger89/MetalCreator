import CreatorGeometry
import CreatorGraph

/// An implicit solid (implicit spec §2.1): an immutable tree whose value at a point is a signed distance in millimetres, negative
/// inside and zero on the surface (the sign of fields spec D5). Every node has `bounds`, a box that contains its surface, and
/// `lipschitz`, a constant L ≥ 1 with |f(a) − f(b)| ≤ L · |a − b|. The sparse evaluator divides by L before pruning
/// (implicit spec §4.2), so an overestimate costs speed, never correctness. `ImplicitSolid+Evaluation` evaluates it, and
/// `ImplicitCompiler` turns it into Metal.
///
/// Adding a case means adding it to `children`, `bounds`, `lipschitz`, `recipe`, the CPU evaluator and the compiler, none of
/// which has a `default`, so the compiler lists the places.
public indirect enum ImplicitSolid: Hashable, Sendable {
    // MARK: Primitives (exact distances, lipschitz 1)

    /// A ball about the origin.
    case sphere(radius: Double)
    /// A box about the origin with rounded edges: `halfSize` is half its extent on each axis, `cornerRadius` ≤ the smallest half size.
    case box(halfSize: Vector3, cornerRadius: Double)
    /// A cylinder about the origin with its axis along Z.
    case cylinder(radius: Double, halfHeight: Double)

    // MARK: Moves

    /// The solid seen through a rigid move (Place): its value at p is the child's at `move.toLocal(p)`. Exact.
    case moved(ImplicitSolid, RigidMove)

    // MARK: Combining

    /// The first child with every other child cut away; with one child, that child. `blend` rounds the joins (the polynomial
    /// smooth minimum); constant 0 is sharp.
    case subtract([ImplicitSolid], blend: Grading)
    case union([ImplicitSolid], blend: Grading)
    case intersect([ImplicitSolid], blend: Grading)
    /// The surface moved outwards by `distance` (inwards when negative).
    case offset(ImplicitSolid, distance: Grading)
    /// A wall of `thickness` on `side` of the surface.
    case shell(ImplicitSolid, thickness: Grading, side: ShellSide)

    // MARK: Conversions

    /// A solid's signed distance baked on a grid (To Implicit, implicit spec §4.4). `label` names the solid in `description`.
    case baked(DistanceBlocks, label: String)
    /// Where `grading.field` is below `level`: the value is (field − level) ÷ `maxSlope`, so lipschitz is 1 when the slope bound is
    /// honest (Isosurface). `region` bounds the surface.
    case isosurface(Grading, level: Double, maxSlope: Double, region: BoundingBox)

    // MARK: Lattices (implicit spec §3.4; each is cut to its region's box, the lattice nodes intersect it with the region itself)

    /// A triply periodic minimal surface, a sheet or a network.
    case tpms(TPMSLattice)
}
