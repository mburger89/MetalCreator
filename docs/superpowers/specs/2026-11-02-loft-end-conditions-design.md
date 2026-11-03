# G-d: Loft end conditions — design

Status: written 2026-11-02 without a question round (the user skipped the questions for G-c and asked to keep going down the list).
It follows "Later" in `2026-11-01-g2-surfacing-design.md` ("Tangent (G1) and Curvature (G2) at a loft's ends against a face, with
a weight, as Fusion; needs a profile that knows its face and our own end-constrained skinning"). Everything else is marked **(call)**.

## Intent

A loft that grows out of a part today starts with a crease: its sides leave the part's face at whatever angle the sections give, and
zebra breaks there. With an end condition the loft's sides carry on from the part's own side faces, tangent (G1) or with matching
curvature (G2), so a boss, a handle or a transition grows out of the part with stripes that flow across the joint, and Measure reads
the joint as G1 or G2.

## How Fusion does it (the behaviour we copy)

A loft profile may be a face (or a loop of edges) of a body. With the end condition **Tangent** or **Smooth (G2)** on that profile, the
loft's side surface leaves each edge of the loop in the direction of the body face on the far side of that edge (continuing the body's
wall), with a **tangency weight**. The cap on the body face disappears when the loft is joined to the body.

## Goals

1. The Loft node takes a part (`solid` input) and, for its **first** and/or **last** section, a picked **face** of that part instead of
   a profile. That face's outer loop is the section.
2. For each face end, **Continuity**: Free (as today), Tangent (G1), Curvature (G2), and a **weight** 0.1 to 2 (default 1), as the
   Fillet node's tangency weight.
3. With Tangent or Curvature, along every edge of the face's loop the loft's side surface meets the part's adjacent face (the face on
   the other side of that edge from the picked face) G1 or G2; joined with Boolean Union, `Kernel.continuity` reads that grade on those
   edges.
4. Free ends and middle sections behave as today's smooth loft (sections in order; equal segment counts).
5. Works on every platform (OpenCascade everywhere).

## Non-goals

- Picked edge loops that aren't a whole face's outer loop; faces with holes (the loft still refuses holes).
- Joining inside the Loft node: the user unions with Boolean, as for every other feature. **(call)**
- A ruled loft with end conditions (refused: "Straight sides can't have end conditions."). **(call)**
- End conditions against a face that isn't on the part (a free-floating sketch section stays Free).
- Rails/guide curves, centre lines.

## Anti-goals

- A Tangent or Curvature end that silently isn't: the kernel judges every joint edge it promises, at the fillet's tolerances (position
  1e-4 mm, angle 0.01°, curvature 1 % or 1e-4 /mm), and fails the loft in words rather than return a weaker joint.
- A loft whose Free ends change when end conditions are added at the other end.
- A pick that drifts: the face is a `FacePick`, resolved and warned about exactly as Plane from Face and Face Pattern do.

## Behaviour

- **Inputs:** `sections` (profiles, as today), new `solid` (optional; needed only for a face end), settings `startFace` and `endFace`
  (`FacePick`s, set with "Pick Start Face in View…" / "Pick End Face in View…" and cleared with a button), `startContinuity` /
  `endContinuity` (0 Free, 1 Tangent (G1), 2 Curvature (G2); shown only when that end has a face), `startWeight` / `endWeight`
  (0.1…2, shown for Tangent and Curvature). typeVersion 2; an old Loft opens with no faces (unchanged).
- **Sections:** with a start face the loft's sections are [the face's loop] + `sections`; with an end face, `sections` + [the face's
  loop]. At least two sections in all. The face's loop must have as many edges as each profile has segments (the existing message).
