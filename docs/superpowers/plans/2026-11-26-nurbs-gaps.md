# NURBS Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the user-visible NS-4/NS-5 gaps: thickened hole walls are true cylinders (so Measure gives a diameter), a value holding a solid and a sheet can be separated (and Split Solid says so), and Match Surface and Blend Surface work on closed edges.

**Architecture:** All geometry stays in the shim (`Sources/COCCT`) behind `Kernel`. Task 1 changes Thicken's wall builder; Task 2 adds one kernel call and one node; Tasks 3 and 4 add a periodic (cyclic) path beside the existing open path in Match's least-squares fit and Blend's skinning.

**Tech Stack:** Swift 6.4 (strict concurrency), Swift Testing, OpenCascade 7.9 through the C++ shim.

**Spec:** `docs/superpowers/specs/2026-11-17-nurbs-surfaces-design.md` (NS-4 Match and Blend, NS-5 Thicken and Split Solid). The parked items are in the memory note `nurbs-backlog-after-ns2` and in `Sources/CreatorNodes/Surfaces/CLAUDE.md`. The user asked for no question rounds on designs, so the rulings below are the controller's.

## Rulings

- **R1.** A Thicken wall between two coaxial circle arcs (axes parallel within 1e-9 rad and on one line within 1e-7 mm) is built on an analytic surface: a cylinder when the radii are equal (within 1e-7 mm) and the arcs lie in different planes, a plane (an annular sector) when the arcs are coplanar, otherwise a cone. Every other pair keeps `BRepFill::Face`. Its history and tags are unchanged (`.blend(sourceEdge:)`).
- **R2.** Thicken gets its own sentence for one-sided open edges instead of Offset's: "The thickened sides don't keep the surface's open edges, so it can't be thickened." (`kThickenOpenEdges`). Offset keeps its sentence.
- **R3.** New node **Separate Solids** (`creator.separateSolids`, category `.surface`, subgroup "Solids"): input `value` (`.solid`), outputs `solids` and `surfaces`, both `.solid` lists. Each closed solid in the value is one item of `solids`; each connected open piece (an open shell, a loose face, or a closed shell that made no valid solid, the same classes `SewResult.sheets` counts) is one item of `surfaces`. Either list may be empty; no warning. Items keep the input's face and edge tags. Order: the shim's compound order. No file-format bump (a new node type with no new `ConstantValue` kind, as NS-5).
- **R4.** Split Solid on a value that holds both a closed solid and an open piece refuses with: "Split Solid takes a closed solid; “solid” also holds a surface. Use Separate Solids to take the solid out first." A value that is only open keeps today's sentence. Both guard sites (`ClosedSolidCheck.requireForSplitSolid`, `OCCTKernel+SplitSolid.swift`) use the new one.
- **R5.** Match Surface on a closed edge: the sheet's edge must be a closed iso of a surface periodic along it, and the target edge must be closed too; a closed sheet edge with an open target, or the reverse, refuses: "Match Surface can't match a closed edge to an open one." The fit is cyclic: the along-edge pole rows of the result are periodic (no pinned ends), and the result surface stays periodic along the edge. The target pairing starts at the target parameter nearest the sheet's seam point and runs the way the tangents agree (positive dot product at the seam), by arc length as today.
- **R6.** Blend Surface on closed edges: both edges closed, or both open; one of each refuses: "Blend Surface needs both edges closed, or both open." For two closed edges, edge b starts at its point nearest edge a's start and runs the way the tangents agree; sections are made at the same fractions as today, and each pole column across sections is interpolated periodically (same parameters for every column, so the columns share one knot vector), giving a surface periodic in u. The face has two boundary edges and a seam; the boundary roles name the two rims, and the seam is never a role.
- **R7.** The doubly periodic case (a torus-like sheet) has no boundary edge to pick and needs nothing.

## Global Constraints

