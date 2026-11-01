# G-b1: Edge continuity readout — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `Kernel.continuity(along:of:)` and Measure's Continuity row for one picked edge.

**Architecture:** A new kernel call samples an edge and compares the two faces' normals and normal curvatures across it (OCCT:
`BRepLProp_SLProps` in a new shim file). The Measure session asks for it off the main actor exactly as it asks for a distance,
and the panel shows one row.

**Tech Stack:** Swift 6.4, Swift Testing, OpenCascade 7.9 C++ shim.

**Spec:** `docs/superpowers/specs/2026-11-01-g2-surfacing-design.md` §G-b (Kernel, Measure readout).

## Global Constraints

- OCCT only behind `Kernel`, under `OCCTKernel.serialized`; every C allocation has a `*_free`; no C++ exception crosses into Swift;
  the shim stays portable (no `M_PI`, POSIX headers, `__attribute__`).
- Swift Testing; `swiftlint lint --strict` 0; 12 "Test run with" lines on macOS and Linux.
- Tolerances (spec): position 1e-4 mm; angle 0.01°; curvature within 1 % of the larger curvature or 1e-4 /mm, whichever is larger.
- Measure is view state: no command, no undo step, no edit.
- Copy: "G2"; "G1 · curvature jump 38 %"; "G0 · 12.0°" (angle in the document's angle display, percent rounded to whole).

## Review Focus

1. An edge on only one face (an open shell's boundary, a seam edge of a cylinder) gives no Continuity row, not an error row.
2. A seam edge of a closed face (cylinder) is not offered (selection rules never select seams; still guard in the kernel: `.unsupported`).
3. Two flat faces meeting at 180° (coplanar after a boolean) read G2 (both curvatures 0).
4. A cylinder tangent to a plane reads "G1 · curvature jump 100 %".
5. A kernel failure during the readout leaves the other Measure rows intact and shows "Couldn't measure" in the Continuity row.

---

### Task 1: `Kernel.continuity` in CreatorKernel, FakeKernel and the shim

**Files:**
- Create: `Sources/CreatorKernel/Measure/EdgeContinuity.swift`, `Sources/COCCT/cocct_continuity.cpp`,
  `Sources/CreatorOCCT/OCCTKernel+Continuity.swift`
- Modify: `Sources/CreatorKernel/Kernel.swift` (requirement + default `.unsupported("continuity")`), `FakeKernel.swift`,
  `KernelUnavailable.swift`, `Sources/COCCT/include/cocct.h`
- Test: `Tests/CreatorKernelTests/EdgeContinuityTests.swift`, `Tests/CreatorOCCTTests/EdgeContinuityOCCTTests.swift`

**Interfaces — Produces:**
```swift
public enum ContinuityClass: Int, Comparable, Sendable { case g0, g1, g2 }
public struct EdgeContinuity: Equatable, Sendable {
    public var positionGap: Double      // mm, worst sample
    public var angleGap: Double         // radians, worst angle between the faces' normals
    public var curvatureGap: Double     // relative: |κ1 − κ2| / max(|κ1|, |κ2|), or 0 when both are under 1e-4 /mm
    public var absoluteCurvatureGap: Double  // /mm
    public var grade: ContinuityClass   // against EdgeContinuity.tolerances
    public static let positionTolerance = 1e-4, angleTolerance = 0.01 * .pi / 180, curvatureTolerance = 0.01, curvatureFloor = 1e-4
    public static func grade(positionGap:angleGap:curvatureGap:absoluteCurvatureGap:) -> ContinuityClass
}
// Kernel
func continuity(along edge: EdgeID, of solid: Solid) throws -> EdgeContinuity
```
Normal curvature on each side is taken in the direction across the edge (the face's tangent plane, perpendicular to the edge
tangent), with the normals oriented by the faces' orientation in the solid. Samples: 32 evenly in the edge's parameter, ends excluded
by 1 % of the range.

- [ ] **Step 1: Failing tests:** `gradeRules` (pure: each boundary of the tolerances, the curvature floor); FakeKernel
  `aBoxEdgeIsG0` (angle π/2). OCCT: `aBoxEdgeIsG0`, `aFilletSpringEdgeIsG1` (box edge filleted r 2: spring edge angle < 0.01°,
  curvature jump 100 %), `aCylinderTangentToAPlaneIsG1`, `coplanarFacesAreG2` (a box unioned with a box sharing a face, if
  OCCT keeps the edge; else build two faces sharing an edge through an extrude of a two-segment collinear profile), `aSeamIsUnsupported`.
- [ ] **Step 2:** Run `swift test --filter EdgeContinuity`; expect failures.
- [ ] **Step 3: Implement** (shim: `occt_edge_continuity(shape, edge_index, out)` filling a plain C struct; errors through the
  existing `set_error`/`guarded` path).
- [ ] **Step 4:** Tests pass on macOS; `scripts/linux-test.sh test --filter 'EdgeContinuity'` passes.
- [ ] **Step 5: Commit** `feat(kernel): edge continuity`.

### Task 2: Measure's Continuity row

**Files:**
- Modify: `Sources/CreatorApp/Measure/MeasureReadings.swift` (`MeasureQuantity.continuity`), `MeasureSession.swift` (ask after a
  single edge pick, as the distance is asked; cancel on a new pick), `MeasurePanel.swift` (`MeasurePanelText.continuity(_:)`),
  `MeasureBook.swift` only if a kept single-edge measurement re-measures (it does: same rule as distances)
- Test: `Tests/CreatorAppTests/Measure/MeasureContinuityTests.swift`

**Interfaces — Consumes:** Task 1. **Produces:** `MeasurePanelText.continuity(_ value: EdgeContinuity, units:) -> String` giving
the spec's copy; the row is titled "Continuity".

- [ ] **Step 1: Failing tests:** `oneEdgeShowsItsContinuity` (FakeKernel box edge: row "G0 · 90.0°"), `copyForEachGrade` (G2,
  "G1 · curvature jump 38 %", "G0 · 12.0°"), `aSectionEdgeOrMeshShowsNoContinuity`, `twoPicksShowNoContinuity`,
  `aFailedContinuityReadsCouldntMeasure` (throwing kernel; other rows intact), `noUndoStepNoEdit`.
- [ ] **Step 2:** Run `swift test --filter MeasureContinuity`; expect failures.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** `swift test --filter 'Measure'`, lint.
- [ ] **Step 5: Commit** `feat(measure): continuity of a picked edge`.

### Task 3: Records

- [ ] CLAUDE.md: Kernel line for `Kernel.continuity(along:of:)`; Measure paragraph for the row. Human checks ME-C (box edge G0,
  fillet spring edge G1, coplanar G2).
- [ ] Full `swift test`, lint, `scripts/linux-test.sh test`. Commit `docs(measure): continuity records`.
