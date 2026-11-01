# G2 surfacing — design

Status: draft for review, 2026-11-01. The user asked "do we currently have the ability to make all levels of G surfaces?",
was told G0 and G1 yes, G2 only inside one face, G3 no, and asked for this design, skipping the questions ("yes lets skip
the questions"). Every decision below not quoted from the user is the designer's call and is marked **(call)**.

## Intent

The user shapes parts and checks them with zebra stripes (spec `2026-11-01-zebra-design.md`) "to insure they flow as
expected". Today every blend we make stops at G1: zebra shows a kink at each fillet's edge, at each implicit smooth union
and at every joint of a sketch profile. The user cannot make a joint whose stripes flow straight through. This work adds
the tools that make curvature-continuous (G2) joints, and G3 where it costs nothing extra, and a way to read a joint's
continuity as a number, not only by eye.

## How the reference products do it (research, 2026-11-01)

- **Fusion 360, Fillet:** Continuity Tangent (G1) or Curvature (G2); Tangency Weight 0.1 to 2.0, default 1.0; corner
  type Rolling Ball or Setback. Loft end conditions Connected (G0), Direction, Tangent (G1), Smooth (G2), each Tangent and
  Smooth needing a body edge or face as the profile. Sketch fit-point splines (degree 5) and a Curvature (G2) constraint.
- **SOLIDWORKS, Fillet profile:** Circular, Conic Rho, Conic Radius, Curvature continuous (a spline cross-section in place
  of the circle). Boundary and loft: Curvature to Face, with a tangent length.
- **OpenCascade 7.9:** `BRepFilletAPI_MakeFillet` makes circular sections only (its `ChFi3d_FilletShape` values are three
  representations of the circle), so it is G1 at both seams. `BRepOffsetAPI_MakeFilling` takes G0, G1 or G2 constraints
  along edges but is a least-squares plate fit (default curvature tolerance 0.1) and silently drops constraints it can't
  meet. `BRepOffsetAPI_ThruSections` (our loft) has no end conditions. No OCCT tool makes a curvature-continuous fillet.
- **Implicit smooth minimum (Quilez):** quadratic is C1 (G1 isosurfaces), cubic C2 (G2), and a quartic he calls C3 (it is C2 at the blend's edge; see G-a); each is at or
  below `min(a, b)` and 1-Lipschitz when its inputs are.

## The work, in order **(call)**

This is four projects of very different size. This design decides the first two in full; the last two get their own design
documents when they come up, with the decisions recorded under "Later".

1. **G-a: Implicit blend continuity** (small): G1, G2 or G3 smooth union, subtract, intersect and lattice skin.
2. **G-b: Curvature-continuous fillets and a continuity readout** (the main piece): a G2 option on the Fillet node, and
   Measure showing an edge's continuity.
3. **Later, G-c: sketch splines** (a sketcher project: entity, solver, tools, profile pipeline).
4. **Later, G-d: loft end conditions** (needs G-c's curves and a face-backed profile).

## Goals

1. Implicit Union, Subtract and Intersect, and the TPMS, Strut Lattice and Voronoi Lattice nodes' skin `blend`, offer
   **Continuity: G1 / G2 / G3**. The blend width means what it means today: the range of `|a − b|` over which the two
   shapes blend.
2. The Fillet node offers **Continuity: Tangent (G1) / Curvature (G2)** and, for G2, **Tangency weight** (0.1 to 2.0,
   default 1.0), as Fusion does. The radius keeps its meaning: the G2 fillet meets the two faces on the same lines a
   circular fillet of that radius would touch, and only the cross-section between them changes.
3. Picks and downstream nodes survive switching a fillet between G1 and G2: the faces keep the same tags.
4. Measure, with one edge picked between two faces, shows that edge's continuity: "G0", "G1" or "G2", with the worst angle
   gap and the worst curvature gap along it.
5. macOS, Linux and Windows, like every kernel and implicit feature.

## Non-goals

- G3 fillets, conic (rho) fillets, variable-radius fillets, setback corners, asymmetric fillets.
- Chamfers (G0 by nature).
- A G2 option on the field Smooth Blend node (fields are numbers, not surfaces). It keeps the quadratic.
- Surface patch, fill and boundary nodes.
- Curvature maps and curvature combs. Zebra plus the Measure readout cover reading a joint.

## Anti-goals (a failure even if it works)

- **A "G2" fillet that isn't.** If the readout or zebra shows a curvature jump at a seam of a G2 fillet, the feature has
  failed, whatever the label says. Where G2 can't be reached (below), the node says so; it never silently gives G1.
- **Old files changing shape.** A file saved before this work opens and evaluates to the same geometry.
- **A fragile fillet.** A G2 fillet that fails where the G1 fillet of the same radius succeeds is acceptable only with a
  message naming the reason; a G2 fillet that returns an invalid solid is not acceptable (the `BRepCheck_Analyzer` rule
  applies as to every blend).

## G-a: implicit blend continuity

**Formulas** (width `k`, `h = max(k − |a − b|, 0) / k`; `k = 0` is a plain min), keeping today's width meaning:

| Continuity | Smooth minimum | Deepest dip (at `a = b`) |
|---|---|---|
| G1 (today) | `min(a, b) − h² · k / 4` | `k / 4` |
| G2 | `min(a, b) − h³ · k / 6` | `k / 6` |
| G3 | `min(a, b) − h⁴ (h² − 6h + 10) · k / 32` | `5k / 32` |

G1 and G2 are Quilez's polynomial smooth minimums without his rescaling of `k`. G3 is not his quartic (that one,
`h³(4 − h)k/16`, starts as `h³` and so is only C2 at the blend's edge): it is the smooth minimum whose second derivative is
the kernel `(15/16)(1 − s²)²` over `s = |a − b|/k` (the same construction gives the G1 and G2 rows from a constant and a tent
kernel), so it vanishes to fourth order at the edge and has no odd derivative at `a = b`: C3 (erratum 2026-11-01, found by
G-a Task 1). All three use the same `k`, so the blend starts at the same `|a − b|`
for every continuity and the joint is slightly shallower for G2 (**call**: equal reach rather than equal depth, so
switching continuity never moves where the blend starts on the part). Intersect and subtract use the same function as
today (`−smin(−a, −b)`, `−smin(−a, b)`).

- **Continuity is structural:** `ImplicitSolid.union`, `.subtract` and `.intersect` carry a `BlendContinuity` (`g1`,
  `g2`, `g3`) beside their `Grading`, so the generated GPU source differs by continuity (a function per continuity in the
  MSL library and its HLSL twin, every float `precise` as D21 requires) and numbers stay in buffers.
- **Bounds:** the lipschitz term for a graded blend (`blend.slope / 4` today) becomes the continuity's own bound on
  `∂(dip)/∂k`, derived and pinned by a test that samples it (the cubic's is 1/6, G3's 5/32 by the same rule; the test confirms each by sampling).
  `exactReach` is unchanged.
- **The node:** Union, Subtract and Intersect get a `continuity` integer socket (segmented: G1, G2, G3), shown with the
  blend. The lattice nodes get the same beside `blend`; on Strut Lattice the one socket also governs its `node blend` (the
  rounding where struts meet, today a quadratic smooth minimum of its own), so the strut lattice value carries a
  `BlendContinuity` too (**call**: strut joints are where zebra gets read, and one setting per node keeps the inspector
  simple).
- **Defaults and old files (call):** a new node defaults to **G2** (the reason the user asked); each of these node types
  goes up one `typeVersion`, and its `migrate` stores G1 in a node saved before, so old files keep their shape. TPMS,
  Strut Lattice and Voronoi Lattice go from 2 to 3 (their 2's migration still stores blend 0 first).
- **Tests:** the CPU formulas against closed forms (value and the first, second and third derivative continuity at
  `|a − b| = k` for each continuity), the GPU agreement suites with a G2 and a G3 fixture, `MetalSourceDigests`
  re-recorded, `HLSLSourceTests` unchanged in rule, migration of a pre-G-a file, and a meshed G2 union whose zebra (the
  CPU twin `ZebraBand` over the mesh normals) has no kink a G1 union has.

## G-b: curvature-continuous fillets

### Behaviour

- Fillet node: `continuity` (segmented Tangent / Curvature, default **Tangent**, **call**: matching Fusion's default and
  needing no migration, since a missing input reads Tangent) and `tangencyWeight` (number, 0.1 to 2.0, default 1.0, shown
  only for Curvature through `NodeDefinition.inspector(for:)`). The radius handle works as today.
- A G2 fillet has the same faces as the G1 fillet of the same radius and edges: same count, same tags
  (`TopoRole.blend(sourceEdge:)`), same spring edges on the neighbouring faces. Only the blend faces' surfaces differ.
- **Which seams are promised G2 (call):** the spring seams, where a blend face meets an original face. A seam between two
  strips of one tangent chain (a line running tangent into an arc, say) can only be as continuous as the faces under it,
  which today are G1, so it is not promised and not warned about. A strip's run-out at an open end of a chain is a crease
  and is not checked either.
- **Checked on every evaluation (call):** after building, the kernel samples every promised seam with
  `Kernel.continuity`'s sampler. A strip seam out of tolerance makes the blend fail like an invalid one ("The fillet can't be
  made curvature continuous at this radius."), and `largestValidBlend` searches for the largest radius that passes both the
  validity check and this one. The cost is measured by the benchmark row.
- **Where G2 can't be reached:** a corner patch where three or more fillets meet at a vertex is refilled to meet the new
  strips (the circular corner can't be kept: the strips' ends no longer match it). If the refill misses G2 there but meets G1
  (angle 0.01°), the node warns "N fillet corners are tangent only (G1)." A corner that misses G1 makes the G2 fillet fail
  ("The fillet's corners can't be made smooth at this radius."): a crease is never returned (erratum 2026-11-01, found by the
  spike review). The strips between corners are always G2 or the node fails.
- Failure follows the existing blend rules: an invalid result is never returned, and the message names the largest radius
  that works (`largestValidBlend`, now searched with the G2 profile).

### Construction (call)

OpenCascade makes the topology; we replace the blend surfaces. Steps, all inside the shim under `OCCTKernel.serialized`:

1. Build the circular fillet with `BRepFilletAPI_MakeFillet` as today (history, tags and the validity check as today).
2. For each blend strip face (a face generated from an edge), sample cross-sections along it. At each section, the two
   ends are the points where the strip meets its neighbouring faces (on the spring edges). At each end, read the
   neighbour's position, its tangent direction across the spring edge (in the neighbour's tangent plane, perpendicular to
   the spring edge, pointing into the blend) and its normal curvature in that direction.
3. Sections are placed densely enough that the skinned surface meets the tolerances between them (the count is chosen per
   strip, adaptively, by measuring; a strip that can't meet them fails), and the springs' pcurves follow the same
   parametrization as the sections. Make each cross-section a **quintic Bézier** that matches position, tangent direction and curvature at both ends (G2
   Hermite). Its two end tangent lengths are `w × d`, where `w` is the tangency weight and `d` is the circular fillet's
   own end-tangent length for that section (so weight 1 is close to the circle's proportions); the remaining freedom
   (the component of each end's second derivative along the tangent) is zero.
4. Skin the sections into one B-spline surface per strip (quintic across, cubic or higher along), with its two boundary
   curves along the existing spring edges, and replace the strip's surface in the solid, keeping its edges (new pcurves).
5. Each corner patch (a face generated from a vertex) is rebuilt with `BRepOffsetAPI_MakeFilling`, its boundary edges
   constrained G2 to the new strips and original faces, the circular corner as the initial surface. If it misses the
   curvature tolerance, it is rebuilt with G1 constraints and counted for the warning; if that misses the angle tolerance,
   the fillet fails (above).
6. `BRepCheck_Analyzer`, as for every blend.

Tolerances the result must meet along every G2 seam (checked at sample points by the tests and the readout): position
1e-4 mm, angle 0.01°, curvature within 1 % of the larger curvature or 1e-4 /mm, whichever is larger.

**Left to the builder:** the number of sections and how the skinning interpolates them (enough to meet the tolerances;
measure the cost), how a strip's ends meet a corner patch or an open end, and the pcurve work. A spike that builds the
strip construction on a plate edge and a box's three-edge corner is the first task of G-b. **If the spike can't meet the
tolerances, the G2 fillet stops there** and comes back to the user with the measurements (**call**: no looser tolerance and
no plate-fit fallback, either would break the first anti-goal). G-a and the Continuity readout (with `Kernel.continuity`)
do not depend on the spike and ship either way; plan them as their own track, and the `FilletProfile` change only once the
spike passes.

### Kernel

- `Kernel.fillet(_:edges:radius:profile:tag:)` with `FilletProfile` (`.circular`, `.curvatureContinuous(weight:)`);
  the old requirement forwards `.circular`. `FakeKernel` gives the same faces and tags for both profiles (it has no
  surfaces to bend).
- `Kernel.continuity(along:of:)` for one edge between two faces: samples the edge and returns the worst position gap, the
  worst angle between the faces' normals, the worst curvature gap (normal curvature across the edge, relative as above),
  and the class (G0, G1 or G2 against the tolerances above). OCCT: `BRepLProp_SLProps` on both faces at each sample.
  `FakeKernel` answers for its boxes (G0 at every edge).

### Measure readout

With one edge picked that lies between two faces, the Measure panel adds a **Continuity** row: "G2", "G1 · curvature jump
38 %" or "G0 · 12.0°" (**call**: the gap shown is the one that keeps it below the next class). Not for a section edge or a
mesh. It is a view-only value like the rest of Measure: no command, no undo step.

### Tests

- The quintic Hermite section against its end conditions (position, tangent, curvature) and the weight's effect.
- On OCCT: a plate edge, a box's three-edge corner, a fillet next to a cylinder (non-zero neighbour curvature), and the
  bracket's fillets: G2 strips meet the tolerances at every seam (`Kernel.continuity`), faces and tags equal the G1 fillet's,
  the solid is valid, and switching G1 ↔ G2 keeps a downstream pick.
- A refused G2 radius names the largest that works; a corner that can't reach G2 warns with the count.
- A benchmark row: the bracket's fillets G1 against G2 (edit to preview), recorded like the others.
- Human checks: a new group comparing a G1 and a G2 fillet under zebra, the weight's effect, the corner warning and the
  Continuity row.

## Later

- **G-c, sketch splines:** a spline entity (degree-5 fit-point splines with tangent and curvature handles, as Fusion), a
  curvature (G2) constraint at a joint, `Segment2D` gaining a B-spline case through the profile pipeline and the shim.
  Its own design.
- **G-d, loft end conditions:** Tangent (G1) and Curvature (G2) at a loft's ends against a face, with a weight, as Fusion;
  needs a profile that knows its face and our own end-constrained skinning (ThruSections has none). Its own design.
- G3 fillets (a degree-7 section), conic fillets, setback corners.
- Mesh import (from the zebra design's Later).
