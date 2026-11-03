# G-c: Sketch splines — design

Status: written 2026-11-02 without a question round (the user: "Let's skip the questions"). It follows the decisions recorded under
"Later" in `2026-11-01-g2-surfacing-design.md` (degree-5 fit-point splines with tangent and curvature handles, as Fusion; a
curvature (G2) constraint at a joint; `Segment2D` gaining a B-spline case through the profile pipeline and the shim). Everything else
here is marked **(call)**: the designer's decision, open to the user's correction.

## Intent

The user shapes parts and checks them with zebra stripes "to insure they flow as expected". A G2 fillet now makes a joint whose
stripes flow; a sketch still can't. Every profile is lines and arcs, so every joint between them is at best tangent (G1): the extruded
side faces kink under zebra at each joint, and a loft or revolve inherits the kink. Splines let the user draw a curve that bends as
they want, and the curvature constraint lets a spline meet a line, an arc or another spline with stripes that flow straight through.
The continuity readout (Measure) then reads the extruded joint as G2.

## Goals

1. A **Spline** sketch entity: a degree-5 curve through two or more fit points, C2 (curvature continuous) along its whole length.
2. **Handles** at each fit point, as Fusion's: a tangent handle (direction and length) and a curvature handle. A handle is *automatic*
   until the user drags it or a constraint uses it; then it is *active* (the solver's) until released.
3. Constraints at a spline's ends: the existing **Tangent**, and a new **Curvature (G2)** constraint, between a spline end and a
   line, an arc or another spline end that shares the point. Fit points take every point constraint and dimension (they are points).
4. Splines flow through regions, profiles, Extrude, Revolve, Loft and the rest of the pipeline as exact B-splines (no polyline
   approximation reaches the kernel), on every platform.
5. Mirror and Pattern copy splines; Delete, Construction (X), undo names, saving and the warm start handle them.

## Non-goals

- Control-point (CV) splines, conics, splines of other degrees, closed (periodic) splines. **(call)**: a closed shape is two splines
  joined G2 at both ends.
- Point-on-spline, trim, extend and fillet on splines: refused with a message naming the spline ("Trim doesn't work on splines
  yet."). **(call)**
- Dimensions on the curve itself (arc length, a curvature value): later. Fit points take point dimensions now. **(call)**
- Projecting a model's B-spline edges into a sketch, and Curve Pattern along a spline edge (they still refuse, in their own words).
- Loft end conditions (G-d, its own design).

## Anti-goals (a failure even if it works)

- A spline that changes shape when nothing about it changed (an unrelated edit, a re-solve, a reopened file).
- A curve drawn in the sketch that differs from the edge the kernel makes from it.
- A joint the user constrained G2 that reads G1 in the continuity readout after an extrude.
- Fit points that fight the user: dragging one moves only the curve near it noticeably, never flips the whole spline.

## The curve (decided maths)

A spline with fit points `P_0 … P_n` (n ≥ 1) is a chain of quintic Hermite spans. Span `i` runs from `P_i` to `P_{i+1}` over a
parameter interval of length `h_i = |P_{i+1} − P_i|` (chord length) **(call)**. At every fit point the curve has a first derivative
`T_i` and a second derivative `A_i` (with respect to that chord-scaled parameter), shared by the two spans that meet there, so the
curve is C2.

- **Active handles** fix `T_i` (the tangent handle: its direction is the tangent, its length the "weight") and/or `A_i` (the curvature
  handle) as solver unknowns: two columns each.
- **Automatic handles** are filled by one linear solve over the whole spline: the C4 quintic interpolant, i.e. the third and fourth
  derivatives continuous at every interior fit point with an automatic handle, and at an end with automatic handles the natural
  conditions (third and fourth derivatives zero there). A point with one handle active and the other automatic keeps only the lower
  condition (interior: third derivative continuous; end: third derivative zero). With all handles automatic this is the smoothest
  quintic through the points; a two-point spline with automatic handles is the straight chord.
  The system depends on the fit points (through `h_i`) and the active handles; it is solved after every solve and whenever the curve
  is drawn, never stored.
- Curvature of the curve at a fit point is `κ = (T × A) / |T|³` (signed, 2D cross product).
- The exact curve as a B-spline: each span's Hermite data converts to one quintic Bézier; the chain is a degree-5 B-spline with
  interior knots of multiplicity 3 (C2) at the cumulative `h`. This is `Segment2D`'s new case, and what the kernel builds.

**Why the handles are columns only when active:** a spline with all-automatic handles is fully defined by its fit points, as in
Fusion, so a fully constrained sketch stays fully constrained (no free handle DOF). Only constraints at fit points with active
handles touch handle columns, and those quantities (direction, curvature) are explicit in the columns, so every residual and its
Jacobian stay analytic and local, as the solver requires.

## Behaviour

- **Drawing:** the Spline tool (key **S**, toolbar "Spline") places fit points with each click, previewing the spline through the
  pointer; Return, a double click or clicking the last point again finishes; Esc finishes too (keeping two or more points, discarding
  one). A click on an existing point or curve end reuses it (shared endpoint), as lines do. Starting or ending at the end of a line or
  arc infers **Tangent** there (shown with the inference glyph; ⌘ suppresses), as a line leaving an arc does. **(call)**
- **Handles:** a selected spline shows its fit points and, at each, a tangent handle (a line through the point with a knob at each
  end) and a curvature handle (a short arc glyph whose knob moves along the normal). Dragging a knob activates that handle and solves
  live, as a point drag does. The inspector, for a selected fit point, shows "Tangent handle: Automatic / Active" and "Curvature
  handle: Automatic / Active" with **Release** buttons that make an active handle automatic again (an active handle used by a
  constraint can't be released; the button says so).
- **Constraints:** Tangent and the new **Curvature** button apply to a spline end and a line, arc or spline end sharing its point.
  Applying either activates the spline's handles at that end (Tangent: the tangent handle; Curvature: both). Curvature means tangent
  directions equal and signed curvatures equal across the joint; with a line the spline's curvature there is 0, with an arc 1/r with
  the arc's turning sense. Line-to-arc Curvature is refused as unsatisfiable ("A line and an arc can't meet with equal curvature.").
- **Commands:** Mirror and Pattern copy splines with their handles (mirrored). Trim, Extend and Fillet refuse on a spline in their
  own words. Delete removes a spline; its fit points that nothing else uses go with it (orphan rule).
- **Construction:** a construction spline is drawn dashed and stays out of regions, as other construction curves.
- **Self-crossing:** a spline that crosses itself stays drawn and is left out of regions, with the sketch warning "Spline 4 crosses
  itself, so it isn't part of a region." **(call)**

## Pipeline

- **CreatorGeometry:** `Segment2D.spline(SplineCurve2D)`: degree 5, poles, knots and multiplicities, clamped; its `startPoint`,
  `endPoint`, `length` (Gauss–Legendre per span, exact enough to 1e-9 relative), `boundingPoints` (the poles: a convex hull bound),
  translation, point and derivative evaluation, Bézier span split (de Casteljau), nearest point (subdivision then Newton). Every
  `switch` over `Segment2D` (14 in 10 files) gets a case; consumers that can't use a spline say so in words, never crash.
- **Regions:** `CurveShape.spline`, with intersections against lines, arcs and splines by Bézier-hull subdivision then Newton (to
  1e-10 mm), `piece(from:to:)` by split, and area/containment through exact Green's-theorem integrals of the polynomial spans.
  `SketchTrace` maps a spline's profile segments back to the spline entity as for any curve.
- **Kernel/shim:** `occt_segment` gains kind 2 with a pointer to its poles, knots and multiplicities in a side table of
  `occt_profile` (the segment buffer stays contiguous); `build_edge` makes a `Geom2d_BSplineCurve` on the plane, `signed_area` uses the
  exact polynomial integral. Side tags are unchanged (one segment, one edge). `FakeKernel` refuses a spline profile for the solids it
  can't model, in words.
- **File format 11:** `SketchEntityKind.spline`, the handle states and the `.curvature` constraint are new kinds, so
  `GraphFile.currentFormatVersion` goes to 11 (an older reader cannot decode them). Files 1–10 open unchanged.

## Tests (what proves it)

- Maths: the Hermite → B-spline conversion is exact (evaluate both at 1,000 parameters, 1e-12); C2 along the chain; the automatic
  handles reproduce a cubic/quintic polynomial exactly when the fit points lie on one; curvature formula against finite differences.
- Solver: residuals of Tangent and Curvature at spline ends with analytic Jacobians checked against finite differences; DOF of a spline
  with all-automatic handles equals 2 × fit points; activating a handle adds 2 DOF per active vector until constrained; conflicts named.
- Regions: a closed loop of a line and a spline, two splines, a spline crossing a circle; self-crossing warns.
- Kernel (OCCT): extrude a profile of a line and a spline joined with Curvature; `Kernel.continuity` on the vertical edge between their
  side faces reads **G2**, and with Tangent only **G1 · curvature jump N %**; revolve and loft a spline profile; the kernel's edge
  matches the sketch curve within 1e-9 mm.
- Editor: drawing, finishing, handle drag activates, release, inference, refusals, copy/mirror, undo names ("Add Spline", "Move Handle",
  "Release Handle", "Add Curvature Constraint").
- Human checks (group SP): draw a spline, drag fit points and handles, Curvature-join a spline to a line, extrude, zebra flows across the
  joint; Measure reads G2.

## Left to the builder

The storage of handle states in `SketchEntityKind.spline`, the solver's handle column layout (`UnknownLayout`), the warm-start state,
the overlay glyphs' exact look within the theme's sketch roles, and the numeric tolerances inside intersection and nearest-point
searches (results to 1e-10 mm).
