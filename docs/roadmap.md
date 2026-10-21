# Roadmap

This page gathers the sub-projects in one place. Each sub-project has its own spec in `docs/superpowers/specs/`, which is binding,
and its own plans in `docs/superpowers/plans/`. The order below is the build order. Status is as of 2026-10-14.

| # | Sub-project | Spec | Status |
|---|---|---|---|
| 1–5 | Vertical slice: graph engine, OCCT kernel bridge, node editor, viewport, profile nodes | `2026-10-07-metalcreator-vertical-slice-design.md` | done |
| 6 | Constraint sketcher | `2026-10-08-constraint-sketcher-design.md` | done |
| — | Packaging | `2026-10-09-packaging-design.md` | done |
| — | Selection, groups, canvas comments | `2026-10-09-selection-groups-comments-design.md` | done |
| 7a | Data trees and feature patterns | `2026-10-10-patterns-trees-design.md` | done |
| 7b | Fields | `2026-10-12-fields-design.md` | done |
| 7c | Implicit geometry and lattices | `2026-10-13-implicit-lattices-design.md` | in progress (7c-4 is merged, 7d next): 7c-1, 7c-1g, 7c-2, 7c-3 and 7c-3f are merged; 7c-3's two known issues (trapped voids and thin walls, erratum M5) are resolved by 7c-3f (erratum D18: a blended skin join and robust checks; merged with the acceptance met: 0 voids, 0 thin walls; human check IL-10 pending); 7c-4 conformal (Cylindrical, Spherical and Face mappings on the three lattice nodes, Errata D20) is merged, its human checks IM-14 to IM-18 pending |
| 7d | Surface textures (knurl, hex, voronoi, embossed skins by displacement) | not written | after 7c |
| XP | Cross-platform: Linux and Windows on MetalUI's SDL backend | `2026-10-13-cross-platform-design.md` | xp-1 (everything but the viewport and OCCT) merged; then xp-2 (OCCT), xp-c (GPU meshing on SDL3) and xp-3 (the viewport on SDL GPU) |
| 8 | Variants and versions UI | not written (graph parameters are already designed for it, slice spec §4.1) | after 7 |
| 9 | **Class A surfaces** | not written | after 8 (added 2026-10-14) |

## 9. Class A surfaces (added 2026-10-14, not yet designed)

The aim is to model the curvature-continuous freeform surfaces used for visible product skins: consumer products,
automotive and industrial design. They are exact B-rep, so they export to STEP like the rest of the B-rep world, unlike 7c's
meshes. The scope is settled by a brainstorm before its spec is written. The likely ingredients are:

- **NURBS surface nodes.** Surfaces from curves and from control nets: loft, sweep, network/Gordon and fill or patch. They
  carry explicit G0/G1/G2 (and G3 where OCCT supports it) continuity constraints to neighbouring faces. They are built on
  OCCT's `GeomFill`, `BRepFill` and `GeomPlate`, behind the `Kernel` protocol as always.
- **Control-point editing.** Handles in the viewport for a surface's control net and its weights, as parametric graph data,
  so the edits stay in the history.
- **Surface-quality analysis in the viewport.** Zebra stripes and reflection lines, highlight lines, Gaussian and mean
  curvature maps, curvature combs on edges and sections, and deviation and continuity readouts across edges. The curvature
  maps reuse 7b's tint and legend.
- **Continuity checks** as warnings on the node: "G2 not met along edge …, max deviation …".
- **Questions for the brainstorm:**
  - how much stays parametric and how much is direct editing;
  - the degree and span limits;
  - whether G3 and curvature-continuous fillets (blends) are in scope;
  - how this interacts with 7d textures and 7c implicits;
  - what "Class A" acceptance means for this app, for example which analysis must pass on a reference part.

It depends on the B-rep kernel only. It does not need 7c or 7d, and it could move earlier if it matters more than variants.
