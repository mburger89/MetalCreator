# G-d: Loft end conditions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A loft may start or end on a picked face of the part and meet the part's adjacent faces Tangent (G1) or Curvature (G2), with
a weight.

**Architecture:** A new shim entry `occt_loft_ends` skins the loft itself (quintic Hermite columns across sections with end derivatives
from the adjacent faces, adaptive, judged with `measure_seam`) when an end has a condition; Free lofts keep ThruSections. `Kernel.loft`
gains end specifications; the Loft node gains `solid`, two face picks, continuity and weight per end.

**Tech Stack:** Swift 6.4, Swift Testing, OpenCascade 7.9 C++ shim.

**Spec:** `docs/superpowers/specs/2026-11-02-loft-end-conditions-design.md`.

## Global Constraints

- OCCT only behind `Kernel`, under `OCCTKernel.serialized`; shim portable (`cocct::kPi`, no POSIX headers, no `__attribute__`); every
  C allocation has a `*_free`; no C++ exception crosses into Swift; BRepCheck on every result.
- Tolerances: position 1e-4 mm, angle 0.01°, curvature 1 % or 1e-4 /mm (the fillet's `within_tolerance`).
- Swift Testing; `swiftlint lint --strict` 0; 12 "Test run with" lines on macOS and Linux; only the known HLSL failure.
- Exact copy: "Pick a face of the part for the loft's start." / "…for the loft's end."; "The loft can't meet the part tangent (G1)
  here."; "The loft can't meet the part with matching curvature (G2) here."; "Straight sides can't have end conditions."; continuity
  options "Free", "Tangent (G1)", "Curvature (G2)"; buttons "Pick Start Face in View…", "Pick End Face in View…".
- A Free loft (no face, or Free continuity with a face) uses `BRepOffsetAPI_ThruSections` exactly as today.

## Review Focus

1. A Loft saved before this work opens and evaluates identically (typeVersion 1 → 2 migration stores nothing new).
2. A face end with Free continuity builds like ThruSections from that face's wire (same tags, same shape within 1e-6 mm).
3. The face-end's side patches meet each other G0 exactly at the loop's vertices (no slivers: the solid is valid and closed).
4. The weight at 0.1 and at 2 both build valid solids on the box test, and the bulge (the side's offset at mid-height) is monotonic.
5. A pick on a face that merges away after an upstream edit warns with the pick's messages, never picks a neighbour.

---

### Task 1: Spike — the end-constrained loft in the shim (go/no-go)

**Files:** Create `Sources/COCCT/cocct_loft_ends.cpp` (reusing `cocct_g2_section.hpp`, and the fillet's `surface_point` /
`end_condition` / `measure_seam` through `cocct_g2_blend_internal.hpp`, moving a function into a shared header if needed); declare in
`cocct.h`: `occt_loft_ends(const occt_shape *part, const occt_loft_end *start, const occt_loft_end *end, const occt_profile *sections,
int count, occt_history *, occt_loft_report *, occt_status *)` with `occt_loft_end { int face_index; int continuity; double weight; }`
(face_index −1 = no face) and a report (`seams_total`, `seams_judged`, worst gaps, column counts). Tests:
`Tests/CreatorOCCTTests/LoftEndConditionTests.swift` through a thin `OCCTShape` wrapper.

- [ ] Gate tests (all must pass to continue): `boxTopToSmallerSquareTangentIsG1` and `…CurvatureIsG2` (a 20×20×10 box's top face, one
  12×12 square section 10 mm above, centred; union with the box; `Kernel.continuity` on the four top edges reads G1 / G2; valid
  solid); `freeFaceEndMatchesThruSections` (Review Focus 2); `cylinderTopToSmallerCircleIsG2` (one-edge loop: circle seam handled);
  `bridgeBetweenTwoBoxesBothEndsG2`; `weightIsMonotonic` (Review Focus 4). Report timings (release) and column counts.
- [ ] If the gate can't be met, stop and report what blocks it (no product wiring).
- [ ] Commit `spike(occt): end-constrained loft`.

### Task 2: Kernel API

**Files:** `Sources/CreatorKernel/Kernel.swift` (`LoftEnd { face: FaceID, continuity: LoftContinuity, weight: Double }`,
`LoftContinuity { free, tangent, curvature }`, `func loft(_ sections: [Profile2D], ruled: Bool, part: Solid?, start: LoftEnd?, end:
LoftEnd?, tag: NodeTag) throws -> Solid` with the old signature forwarding), `FakeKernel` (refuses face ends: `.unsupported`),
`KernelUnavailable`, `Sources/CreatorOCCT/OCCTKernel.swift` (+ `OCCTShape` call; the loft's caps keep `.startCap`/`.endCap` and its
sides `.side(loop: 0, segment: k)`; none of the part's faces are in the loft, so no part tag passes through),
`KernelError` cases with the spec's copy. Tests: `Tests/CreatorKernelTests/LoftEndTests.swift`, OCCT tests extended for tags
(`sideTagsFollowTheFaceLoop`).

- [ ] Failing tests, implement, `swift test --filter 'CreatorKernelTests|CreatorOCCTTests'`, Linux OCCT, lint. Commit `feat(kernel): loft end conditions`.

### Task 3: The Loft node and the pick

**Files:** `Sources/CreatorNodes/Solids/LoftNode.swift` (typeVersion 2, `solid` input, `NodeSetting.startFace`/`endFace` (new setting
keys; check `NodeSetting.reservedForSockets`), continuity and weight sockets, `inspector(for:)` showing only what applies, face
resolution via the Face Pattern / Plane from Face helpers), `Sources/CreatorApp/PickSession.swift` + `AppModel+Picking.swift` (a pick
target for a loft end, one undo step "Pick Face"), `InspectorAction` cases for the two pick buttons and clear. Tests
`Tests/CreatorNodesTests/LoftEndNodeTests.swift`, `Tests/CreatorAppTests/LoftFacePickTests.swift`, and an acceptance through the
Evaluator on OCCT (box → loft with Curvature start → Boolean union → `Kernel.continuity` G2 on the four edges).

- [ ] Failing tests (incl. Review Focus 1 and 5), implement, `swift test --filter 'CreatorNodesTests|CreatorAppTests|CreatorGraphTests'`, lint. Commit `feat(loft): end conditions on picked faces`.

### Task 4: Records

- [ ] CLAUDE.md (Kernel line, Loft node, the shim file), human checks group **LE**, a benchmark row `loft-ends-1` (box face to square at
  G2, release) in `docs/verification/performance.md`.
- [ ] Full `swift test` (12), lint, `scripts/linux-test.sh test` (12). Commit `docs(loft): end condition records`.