- All OCCT work runs under `OCCTKernel.serialized`; the shim stays portable (no `M_PI`, use `cocct::kPi`; no POSIX headers; no `__attribute__`).
- `cocct::user_error` messages are user-facing and unprefixed. Sentences quoted in the rulings are exact.
- Create nodes only with `NodeRegistry.makeNode`; a new node is added to `BuiltInNodes.all`.
- Tests use Swift Testing; a test that needs OpenCascade is in `CreatorOCCTTests` or gated `canImport(CreatorOCCT)`. In tests never block a pool thread (use `HookGate`).
- Pass rule: `swift test` exit 0, 16 "Test run with" lines, no "recorded an issue" / "failed after"; `swiftlint lint --strict` zero violations.
- Notes go into `Sources/CreatorNodes/Surfaces/CLAUDE.md` (and `Sources/COCCT/CLAUDE.md` for shim facts), never the root `CLAUDE.md`. Each task adds its human checks to `docs/verification/human-checks.md` (group NS-G, ids NSG-1…) in the existing style, and updates the stale lines (NS4-7 quotes "can't blend a closed edge yet").

## Review Focus

- A partial arc (a hole cut by the sheet's edge, i.e. an arc, not a full circle) thickened: the wall must still be analytic and still sew; Task 1 tests a half-hole.
- Thicken "Both" and "Back" put the circles on either side; the cylinder must span exactly between them in both orders; Task 1 tests all three sides.
- A closed target whose seam is far from the sheet's seam, and a target running the opposite way: Match must not twist; Task 3 tests both.
- Two closed rims of different radii and offset seams for Blend: no twist and no gap at the seam; Task 4 tests both.
- Separate Solids on a value with only one kind: the other list is empty and downstream nodes see an empty list, not an error; Task 2 tests both.

---

### Task 1: Thicken walls on analytic surfaces

**Files:**
- Modify: `Sources/COCCT/cocct_thicken.cpp` (`wall_between`, ~56-86; the one-sided open-edge refusal ~178)
- Modify: `Sources/COCCT/cocct_offset.hpp` or a thicken header: add `kThickenOpenEdges`; `Sources/COCCT/include/cocct.h` if sentences are declared there (they are, ~873/886)
- Modify: `Sources/CreatorOCCT/OCCTKernel+Thicken.swift` (the `thickenAttempt` pass-through that compares against Offset's sentence, ~83)
- Test: `Tests/CreatorOCCTTests/ThickenTests.swift` (or the existing Thicken test file)

**Interfaces:** Produces nothing new for other tasks.

- [ ] **Step 1: Write the failing tests**
  - `aHoleWallIsACylinder`: a Planar Surface plate 40 × 40 with a round hole of radius 5, thickened 2 mm with each of `.front`, `.back`, `.both`: exactly one face has `kind == .cylinder`, its `radius` is 5 within 1e-7, and the result is a closed solid.
  - `aHalfHoleWallIsACylinder`: a plate whose edge cuts a radius-5 hole in half (an arc boundary edge): the arc's wall is `.cylinder`, radius 5; the result is closed.
  - `aTubeRimWallIsFlat`: a tube sheet (revolve a line x = 10, z 0…20 about z, 360°) thickened 2 mm `.both`: the two rim walls are `.plane`.
  - `aConeRimWallIsAConeOrPlane`: a cone sheet (revolve the line from (10,0,0) to (5,0,10) about z, 360°) thickened 1 mm: each rim wall is `.cone` (its circles lie in different planes with different radii).
  - `theWallKeepsItsName`: the cylinder wall's tags are `.blend(sourceEdge:)` naming the hole's edge, as before.
  - `oneSidedOpenEdgesSayThicken`: wherever an existing test pins Offset's sentence for Thicken, it now expects R2's sentence (find it with grep for "so it can't be offset" in Thicken tests).
- [ ] **Step 2: Run them and see them fail** (`swift test --filter CreatorOCCTTests.ThickenTests`): the hole wall is `.bspline`.
- [ ] **Step 3: Implement R1 in `wall_between`.** Recognise the circle pair with `BRepAdaptor_Curve::GetType() == GeomAbs_Circle` on both edges and compare their `gp_Circ` axes and radii. Build the face on `Geom_CylindricalSurface`, `Geom_Plane` or `Geom_ConicalSurface` placed on the common axis, bounded by the two arcs and the two straight end segments (none for a full circle: then the face is bounded by the two circles and a seam), so that its boundary edges are the very `lower` and `upper` edges (or sew to them within the sewing tolerance already used). Keep `BRepFill::Face` for every other pair. Leave the planar line-pair special case as it is.
- [ ] **Step 4: Implement R2**: Thicken's one-sided open-edge refusal throws `kThickenOpenEdges`; `thickenAttempt` passes that sentence through where it passed Offset's.
- [ ] **Step 5: Run the Thicken, Offset and Measure tests**, then the full suite and lint.
- [ ] **Step 6: Notes and checks.** `Sources/CreatorNodes/Surfaces/CLAUDE.md`: Thicken's walls between coaxial circles are analytic (R1), and its own sentence (R2). Human check NSG-1: thicken a plate with a hole, Measure the hole wall: it shows the diameter.
- [ ] **Step 7: Commit.**

### Task 2: Separate Solids, and Split Solid's mixed-value sentence

**Files:**
- Modify: `Sources/CreatorKernel/Kernel.swift` (protocol), `Sources/CreatorKernel/BackToSolids.swift` (result type and the default/forwarding pattern used beside `splitSolid`), `Sources/CreatorKernel/FakeKernel*.swift` (fake answer)
- Create: `Sources/CreatorOCCT/OCCTKernel+Separate.swift`; shim function in a new `Sources/COCCT/cocct_separate.cpp` with its declaration in `Sources/COCCT/include/cocct.h`
- Create: `Sources/CreatorNodes/Surfaces/SeparateSolidsNode.swift`; Modify: `Sources/CreatorNodes/BuiltInNodes.swift`
- Modify: `Sources/CreatorNodes/Support/ClosedSolidCheck.swift`, `Sources/CreatorOCCT/OCCTKernel+SplitSolid.swift`
- Test: `Tests/CreatorOCCTTests/SeparateSolidsTests.swift`, `Tests/CreatorNodesTests/SeparateSolidsNodeTests.swift`, the existing Split Solid tests

**Interfaces:**
- Produces: `public struct SeparatedBodies: Sendable { public var solids: [Solid]; public var sheets: [Solid] }` and `func separated(_ value: Solid, tag: NodeTag) async throws -> SeparatedBodies` on `Kernel`.

- [ ] **Step 1: Write the failing tests**
  - Kernel: `aSolidAndASheetComeApart`: Sew of a box's six faces plus one loose planar sheet (or any fixture that yields a value with one closed solid and one sheet, e.g. the Thicken mixed-value fixture at `OCCTKernel+Thicken.swift:50`'s test): `solids.count == 1` and `solids[0].isClosed`, `sheets.count == 1` and `sheets[0].hasOpenShell`; every face tag of the input appears in exactly one output.
  - Kernel: `onlySolidsLeaveSheetsEmpty` (two boxes in one value via a union of disjoint boxes or a Sew: `solids.count == 2`, `sheets.isEmpty`) and `onlySheetsLeaveSolidsEmpty`.
  - Node: `separateSolidsIsInTheLibrary` (registry has `creator.separateSolids`, category `.surface`, subgroup "Solids", outputs `solids` and `surfaces`), and through the real Evaluator, `separatedSolidFeedsSplitSolid`: the `solids` item wired into Split Solid with a sheet tool splits.
  - Split Solid: `aMixedValueSaysSeparate` expects R4's sentence; the existing open-only test keeps its sentence.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement** the shim walk (closed solids vs open pieces, by the same classification Sew uses for `SewResult.sheets`), `OCCTKernel.separated` with history so the tags carry over (follow how `splitSolid` or `sewn` passes tags), the fake, the node (R3), and R4's sentence at both guard sites.
- [ ] **Step 4: Run the focused tests, then the full suite and lint.**
- [ ] **Step 5: Notes and checks.** Surfaces `CLAUDE.md`: Separate Solids (R3) and R4. Human check NSG-2: Thicken or Sew into a solid plus a sheet, Separate Solids, Split Solid the solid. Also the MCP node list if it is written by hand anywhere (grep for "creator.splitSolid" outside Sources/CreatorNodes).
- [ ] **Step 6: Commit.**

### Task 3: Match Surface on closed edges

**Files:**
- Modify: `Sources/COCCT/cocct_match.cpp` (the periodic refusal ~337; the fit in `match()` from ~300)
- Test: `Tests/CreatorOCCTTests/MatchSurfaceTests.swift` (replace `aSurfaceThatClosesOnItselfRefuses`)

**Interfaces:** none new.

- [ ] **Step 1: Write the failing tests** (fixtures: the existing tube, revolve of x = 10, z 0…20 about z, matching its rim at z = 0; the target is a tube revolved from the line (12,0,-5)…(12,0,-25) about z, whose rim at z = -5 is a closed circle of radius 12)
  - `aTubeRimMatchesAClosedRim` at G0, G1 and G2 (each a parameterised case): the result's matched edge lies on the target within the existing Match tolerance at 64 samples, the `grade` helper reports the requested continuity, and the result surface is periodic along the edge: points either side of the seam agree within 1e-7 and the cross derivatives agree within 1e-6.
  - `aFarSeamDoesNotTwist`: the target rim built from a revolve started at 137° (its seam far from the sheet's): same assertions, and the ruling lines (the sheet's v-isos at u = 0, 0.25, 0.5, 0.75 of the period) meet the target within 1 mm of the point nearest their own start (no twist).
  - `aReversedTargetDoesNotTwist`: the target revolved by -360°: same.
  - `aClosedEdgeToAnOpenOneRefuses`: tube rim to `sheetB`'s open edge: R5's sentence. And the reverse (an open sheet edge to the tube's closed rim).
- [ ] **Step 2: Run them and see them fail** (today's refusal).
- [ ] **Step 3: Implement R5.** Keep the surface periodic along the edge (no `SetUNotPeriodic`), make the along-edge pole unknowns cyclic (no pinned ends, all `na` poles free for k = 0, with the basis taken from the periodic knot vector), and solve the cyclic least-squares system (a dense or cyclic-banded solve; pole counts are small). Pair the target by arc length starting at its parameter nearest the sheet's seam point, in the direction whose tangent agrees with the sheet's at the seam. The open-edge path stays as it is.
- [ ] **Step 4: Run Match's tests, then the full suite and lint.**
- [ ] **Step 5: Notes and checks.** Surfaces `CLAUDE.md` (R5; remove "Match refuses closed edges" from the parked lists there). Human check NSG-3: Match a tube's rim to another tube's rim at G2 with zebra stripes.
- [ ] **Step 6: Commit.**

### Task 4: Blend Surface on closed edges

**Files:**
- Modify: `Sources/COCCT/cocct_blend_surface.cpp` (`open_end` refusal ~246; `build_surface` ~135-189; `iso_edge` and the boundary roles), and the `g2_skin` module if a periodic interpolation belongs there (check for an existing `interpolate_periodic` first)
- Test: `Tests/CreatorOCCTTests/BlendSurfaceTests.swift` (replace `aClosedEdgeIsRefused`)

**Interfaces:** none new.

- [ ] **Step 1: Write the failing tests** (fixtures: two coaxial tubes, radius 10 for z 0…20 and radius 14 for z 30…50, blending the rim at z = 20 to the rim at z = 30)
  - `twoTubeRimsBlend` at G1 and G2: the result is one face whose two boundary edges lie on the two rims (64 samples, the existing tolerance), `edge_continuity_against` / the test `grade` helper meets the requested grade at both, and the surface is periodic in u (seam points agree within 1e-7, derivatives within 1e-6).
  - `offsetSeamsDoNotTwist`: the second tube revolved from 90°: the u-isos at four fractions run from the first rim to the second within 1 mm of the nearest-point pairing (no twist). And `aReversedRimDoesNotTwist` (second tube revolved -360°).
  - `aClosedAndAnOpenEdgeRefuse`: tube rim with `sheetA`'s open edge: R6's sentence.
  - `theRimsAreTheRoles`: the face's boundary roles name the two rims and never the seam (follow how the open case tests roles).
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement R6**: pair the closed edges, build the quintic rows at the same fractions (the last fraction is the first again, so drop the duplicate), interpolate each pole column periodically with shared parameters, assemble a u-periodic `Geom_BSplineSurface`, make its face, and grade and assign roles over the two rim edges (skip the seam). The open path stays as it is.
- [ ] **Step 4: Run Blend's tests, then the full suite and lint.**
- [ ] **Step 5: Notes and checks.** Surfaces `CLAUDE.md` (R6; remove "Blend refuses closed edges" from the parked lists), update human check NS4-7's closed-edge sentence, add NSG-4: blend two tube rims at G2 with zebra stripes.
- [ ] **Step 6: Commit.**