- **The weight:** the across-tangent length at the face end is weight × the length a circular arc would have between that end and the
  next section (the fillet's convention, `circular_tangent_length`).
- **Messages:** "Pick a face of the part for the loft's start." (a face setting with no `solid`); the face pick's own messages
  (vanished, ambiguous, merged) as Face Pattern's; "The loft can't meet the part tangent (G1) here." / "…with matching curvature (G2)
  here." when the kernel can't judge the joint within tolerance; holes and segment counts as today.
- **Tags:** the loft's side faces keep `.side(loop: 0, segment: k)`. Side tag k is the face edge paired with profile segment k **(call,
  ruling after the spike)**: profiles stay fixed, and a face loop is wound like its neighbouring section and started at the rotation that
  best matches that section's vertices, so the tag follows the profile's segment, not the face's edge numbering. A one-edge closed loop (a
  circle) starts at the point of the edge nearest the paired section's start, so the loft does not twist. A face end must be flat
  ("The loft's end face must be flat." otherwise) **(call)**, and a weight that loops a column back is refused ("The tangency weight is
  too large for this loft."). Caps keep `.startCap` / `.endCap`.

## Construction (call: the builder may change it if the spike says so)

The loft is built by our own skinning, not `BRepOffsetAPI_ThruSections`, whenever an end has Tangent or Curvature (Free lofts keep
ThruSections, so nothing changes for them):

1. Pair the sections' segments by index, and points along them by fraction (as ThruSections does for compatible wires).
2. For each segment k, sample columns along it; each column is a curve across the sections: a quintic Hermite chain through the
   sections' points (C2, chord-length spans, the G-c spline maths), whose end derivatives at a face end are set from the adjacent face:
   first derivative = weight-scaled length × the adjacent face's direction across the edge pointing away from the part (G1), second
   derivative from its normal curvature in that direction (G2) — the fillet shim's `end_condition` / `surface_point`. Free ends use the
   natural conditions.
3. Skin each segment's columns into a B-spline surface (as `build_strip` does), adaptive column counts until the face-end seam and the
   seams between neighbouring side patches meet tolerance (`measure_seam`), capped like the fillet (then the message).
4. Caps from the end sections' wires (planar or the picked face's own surface), sew, BRepCheck; never return an invalid solid.

Neighbouring side patches share their boundary column (the curve through the sections' vertices), so they meet G0 exactly and keep the
sections' corners as creases, as today's loft does.

## Tests

- Kernel (OCCT): a box's top face lofted to a smaller square section: Free equals today's ThruSections result in shape and tags;
  Tangent and Curvature, unioned with the box, read G1 and G2 on all four top edges; the weight changes the side's bulge monotonically;
  a cylinder's top face (circle loop) to a smaller circle; a face end at both ends (a bridge between two boxes); refusals in words.
- Node: settings, typeVersion migration, messages, pick resolution, the inspector shows controls only when they apply.
- App: the pick buttons set and clear the face settings (one undo step each), as the lattice's face pick does.
- Human checks (group LE): a boss lofted from a box face at Free, Tangent and Curvature under zebra; Measure on a joint edge.

## Left to the builder

The column count and pairing details, the B-spline approximation tolerance of the skin, the pick session's target plumbing, and the
inspector layout within the existing controls.

## Erratum (2026-11-02): the skin along a segment

Construction step 3 skinned each segment's columns with OpenCascade's cubic interpolation (`GeomAPI_Interpolate`). Its periodic form
estimates the tangent at a closed loop's junction from a few neighbouring points, so a one-edge closed loop (a circle) missed the angle
tolerance at that one column and needed the cap, 129 columns. Every pole row is now our own spline through the columns, as the G2 fillet's
strips are (g2 surfacing spec, erratum "the skin along a strip"): de Boor's averaged knots, periodic with a knot at every column on a closed
loop, a cubic at the first columns and a quintic from then on if the cubic misses. Three exceptions: a patch given its row tangents at a
smooth vertex stays cubic (those tangents share one length ratio across all the rows so the two patches meet G1, the sections' own rows need
not have that ratio, and the skin misses near that end at first order until columns crowd there, which a cubic's miss confines to fewer spans
than a quintic's); a part edge whose first or second derivative jumps at an interior knot breaks the skin there, with a column on the break
(a knot of full multiplicity less one); and an open segment starts at 5 columns, a closed loop at 9 (its periodic quintic needs more than 5).
Tolerances, the checks, the 129 cap, the shared vertex columns and ThruSections for Free lofts are unchanged. Columns, before and after: the
box top to a square (G1, G2, weights 0.1 to 2), the bridge, the bridge with a waist and the frustum 9 to 5 per segment; the cylinder top to a
circle, the circle started a quarter turn round and the dome (G1 and G2) 129 to 17; the rounded rectangle [45, 38] × 4 unchanged.
