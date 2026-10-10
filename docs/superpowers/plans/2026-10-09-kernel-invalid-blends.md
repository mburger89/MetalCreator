# Kernel: Blends That Return an Invalid Solid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The OCCT kernel never returns a fillet or chamfer that OCCT's own checker rejects. It refuses the blend with a plain message naming the largest size that works ("Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm)."), so §8's polygon swap fails at the Fillet with a fix the user can apply, not at the Chamfer downstream with no explanation (roadmap row "Kernel: blends that return an invalid solid").

**Architecture:** One new shim query, `occt_is_valid` (`BRepCheck_Analyzer`, geometry included), exposed as `OCCTShape.isValid`. `OCCTKernel`'s shared blend path moves to `OCCTKernel+Blend.swift`. It checks each built blend under the same OCCT lock. When the check rejects the result, it bisects for the largest size on a 0.1 mm grid that OCCT builds and the checker accepts (`largestValidBlend`; each try takes the lock on its own, and a cancelled evaluation stops between tries) and throws `KernelError.invalidBlend(…)`. Repair was probed on real OCCT 7.9 and can't produce a valid solid (see Probe evidence), so nothing is repaired. A blend that passes is returned as built, with the same history, so tagging and naming don't change. No `Kernel` protocol, `KernelError` case, graph, node or UI change.

**Tech Stack:** Swift 6.4 (strict concurrency, Swift 6 language mode), Swift Testing, OpenCascade 7.9 (Homebrew) through `COCCT`/`CreatorOCCT`, SwiftLint.

**Spec:** `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`: §3 (error messages: "max ≈" when OCCT reports enough), §5.2 (the kernel), §8 (naming stability's polygon swap), the risks table ("OCCT fillets fail for some radii: Clear errors with the maximum radius where possible"), and Errata (naming: merged faces), which hands this defect to this row. Task 3 adds Errata (Kernel: invalid blends).

**Verified against master `fdef111` (1368 tests) and MetalUI `0b400b4`.** Every code block below was extracted from this file into a fresh copy of the worktree and applied task by task, in order. The copy sat next to an export of MetalUI at `0b400b4` (`git archive`), as Prerequisites' "Running the full suite" describes. The live `../MetalUI` checkout has moved on (at review it was `2155f1e`, which contains LF-b's fix `9ad2254`), so built against it `CanvasClipRenderTests`' `withKnownIssue` cases report "Known issue was not recorded" on master as well as here (see Risks). After each task the package built with no new warnings: only the expected OCCT "built for newer macOS" linker notes and M4's existing `ContextMenuTests` capture warning. `swift test` exited 0, no line said "recorded an issue" or "failed after", and 11 "Test run with" lines appeared (the 8 LF-b known issues expected). `swiftlint lint --strict` reported zero violations. Cumulative test counts: Task 1 → 1370 (master + 2), Task 2 → 1377 (master + 9), Task 3 → 1377 (master + 9). A parameterised test counts once.

**Shared with other tracks (merge with care):**
- `CLAUDE.md` (Task 3 adds one sentence after the "Shim errors" rule). Every track edits it.
- `docs/superpowers/roadmap.md` (Task 3 replaces row "Kernel: blends that return an invalid solid" and adds a row under it). Every track edits it, and m7-measure ("Measure §7.3 targets") edits the M7 row.
- `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (Task 3 appends a section at the end). Any track adding errata (sketcher-s5b, m7-measure) appends there too; keep both sections.
- `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md` (Task 3 rewrites the end of the first "From M6" bullet).
- `Sources/COCCT/include/cocct.h` and `Sources/COCCT/cocct.cpp` (Task 1 adds one declaration after `occt_edge_length` and one function before `occt_fillet_edge`). Any track that adds a shim call edits `cocct.h` (sketcher-s5b's Project may). The additions are local.
- `Sources/CreatorOCCT/OCCTKernel.swift` (Task 2 deletes the private `blend`, which moves to `OCCTKernel+Blend.swift`). m7-measure may touch the kernel for timings; rebase onto the move rather than re-adding `blend`.
- Not shared: the sketch-drag-readout branch's `SketchEditorModel+Readout.swift`, `ReadoutText.swift` and `PointerReadoutTests`; `Package.swift` (TKTopAlgo, which holds `BRepCheck`, is already linked); MetalUI; any UI target; `GraphFile.swift` (no format change).

**Prerequisites:**
- The worktree `/Users/maxburger/Developer/MetalCreator-blends` on branch `kernel-invalid-blends` at `fdef111` or later, clean (`git status --short` prints nothing). Run every command from it; never `cd` to another worktree.
- OpenCascade 7.9 from Homebrew, as for M2 on. SwiftLint installed.
- **Running the full suite.** `../MetalUI` belongs to another session: never modify it, and never edit `Package.swift`'s MetalUI path. Builds, filtered runs and `swiftlint` run in the worktree. For the gated full `swift test` (exit 0, no "recorded an issue" or "failed after" line, 11 "Test run with" lines, the 8 LF-b known issues expected), use one of:
  1. *A scratch copy* (preferred): `git archive HEAD` of the worktree (plus its uncommitted changes) extracted to `<scratch>/MetalCreator-blends`, next to `<scratch>/MetalUI` from `git -C ../MetalUI archive 0b400b4` (read-only git), and run `swift test` there. The relative MetalUI path then resolves to `0b400b4` without touching either checkout.
  2. *In the worktree*, against whatever `../MetalUI` holds: when it contains LF-b's fix, `CanvasClipRenderTests.aNodeAtANegativeCanvasPositionDrawsWhole` reports "Known issue was not recorded". Count only "recorded an issue" / "failed after" lines outside `CanvasClipRenderTests`, and report the `CanvasClipRenderTests` ones to the LF-b owner (MetalUI session) rather than changing them here.

## Probe evidence (real OCCT 7.9)

Probed on master with a throw-away shim function and test (not part of the plan). Through the §7.2 bracket graph, the polygon swap's union and the Fillet rule's four edges were taken and every variant below was run on them. A variant counts as a **repair** only if `BRepCheck_Analyzer` accepts the result and the 5 resolved top-outline edges then chamfer at 0.5 mm.

1. **What's broken.** The four edges are the hexagon's upright edges, x = ±12.99, z 7.5 → 22.5, on its two caps (y = 12 and y = 20). At R3, `BRepFilletAPI_MakeFillet` reports done with 4 contours. The solid it returns has 3 wires not closed in their face (`BRepCheck_NotClosed`), 3 faces `BRepCheck_UnorientableShape`, an unclosed shell, vertex tolerances up to **4.995 mm** (the union's are 1e-4) and volume **16007 mm³**, where the valid trend gives about 17905 (R2.5: 17940.1, R2.55: 17936.7). About 1900 mm³ is missing, so the shape isn't just a bad tolerance. Every chamfer of the outline fails on it. These volumes are the bracket's, holes included. On the kernel-only `HexagonFlange` fixture (Decision 8, no holes) the invalid R3 fillet has *more* volume than a valid one would (20202 mm³, against 18411 at R2.5, 18408 at R2.55; 20231 at the invalid R2.6), so the defect is a wrong volume, not specifically a loss.
2. **Where it starts.** Valid at R 1, 2, 2.5 and 2.55 (and the outline then chamfers at 0.5 mm). Invalid at 2.6, 2.7, 2.8, 2.85, 2.9, 3, 3.5. Not done at 4. A **chamfer** of the same four edges behaves the same way: valid at 1, 2 and 2.5, done but invalid at 3, not done from 4. The rectangle bracket's R3 fillet is valid.
3. **Repair attempts, all on the R3 result; none gives a valid solid:**
   - `ShapeFix_Shape`, default: still invalid, volume changes to 16832.3, outline chamfer done but invalid (15866.5).
   - `ShapeFix_Shape` with `SetPrecision(1e-4)`, `SetMaxTolerance(1e-3)`, `SetMinTolerance(1e-7)`: same as default.
   - `ShapeUpgrade_UnifySameDomain(…, true, true, true)`: still invalid, unchanged. Followed by `ShapeFix_Shape`: as `ShapeFix_Shape` alone.
   - `ShapeFix_ShapeTolerance::LimitTolerance(1e-7, 1e-3)`: more invalid (two vertices fail too). Followed by `ShapeFix_Shape`: as above.
   - `BRepLib::SameParameter(…, 1e-5, true)`: unchanged.
4. **Different fillet options, none valid at R3:** `ChFi3d_QuasiAngular` and `ChFi3d_Polynomial` give the same invalid solid. `SetParams` with OCCT's defaults, ten times tighter or ten times looser gives the same invalid solid (the loose one with a slightly different volume). Filleting **one edge at a time**: the very first single edge is already invalid at R3 (2 faces). `ShapeFix_Shape` on the **input** first, then fillet: the same invalid solid. At R4 every variant is not done.
5. **Conclusion:** the R3 result can't be repaired into a valid solid that keeps the right volume and topology. So the kernel refuses it (decision 1). The threshold falls between 2.55 and 2.6, so a 0.1 mm bisection from 3 names **2.5 mm**, for the fillet and for the chamfer. On a 10 × 20 × 30 box's 30 mm edge it names **9.9 mm** (R10 isn't built: the narrower face is 10 mm wide).
6. **No false positives:** with the check on every blend, the whole suite (naming stability, the bracket at Width 90, merged faces at 40 and 70 mm, the app's acceptance run, sketch projections) passes unchanged. Every existing blend result is `BRepCheck`-valid. One check costs about 3-4 ms on the hexagon flange's blend result and about 2 ms on its union (measured at review; see Risks, Cost).

## Decisions made in this plan

1. **Reject, don't repair.** Probe 3–5: no healing, unifying, tolerance fix, fillet option or edge order gives a valid solid, and ShapeFix changes the volume. A refused blend leaves the solid it would have broken untouched; the viewport keeps the last good part as a ghost (spec §4.4, §6.3).
2. **Check with `BRepCheck_Analyzer` in the shim, as a query.** `occt_is_valid` returns 1, 0, or -1 when the check itself throws (`queried`), and `OCCTShape.isValid` treats anything but 1 as invalid. The blend shim functions are unchanged. The check runs in Swift right after the blend, inside the same `OCCTKernel.serialized` call. A separate query, rather than a new status code on `occt_status`, keeps every other shim call and `OCCTError` untouched.
3. **Only fillets and chamfers are checked** (this row). Booleans, extrudes and transforms are not: the probe found no invalid one, and checking them is a behaviour change for its own row (see Risks).
4. **Name the largest size that works** (spec §3, risks table). `largestValidBlend` bisects in tenths of a millimetre between 0 and the size asked for. It returns only a size that was built and accepted, and returns nil when even 0.1 mm isn't. It assumes that once a size fails, every larger size fails (true across probe 2). The upper bound is capped at 1,000,000 tenths (100 m), so a huge size can't overflow `Int`. That gives at most 20 tries, each under the OCCT lock on its own, with `Task.checkCancellation()` before each. The search runs only when OCCT built a result and the checker rejected it. A blend OCCT can't build at all keeps today's message, with no search (new roadmap row, Task 3).
5. **Messages** (`KernelError+Blend.swift`). Existing cases are reused; no new `KernelError` case:
   - Fillet with a size that works: `.filletFailed(radius:maxRadius:reason:)`, read as §3's "Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm)." That wording is §3's own, so it doesn't name the edge count; the count is kept in `reason`, which this case of `userMessage` doesn't show. The other three messages name it.
   - Fillet with none: "Radius 3 mm could not be applied: rounding the 4 selected edges gives a broken solid, even by 0.1 mm."
   - Chamfer: `.operationFailed(operation: "chamfer", …)`, read as "Chamfer failed: chamfering the 4 selected edges by 3 mm gives a broken solid (max ≈ 2.5 mm)." or "…, even by 0.1 mm."
   - One edge reads "the selected edge". Numbers use the same `FormatStyle` as the kernel's other messages (`.number.precision(.fractionLength(0...2))`). The existing not-built messages move into `KernelError.blendFailed` word for word.
6. **The polygon swap test flips** (renamed `swappingTheFlangeForAPolygonKeepsEveryPickOnceTheFilletFits`):
   - at R3 the **Fillet** is in error with the 2.5 mm message; its Edges by Tag rule still re-derives the hexagon's 4 edges; the Edges by Tag, Chamfer and Output after it are `.idle`, and the Output has no part;
   - the test then sets the Fillet's radius to 2.5, the size the message names: everything is `.ok`, the five chamfer picks resolve exactly as Errata (naming: merged faces) says, and the Output has its part;
   - two undos bring back the rectangle flange.
   The old proof that "the picks aren't the cause" (chamfering the union) is dropped, since the Chamfer no longer fails.
7. **Naming keeps working**, and nothing is repaired: a blend that passes returns the shim's own shape and history, so `OCCTTagger` sees exactly what it saw on master. `NamingStabilityTests` and `FeatureConformanceTests` run unchanged as the check.
8. **The test fixture is the kernel-only hexagon flange** (`Tests/CreatorOCCTTests/Support/HexagonFlange.swift`): plate and lifted hexagon without holes. It reproduces the defect without the graph, at the same thresholds.

## Global Constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v26)]`. Strict concurrency; no `@unchecked Sendable`, no new `nonisolated(unsafe)`.
- Tests use **Swift Testing** only (`import Testing`, `@Test`, `#expect`, `#require`).
- One type per Swift file, named after the type; extensions in `Type+Purpose.swift`.
- No force unwraps or force `try`. No GCD. No third-party packages. Numbers shown to people go through `FormatStyle`.
- Module boundaries (CLAUDE.md): only `COCCT`/`CreatorOCCT` touch OCCT. **All OCCT work runs under `OCCTKernel.serialized`, tests included.** Every C allocation has a `*_free`; no C++ exception crosses into Swift (`queried`/`guarded`).
- Shim errors (CLAUDE.md): `set_error`/`user_error` text is user-facing and unprefixed; other OCCT exceptions get "occt: " and `KernelError.plainReason`. The new query reports no text.
- Swift 6.4 crashes with typed throws in a closure returning a tuple (comments in `OCCTKernel.swift`): such closures are written with untyped `throws`.
- `swiftlint lint --strict` reports zero violations.
- Never edit `Package.swift`'s MetalUI path, never modify `../MetalUI`, never take screenshots.

## Review Focus

1. **A blend OCCT builds correctly comes back exactly as before**: same shape, same history, every face tagged. Pinned by `InvalidBlendTests.theRadiusItNamesWorksAndKeepsEveryFaceNamed` (Task 2) and by the unchanged `NamingStabilityTests`/`FeatureConformanceTests`.
2. **The size the message names actually works, downstream included.** Pinned by `theRadiusItNamesWorksAndKeepsEveryFaceNamed`, by `aChamferOCCTBreaksIsRefusedWithTheLargestDistanceThatWorks` (it chamfers at the size it was told) and by the swap test, whose Chamfer and Output succeed at 2.5 (Task 2).
3. **Dragging the radius handle while a search runs**: the superseded evaluation must stop rather than finish its tries. Pinned by `aCancelledSearchStopsBeforeTryingASize` (the search itself) and `aCancelledBlendStopsRatherThanNamingASize` (`blend` → search lets the `CancellationError` through; the `catch is OCCTError` wraps only the first build, and `fillet`/`chamfer` already check cancellation on entry) (Task 2). Both cancel before the call; a cancel arriving mid-search is caught by the same `Task.checkCancellation()` before the next try and isn't pinned separately.
4. **A radius far larger than the part**, up to `.greatestFiniteMagnitude` through the kernel API: no `Int` overflow trap, and the search still ends on a size that works. Pinned by `aRadiusFarBeyondThePartStillFindsOneThatWorks` (Task 2).
5. **Wording when one edge is selected, or when no size works.** Pinned by `theMessagesNameOneEdgeAndSayWhenNoSizeWorks` (Task 2).

---

## File structure

| File | Task | Responsibility |
|---|---|---|
| `Sources/COCCT/include/cocct.h` | 1 | declares `occt_is_valid` |
| `Sources/COCCT/cocct.cpp` | 1 | `occt_is_valid`: `BRepCheck_Analyzer(shape).IsValid()` in `queried` |
| `Sources/CreatorOCCT/OCCTShape.swift` | 1 | `var isValid: Bool` |
| `Tests/CreatorOCCTTests/Support/HexagonFlange.swift` | 1 | fixture: plate ∪ lifted hexagon, its 4 upright edges |
| `Tests/CreatorOCCTTests/ShapeValidityTests.swift` | 1 | the checker on raw shim blends |
| `Sources/CreatorOCCT/OCCTKernel+Blend.swift` | 2 | `blend(…)` (moved from `OCCTKernel.swift`, now checked) and `largestValidBlend(…)` |
| `Sources/CreatorOCCT/KernelError+Blend.swift` | 2 | `blendFailed(size:chamfer:)` (today's text) and `invalidBlend(size:largest:edgeCount:chamfer:)` |
| `Sources/CreatorOCCT/OCCTKernel.swift` | 2 | loses the private `blend` |
| `Tests/CreatorOCCTTests/InvalidBlendTests.swift` | 2 | the kernel's refusal, the search, the messages |
| `Tests/CreatorNodesTests/BracketAcceptanceTests+PolygonSwap.swift` | 2 | the flipped §8 swap test |
| `CLAUDE.md`, roadmap, spec, carry-over note | 3 | the rule, the row, Errata (Kernel: invalid blends) |

---

### Task 1: OCCT's checker in the shim

**Files:**
- Modify: `Sources/COCCT/include/cocct.h` (after `occt_edge_length`)
- Modify: `Sources/COCCT/cocct.cpp` (an include and one function before `occt_fillet_edge`)
- Modify: `Sources/CreatorOCCT/OCCTShape.swift` (after `edgeCount`)
- Create: `Tests/CreatorOCCTTests/Support/HexagonFlange.swift`
- Test: `Tests/CreatorOCCTTests/ShapeValidityTests.swift`

**Interfaces:**
- Consumes: `OCCTShape.blended(edges:size:chamfer:) throws(OCCTError) -> (OCCTShape, [OCCTHistoryRecord])` (existing, `OCCTShape+Operations.swift`); `OCCTKernel.serialized`; `OCCTSolidStorage.shape`; test support `newTag()`, `box(_:_:_:_:)`.
- Produces: C `int occt_is_valid(const occt_shape *shape)` (1 valid, 0 invalid, -1 check failed); Swift `OCCTShape.isValid: Bool` (internal; call under `OCCTKernel.serialized`); test fixture `struct HexagonFlange { let union: Solid; let uprightEdges: [EdgeID]; static func make(_ kernel: any Kernel) async throws -> HexagonFlange }`.

- [ ] **Step 1: Write the fixture and the failing tests**

Create `Tests/CreatorOCCTTests/Support/HexagonFlange.swift`:

```swift
// Test fixture file: spec §8's polygon swap, plate and hexagon flange only, built through the kernel.
import CreatorGeometry
import CreatorKernel

/// The §7.2 bracket's plate (60 × 40, R4 corners, 6 thick) united with §8's hexagon flange (r 15, turned 30° so two
/// sides stand upright, on the XZ plane at y = 20, 8 thick, lifted 15 mm), and the four vertical edges of those two
/// upright sides, which the bracket's Fillet rounds. OCCT builds them at R3 but its checker rejects the solid
/// (spec Errata (Kernel: invalid blends)).
struct HexagonFlange {
    let union: Solid
    let uprightEdges: [EdgeID]

    static func make(_ kernel: any Kernel) async throws -> HexagonFlange {
        let plate = try await kernel.extrude(.roundedRectangle(width: 60, height: 40, radius: 4, plane: .xy), distance: 6,
                                             mode: .oneSided, tag: newTag())
        let hexagon = try await kernel.extrude(.regularPolygon(sides: 6, radius: 15, rotation: .degrees(30),
                                                               plane: Plane.xz.offset(by: -20)),
                                               distance: 8, mode: .oneSided, tag: newTag())
        let lifted = try await kernel.transform(hexagon, by: Transform(translation: Vector3(0, 0, 15)), tag: newTag())
        let union = try await kernel.boolean(.union, plate, [lifted], tag: newTag())
        let upright = union.topology.edges.filter { edge in
            edge.kind == .line && edge.convexity == .convex && !edge.isSeam && abs((edge.direction ?? .zero).dot(.unitZ)) > 0.999
        }
        return HexagonFlange(union: union, uprightEdges: upright.map(\.id))
    }
}
```

Create `Tests/CreatorOCCTTests/ShapeValidityTests.swift`:

```swift
import Testing
@testable import CreatorKernel
@testable import CreatorOCCT

/// `OCCTShape.isValid`, OCCT's own checker, which the kernel runs on every blend (spec Errata (Kernel: invalid blends)).
struct ShapeValidityTests {
    func shape(_ solid: Solid) throws -> OCCTShape {
        try #require((solid.storage as? OCCTSolidStorage)?.shape)
    }

    /// Raw shim blend of the hexagon's upright edges, checked, with no kernel rule in between.
    func blendIsValid(_ flange: HexagonFlange, size: Double, chamfer: Bool) throws -> Bool {
        let union = try shape(flange.union)
        return try OCCTKernel.serialized { () throws -> Bool in
            try union.blended(edges: flange.uprightEdges, size: size, chamfer: chamfer).0.isValid
        }
    }

    @Test func theUnionAndItsSmallerBlendsAreValid() async throws {
        let flange = try await HexagonFlange.make(OCCTKernel())
        #expect(flange.uprightEdges.count == 4)
        let union = try shape(flange.union)
        #expect(OCCTKernel.serialized { union.isValid })
        #expect(try blendIsValid(flange, size: 2.5, chamfer: false))
        #expect(try blendIsValid(flange, size: 2.5, chamfer: true))
    }

    /// The probe's case: OCCT reports both blends done at 3 mm, but each solid has open wires and an unclosed shell.
    @Test(arguments: [false, true])
    func occtBuildsABrokenBlendOfTheUprightEdgesAt3mm(chamfer: Bool) async throws {
        let flange = try await HexagonFlange.make(OCCTKernel())
        #expect(try !blendIsValid(flange, size: 3, chamfer: chamfer))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `swift test --filter ShapeValidityTests`
Expected: build error `value of type 'OCCTShape' has no member 'isValid'`.

- [ ] **Step 3: Add the query to the shim and to `OCCTShape`**

In `Sources/COCCT/include/cocct.h`, replace:

```c
double occt_edge_length(const occt_shape *shape, int index);
```

with:

```c
double occt_edge_length(const occt_shape *shape, int index);
/// 1 when OCCT's checker (BRepCheck_Analyzer, geometry included) accepts the shape as a valid B-rep, 0 when it
/// rejects it, -1 if the check itself fails.
int occt_is_valid(const occt_shape *shape);
```

In `Sources/COCCT/cocct.cpp`, replace:

```cpp
#include "cocct_internal.hpp"

#include <BRepFilletAPI_MakeFillet.hxx>
```

with:

```cpp
#include "cocct_internal.hpp"

#include <BRepCheck_Analyzer.hxx>
#include <BRepFilletAPI_MakeFillet.hxx>
```

In `Sources/COCCT/cocct.cpp`, replace:

```cpp
occt_shape *occt_fillet_edge(const occt_shape *shape, int edge_index, double radius, occt_status *status) {
```

with:

```cpp
int occt_is_valid(const occt_shape *shape) {
    return queried([&]() -> int { return BRepCheck_Analyzer(shape->shape).IsValid() ? 1 : 0; });
}

occt_shape *occt_fillet_edge(const occt_shape *shape, int edge_index, double radius, occt_status *status) {
```

In `Sources/CreatorOCCT/OCCTShape.swift`, replace:

```swift
    var edgeCount: Int { Int(occt_edge_count(raw)) }
```

with:

```swift
    var edgeCount: Int { Int(occt_edge_count(raw)) }
    /// Whether OCCT's own checker (`BRepCheck_Analyzer`) accepts the shape. A check that fails counts as invalid.
    var isValid: Bool { occt_is_valid(raw) == 1 }
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `swift test --filter ShapeValidityTests`
Expected: 2 tests pass (the parameterised one with 2 cases).

- [ ] **Step 5: Full suite and lint**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "built for newer"`. Expected: only `ContextMenuTests.swift`'s existing `underPointer` capture warning.
Run: `swift test 2>&1 | tee /tmp/kib-1.txt; grep -E "recorded an issue|failed after" /tmp/kib-1.txt; grep -c "Test run with" /tmp/kib-1.txt`. Expected (per Prerequisites' "Running the full suite"): exit 0, no matching line (the 8 LF-b known issues are fine), 11 lines, 1370 tests in all.
Run: `swiftlint lint --strict`. Expected: 0 violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/COCCT/include/cocct.h Sources/COCCT/cocct.cpp Sources/CreatorOCCT/OCCTShape.swift \
  Tests/CreatorOCCTTests/Support/HexagonFlange.swift Tests/CreatorOCCTTests/ShapeValidityTests.swift
git commit -m "feat(occt): occt_is_valid and OCCTShape.isValid, OCCT's BRepCheck on a shape"
```

---

### Task 2: The kernel refuses broken blends and names the size that works

**Files:**
- Create: `Sources/CreatorOCCT/OCCTKernel+Blend.swift`
- Create: `Sources/CreatorOCCT/KernelError+Blend.swift`
- Modify: `Sources/CreatorOCCT/OCCTKernel.swift` (delete `private func blend`)
- Test: `Tests/CreatorOCCTTests/InvalidBlendTests.swift`
- Test: `Tests/CreatorNodesTests/BracketAcceptanceTests+PolygonSwap.swift` (the swap test flips)

**Interfaces:**
- Consumes: `OCCTShape.isValid` (Task 1), `HexagonFlange` (Task 1), `OCCTShape.blended(edges:size:chamfer:)`, `OCCTKernel.shape(of:)`, `OCCTKernel.solid(from:history:inputs:tag:operation:)`, `OCCTKernel.serialized`; in the swap test, `BracketAcceptanceTests.makeBracket()`, `swapTheFlangeForAHexagon(in:_:)`, `topCapOutline`, `edgeSet`, `keys`, `expectAllOK` (existing).
- Produces:
  - `extension OCCTKernel { func blend(_ solid: Solid, edges: [EdgeID], size: Double, chamfer: Bool, tag: NodeTag) throws -> Solid }` (internal; `fillet`/`chamfer` already call it);
  - `func largestValidBlend(of source: OCCTShape, edges: [EdgeID], below size: Double, chamfer: Bool) throws -> Double?` (internal, actor-isolated; throws `CancellationError`);
  - `extension KernelError { static func blendFailed(size: Double, chamfer: Bool) -> KernelError; static func invalidBlend(size: Double, largest: Double?, edgeCount: Int, chamfer: Bool) -> KernelError }` (internal to `CreatorOCCT`).

- [ ] **Step 1: Write the failing kernel tests**

Create `Tests/CreatorOCCTTests/InvalidBlendTests.swift`:

```swift
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// The kernel never returns a blend OCCT's own checker rejects; it names the largest size that works instead
/// (spec Errata (Kernel: invalid blends)).
struct InvalidBlendTests {
    func isValid(_ solid: Solid) throws -> Bool {
        let shape = try #require((solid.storage as? OCCTSolidStorage)?.shape)
        return OCCTKernel.serialized { shape.isValid }
    }

    @Test func aFilletOCCTBreaksIsRefusedWithTheLargestRadiusThatWorks() async throws {
        let kernel = OCCTKernel()
        let flange = try await HexagonFlange.make(kernel)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.fillet(flange.union, edges: flange.uprightEdges, radius: 3, tag: newTag())
        }
        #expect(error == .filletFailed(radius: 3, maxRadius: 2.5,
                                       reason: "rounding the 4 selected edges by 3 mm gives a broken solid."))
        #expect(error?.userMessage == "Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm).")
    }

    @Test func theRadiusItNamesWorksAndKeepsEveryFaceNamed() async throws {
        let kernel = OCCTKernel()
        let flange = try await HexagonFlange.make(kernel)
        let filletTag = newTag()
        let filleted = try await kernel.fillet(flange.union, edges: flange.uprightEdges, radius: 2.5, tag: filletTag)
        #expect(try isValid(filleted))
        let keys = flange.uprightEdges.compactMap { flange.union.topology.edge($0).flatMap(flange.union.topology.key(of:)) }
        #expect(keys.count == 4)
        for key in keys {
            #expect(faces(filleted, role: .blend(sourceEdge: key), of: filletTag).count == 1)
        }
        #expect(filleted.topology.faces.allSatisfy { face in !face.tags.contains { if case .unnamed = $0.role { true } else { false } } })
        let before = try await kernel.properties(of: flange.union).volume
        #expect(try await kernel.properties(of: filleted).volume < before)
    }

    @Test func aChamferOCCTBreaksIsRefusedWithTheLargestDistanceThatWorks() async throws {
        let kernel = OCCTKernel()
        let flange = try await HexagonFlange.make(kernel)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.chamfer(flange.union, edges: flange.uprightEdges, distance: 3, tag: newTag())
        }
        #expect(error?.userMessage == "Chamfer failed: chamfering the 4 selected edges by 3 mm gives a broken solid (max ≈ 2.5 mm).")
        let chamfered = try await kernel.chamfer(flange.union, edges: flange.uprightEdges, distance: 2.5, tag: newTag())
        #expect(try isValid(chamfered))
    }

    @Test func aCancelledSearchStopsBeforeTryingASize() async throws {
        let kernel = OCCTKernel()
        let flange = try await HexagonFlange.make(kernel)
        let source = try #require((flange.union.storage as? OCCTSolidStorage)?.shape)
        let search = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.largestValidBlend(of: source, edges: flange.uprightEdges, below: 3, chamfer: false)
        }
        await #expect(throws: CancellationError.self) { try await search.value }
    }

    /// The refused blend's search lets the cancellation through rather than naming a size. `fillet` checks cancellation
    /// on entry, so this calls the shared `blend` it delegates to: the first build runs, the checker refuses it, and the
    /// search's `CancellationError` must reach the caller (the `catch is OCCTError` wraps only the first build).
    @Test func aCancelledBlendStopsRatherThanNamingASize() async throws {
        let kernel = OCCTKernel()
        let flange = try await HexagonFlange.make(kernel)
        let blend = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.blend(flange.union, edges: flange.uprightEdges, size: 3, chamfer: false, tag: newTag())
        }
        await #expect(throws: CancellationError.self) { try await blend.value }
    }

    /// The search starts at the size asked for, so a size far beyond the part (or beyond `Int`) still ends in one that works.
    @Test func aRadiusFarBeyondThePartStillFindsOneThatWorks() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try #require(solid.topology.edges.first { $0.kind == .line && isClose($0.length, 30) })
        let source = try #require((solid.storage as? OCCTSolidStorage)?.shape)
        let largest = try await kernel.largestValidBlend(of: source, edges: [edge.id], below: .greatestFiniteMagnitude,
                                                         chamfer: false)
        let radius = try #require(largest)
        #expect(radius == 9.9, "its narrower face is 10 mm wide")
        let filleted = try await kernel.fillet(solid, edges: [edge.id], radius: radius, tag: newTag())
        #expect(try isValid(filleted))
    }

    @Test func theMessagesNameOneEdgeAndSayWhenNoSizeWorks() {
        #expect(KernelError.invalidBlend(size: 3, largest: nil, edgeCount: 1, chamfer: false).userMessage
            == "Radius 3 mm could not be applied: rounding the selected edge gives a broken solid, even by 0.1 mm.")
        #expect(KernelError.invalidBlend(size: 0.5, largest: nil, edgeCount: 2, chamfer: true).userMessage
            == "Chamfer failed: chamfering the 2 selected edges by 0.5 mm gives a broken solid, even by 0.1 mm.")
        #expect(KernelError.invalidBlend(size: 1.25, largest: 0.7, edgeCount: 1, chamfer: true).userMessage
            == "Chamfer failed: chamfering the selected edge by 1.25 mm gives a broken solid (max ≈ 0.7 mm).")
    }
}
```

- [ ] **Step 2: Flip the polygon swap test**

Replace the whole of `Tests/CreatorNodesTests/BracketAcceptanceTests+PolygonSwap.swift` with:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorOCCT

extension BracketAcceptanceTests {
    /// Spec §8's third naming-stability case (spec Errata (M3), (M6), (naming: merged faces), (Kernel: invalid blends)):
    /// the L-flange's Rectangle swapped for a Regular Polygon on the same plane, a hexagon of radius 15 turned 30° so
    /// two of its sides stand parallel to Z, lifted 15 mm by a Transform so it stands on the plate. What holds, pinned
    /// here:
    /// - the fillet's rule re-derives its edges: 4 again, now the hexagon's vertical side edges on its two caps;
    /// - OCCT builds the bracket's R3 on them but its own checker rejects the solid (`BRepCheck_Analyzer`), so the
    ///   Fillet refuses it with the largest radius that works, 2.5 mm, and the nodes after it wait for an input;
    /// - at that radius every chamfer pick resolves, with no warning: the three that name only plate faces to the same
    ///   edges, and the two on the plate sides the union had merged with the rectangle's coplanar sides, recorded with
    ///   the rectangle's side tags, to the plate's whole side edges by their narrowed keys (`EdgeKey.narrowed`); the
    ///   rectangle's fillet had split each of those edges in two, the hexagon doesn't, and that is not drift
    ///   (`EdgePick.runCount`); the Chamfer succeeds and the Output has its part;
    /// - undoing the radius and the swap brings the rectangle flange, both edge sets and the part back.
    @Test func swappingTheFlangeForAPolygonKeepsEveryPickOnceTheFilletFits() async throws {
        let kernel = OCCTKernel()
        let bracket = Self.makeBracket()
        let document = DocumentModel(file: GraphFile(graph: bracket.graph), registry: BuiltInNodes.registry, kernel: kernel)
        await document.waitForEvaluation()
        let filleted = try #require(document.results[bracket.fillet.id]?.outputs?["solid"]?.solids?.first)
        let picks = filleted.topology.picks(for: topCapOutline(filleted, plate: bracket.plate))
        #expect(picks.count == 5)
        #expect(picks.filter { $0.matchCount == 2 && $0.runCount == 1 }.count == 2, "the two split plate-side edges")
        try document.perform(.setInput(bracket.chamferEdges.id, NodeSetting.picks, .edgePicks(picks)))
        await document.waitForEvaluation()
        expectAllOK(document, "rectangle flange")
        let chamferKeys = keys(try edgeSet(document, bracket.chamferEdges))
        let filletKeys = keys(try edgeSet(document, bracket.filletEdges))

        try swapTheFlangeForAHexagon(in: document, bracket)
        await document.waitForEvaluation()

        let fillet = try edgeSet(document, bracket.filletEdges)
        #expect(fillet.edges.count == 4)
        #expect(keys(fillet) != filletKeys, "the fillet's flange keys are re-derived from the polygon")
        let sideX = 15 * 3.0.squareRoot() / 2   // r cos 30°
        #expect(fillet.edges.allSatisfy { id in
            fillet.solid.topology.edge(id).map { isClose(abs($0.midpoint.x), sideX, relative: 1e-6) } ?? false
        }, "every fillet edge is on one of the hexagon's vertical sides")
        #expect(document.results[bracket.fillet.id]?.state
            == .error("Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm)."))
        let chamferNode = try #require(document.graph.nodes.values.first { $0.typeID == ChamferNode.typeID })
        let waiting = [bracket.chamferEdges.id, chamferNode.id].map { document.results[$0]?.state }
        #expect(waiting.allSatisfy { if case .idle? = $0 { true } else { false } }, "the nodes after the Fillet wait for its solid")
        #expect(document.results[bracket.output.id]?.outputs == nil, "the Output has no part to show or export")

        try document.perform(.setInput(bracket.fillet.id, "radius", .number(2.5)))
        await document.waitForEvaluation()
        expectAllOK(document, "hexagon flange at the radius the Fillet named")
        let chamfer = try edgeSet(document, bracket.chamferEdges)
        #expect(chamfer.edges.count == 5)
        #expect(keys(chamfer) == Set(chamferKeys.map { $0.narrowed ?? $0 }), "the merged-side picks resolve narrowed")
        let outline = chamfer.edges.compactMap { chamfer.solid.topology.edge($0) }
        #expect(outline.allSatisfy { isClose($0.midpoint.z, 6, relative: 1e-9) && $0.midpoint.y <= 1e-6 },
                "the front edge, its corners and the two sides of the plate's top; not its back")
        #expect(outline.filter { isClose($0.length, 32, relative: 1e-9) }.count == 2, "each side edge is whole")
        #expect(document.results[bracket.output.id]?.outputs?["solid"]?.solids?.count == 1)

        document.undo()
        document.undo()
        await document.waitForEvaluation()
        expectAllOK(document, "undone")
        #expect(document.results[bracket.output.id]?.outputs?["solid"]?.solids?.count == 1)
        #expect(keys(try edgeSet(document, bracket.filletEdges)) == filletKeys)
        #expect(keys(try edgeSet(document, bracket.chamferEdges)) == chamferKeys)
    }

    /// Replaces the flange's Rectangle with a hexagon (r 15, turned 30°) lifted 15 mm, as one undo step:
    /// removing the Rectangle drops its three wires, and the lifted flange replaces the old one in the union's
    /// tools.
    func swapTheFlangeForAHexagon(in document: DocumentModel, _ bracket: Bracket) throws {
        var polygon = BuiltInNodes.registry.makeNode(RegularPolygonNode.typeID)
        polygon.inputValues.merge(["sides": .integer(6), "radius": .number(15), "rotation": .number(30)]) { _, new in new }
        var lift = BuiltInNodes.registry.makeNode(TransformNode.typeID)
        lift.inputValues["move"] = .vector(Vector3(0, 0, 15))
        func link(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) -> GraphCommand {
            .connect(Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input)))
        }
        try document.perform(.batch([
            .addNode(polygon), .addNode(lift), .removeNode(bracket.flangeProfile.id),
            link(bracket.flangePlane, "plane", polygon, "plane"), link(polygon, "profile", bracket.flange, "profile"),
            link(bracket.flange, "solid", lift, "solid"), link(lift, "solid", bracket.union, "tools"),
        ]))
    }
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `swift test --filter "InvalidBlendTests|BracketAcceptanceTests"`
Expected: build error, `type 'KernelError' has no member 'invalidBlend'` and `value of type 'OCCTKernel' has no member 'largestValidBlend'`.

- [ ] **Step 4: Move `blend` out of `OCCTKernel.swift`**

In `Sources/CreatorOCCT/OCCTKernel.swift`, replace:

```swift
        return try blend(solid, edges: edges, size: distance, chamfer: true, tag: tag)
    }

    private func blend(_ solid: Solid, edges: [EdgeID], size: Double, chamfer: Bool, tag: NodeTag) throws -> Solid {
        guard size.isFinite, size > 0 else { throw KernelError.invalidInput("The size must be greater than 0 mm.") }
        guard !edges.isEmpty else { throw KernelError.invalidInput("No edges are selected.") }
        if let missing = edges.first(where: { solid.topology.edge($0) == nil }) {
            throw KernelError.invalidInput("Edge \(missing.rawValue) doesn't exist on the input solid.")
        }
        let source = try shape(of: solid)
        let operation = chamfer ? "chamfer" : "fillet"
        return try build(operation, inputs: [solid.topology], tag: tag) {
            do {
                return try source.blended(edges: edges, size: size, chamfer: chamfer)
            } catch is OCCTError {
                if chamfer {
                    let amount = size.formatted(.number.precision(.fractionLength(0...2)))
                    throw KernelError.operationFailed(operation: "chamfer",
                                                      reason: "the selected edges can't be chamfered by \(amount) mm.")
                }
                throw KernelError.filletFailed(radius: size, maxRadius: nil,
                                               reason: "the selected edges can't be rounded this much.")
            }
        }
    }
```

with:

```swift
        return try blend(solid, edges: edges, size: distance, chamfer: true, tag: tag)
    }
```

- [ ] **Step 5: Write the messages**

Create `Sources/CreatorOCCT/KernelError+Blend.swift`:

```swift
import CreatorKernel
import Foundation

extension KernelError {
    /// OCCT couldn't build the blend at all.
    static func blendFailed(size: Double, chamfer: Bool) -> KernelError {
        if chamfer {
            return .operationFailed(operation: "chamfer",
                                    reason: "the selected edges can't be chamfered by \(millimetres(size)) mm.")
        }
        return .filletFailed(radius: size, maxRadius: nil, reason: "the selected edges can't be rounded this much.")
    }

    /// OCCT built the blend but its checker rejects the solid. `largest` is the largest size that gives a valid one,
    /// nil when not even 0.1 mm does.
    static func invalidBlend(size: Double, largest: Double?, edgeCount: Int, chamfer: Bool) -> KernelError {
        let edges = edgeCount == 1 ? "the selected edge" : "the \(edgeCount) selected edges"
        if chamfer {
            let limit = largest.map { " (max ≈ \(millimetres($0)) mm)" } ?? ", even by 0.1 mm"
            return .operationFailed(operation: "chamfer",
                                    reason: "chamfering \(edges) by \(millimetres(size)) mm gives a broken solid\(limit).")
        }
        let reason = largest == nil
            ? "rounding \(edges) gives a broken solid, even by 0.1 mm."
            : "rounding \(edges) by \(millimetres(size)) mm gives a broken solid."
        return .filletFailed(radius: size, maxRadius: largest, reason: reason)
    }

    private static func millimetres(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
```

- [ ] **Step 6: Write the checked blend and the search**

Create `Sources/CreatorOCCT/OCCTKernel+Blend.swift`:

```swift
import CreatorKernel

extension OCCTKernel {
    /// Fillets or chamfers `edges` (spec §5.2). OCCT can report a blend done yet return a solid its own checker rejects
    /// (spec §8's hexagon flange at R3, Errata (Kernel: invalid blends)); every later blend on such a solid fails. So a
    /// result `OCCTShape.isValid` rejects is never returned: the blend fails, naming the largest size that works.
    func blend(_ solid: Solid, edges: [EdgeID], size: Double, chamfer: Bool, tag: NodeTag) throws -> Solid {
        guard size.isFinite, size > 0 else { throw KernelError.invalidInput("The size must be greater than 0 mm.") }
        guard !edges.isEmpty else { throw KernelError.invalidInput("No edges are selected.") }
        if let missing = edges.first(where: { solid.topology.edge($0) == nil }) {
            throw KernelError.invalidInput("Edge \(missing.rawValue) doesn't exist on the input solid.")
        }
        let source = try shape(of: solid)
        let built: (OCCTShape, [OCCTHistoryRecord])?
        do {
            // Untyped throws on purpose, as in `build`: Swift 6.4 crashes with typed throws returning a tuple.
            built = try Self.serialized { () throws -> (OCCTShape, [OCCTHistoryRecord])? in
                let result = try source.blended(edges: edges, size: size, chamfer: chamfer)
                return result.0.isValid ? result : nil
            }
        } catch is OCCTError {
            throw KernelError.blendFailed(size: size, chamfer: chamfer)
        }
        guard let built else {
            let largest = try largestValidBlend(of: source, edges: edges, below: size, chamfer: chamfer)
            throw KernelError.invalidBlend(size: size, largest: largest, edgeCount: edges.count, chamfer: chamfer)
        }
        return try self.solid(from: built.0, history: built.1, inputs: [solid.topology], tag: tag,
                              operation: chamfer ? "chamfer" : "fillet")
    }

    /// The largest size below `size`, on a 0.1 mm grid, whose blend OCCT builds and its checker accepts; nil when not
    /// even 0.1 mm does. It bisects, assuming every size above one that fails fails too; the size it returns was built
    /// and checked. Each try takes the OCCT lock on its own, and a cancelled evaluation stops between tries.
    func largestValidBlend(of source: OCCTShape, edges: [EdgeID], below size: Double, chamfer: Bool) throws -> Double? {
        var works = 0
        // In tenths of a millimetre; capped so a huge size can't overflow `Int` (sizes above it are never tried).
        var fails = Int(min((size * 10).rounded(.up), 1_000_000))
        while fails - works > 1 {
            try Task.checkCancellation()
            let tenths = (works + fails) / 2
            let valid = Self.serialized { () -> Bool in
                (try? source.blended(edges: edges, size: Double(tenths) / 10, chamfer: chamfer))?.0.isValid ?? false
            }
            if valid { works = tenths } else { fails = tenths }
        }
        return works > 0 ? Double(works) / 10 : nil
    }
}
```

- [ ] **Step 7: Run the tests to see them pass**

Run: `swift test --filter "InvalidBlendTests|ShapeValidityTests|FeatureConformanceTests|NamingStabilityTests|BracketAcceptanceTests"`
Expected: all pass. `swappingTheFlangeForAPolygonKeepsEveryPickOnceTheFilletFits` takes about a second (the search runs 5 tries from 3 mm).

- [ ] **Step 8: Full suite and lint**

Run: `swift build --build-tests 2>&1 | grep -E "warning:|error:" | grep -v "built for newer"`. Expected: only the existing `ContextMenuTests` warning.
Run: `swift test 2>&1 | tee /tmp/kib-2.txt; grep -E "recorded an issue|failed after" /tmp/kib-2.txt; grep -c "Test run with" /tmp/kib-2.txt`. Expected (per Prerequisites' "Running the full suite"): exit 0, no matching line, 11 lines, 1377 tests in all.
Run: `swiftlint lint --strict`. Expected: 0 violations.

- [ ] **Step 9: Commit**

```bash
git add Sources/CreatorOCCT/OCCTKernel.swift Sources/CreatorOCCT/OCCTKernel+Blend.swift \
  Sources/CreatorOCCT/KernelError+Blend.swift Tests/CreatorOCCTTests/InvalidBlendTests.swift \
  Tests/CreatorNodesTests/BracketAcceptanceTests+PolygonSwap.swift
git commit -m "fix(occt): refuse a fillet or chamfer OCCT's checker rejects, naming the largest size that works"
```

---

### Task 3: The rule, the row and the errata

**Files:**
- Modify: `CLAUDE.md` (one sentence after "Shim errors")
- Modify: `docs/superpowers/roadmap.md` (the row, plus one new row)
- Modify: `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` (append Errata (Kernel: invalid blends))
- Modify: `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md` (the "From M6" polygon bullet)

**Interfaces:**
- Consumes: the names from Tasks 1–2 (`OCCTShape.isValid`, `occt_is_valid`, `OCCTKernel.largestValidBlend`, `KernelError.invalidBlend`, the renamed swap test).
- Produces: documentation only.

- [ ] **Step 1: CLAUDE.md**

In `CLAUDE.md`, replace:

```markdown
Shim errors: `cocct::user_error` / `set_error` messages are user-facing and unprefixed; any other OCCT exception is prefixed "occt: " by `guarded` and mapped to a generic sentence by `KernelError.plainReason`.
```

with:

```markdown
Shim errors: `cocct::user_error` / `set_error` messages are user-facing and unprefixed; any other OCCT exception is prefixed "occt: " by `guarded` and mapped to a generic sentence by `KernelError.plainReason`.
Every fillet and chamfer result is checked with OCCT's `BRepCheck_Analyzer` (`OCCTShape.isValid`) and never returned when
the check rejects it: the blend fails naming the largest size that works (`OCCTKernel.largestValidBlend`, spec Errata
(Kernel: invalid blends)).
```

- [ ] **Step 2: Roadmap**

In `docs/superpowers/roadmap.md`, replace:

```markdown
| — | Kernel: blends that return an invalid solid — OCCT's fillet of the polygon-swap hexagon's vertical edges reports done but returns a solid `BRepCheck_Analyzer` rejects, so every later fillet or chamfer along the plate top's tangent chain fails (Errata (naming: merged faces)); `BRepCheck`-valid at R 0.5, 1 and 2, where the chamfer succeeds; through the graph the chamfer also succeeds at R 2.5; invalid at the bracket's R3; reject such a result with a plain message, or repair it | ⏳ | `BracketAcceptanceTests+PolygonSwap` (its Chamfer error and missing Output flip when fixed) |
```

with:

```markdown
| — | Kernel: blends that return an invalid solid — OCCT's fillet of the polygon-swap hexagon's vertical edges reports done but returns a solid `BRepCheck_Analyzer` rejects, so every later fillet or chamfer along the plate top's tangent chain fails (Errata (naming: merged faces)) | ✅ code done (plan `2026-10-09-kernel-invalid-blends.md`, Errata (Kernel: invalid blends)): every fillet and chamfer result is checked (`OCCTShape.isValid`); one OCCT's checker rejects is refused, naming the largest size that works ("Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm)."); repair was probed (ShapeFix, UnifySameDomain, tolerances, fillet shapes and parameters, edge order) and can't make it valid | `BracketAcceptanceTests+PolygonSwap` (flipped: the Fillet names 2.5 mm; at 2.5 mm the Chamfer and the Output have their part), `InvalidBlendTests`, `ShapeValidityTests` |
| — | Kernel: largest size for blends OCCT can't build — a fillet or chamfer OCCT reports not done still says "can't be rounded this much" without a maximum (spec §3, risks table: "the maximum radius where possible"); `OCCTKernel.largestValidBlend` could name one there too, at the cost of up to ~20 failing tries | ⏳ | `FeatureConformanceTests.impossibleFilletFailsCleanlyAndKernelRecovers` (its `maxRadius` would become 9.9) |
```

- [ ] **Step 3: Spec errata**

Append to `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`:

```markdown

## Errata (Kernel: invalid blends)

Plan `2026-10-09-kernel-invalid-blends.md`, roadmap row "Kernel: blends that return an invalid solid".

- §5.2: the OCCT kernel checks every fillet and chamfer result with OCCT's own checker (`BRepCheck_Analyzer`, geometry
  included: `occt_is_valid`, `OCCTShape.isValid`) and never returns one it rejects. OCCT can report a blend done and
  still return such a solid: §8's hexagon flange, its four upright edges at the bracket's R3 (a chamfer of 3 mm too;
  both are valid at 2.5 mm and below). That solid has wires not closed in their faces, an unclosed shell, vertex
  tolerances near 5 mm and a wrong volume (on the §7.2 bracket, holes included, about 1900 mm³ below what a valid
  fillet would leave; on a hole-free plate and hexagon, about 1800 mm³ above), and every later blend along its
  tangent chains fails.
- It isn't repaired. The plan's probe tried `ShapeFix_Shape` (default and with tight tolerances),
  `ShapeUpgrade_UnifySameDomain`, `ShapeFix_ShapeTolerance::LimitTolerance`, `BRepLib::SameParameter`, the other
  fillet shapes (quasi-angular, polynomial), tighter and looser `SetParams`, filleting one edge at a time and fixing
  the input first: none gives a valid solid, and ShapeFix changes its volume. A blend that passes is returned as
  built, with its history, so its faces keep every tag (§5.3 is unchanged).
- §3's errors: a refused blend names the largest size below the one asked for, on a 0.1 mm grid, that OCCT builds and
  its checker accepts (`OCCTKernel.largestValidBlend`: a bisection of at most 20 tries, each under the OCCT lock on its
  own, stopping when the evaluation is cancelled; it assumes every size above a failing one fails too, and the size it
  names was built and checked). A fillet reads "Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm)."; a
  chamfer "Chamfer failed: chamfering the 4 selected edges by 3 mm gives a broken solid (max ≈ 2.5 mm)."; when not even
  0.1 mm works, "…gives a broken solid, even by 0.1 mm.". The fillet message with a maximum is §3's own wording and
  doesn't name the edge count on purpose (the error's `reason` keeps it); the others do. A blend OCCT can't build at all keeps its message, with no
  maximum (roadmap row "Kernel: largest size for blends OCCT can't build").
- Errata (naming: merged faces)'s polygon swap: at R3 the Fillet is now the node in error, naming 2.5 mm, and the Edges
  by Tag, Chamfer and Output after it wait for its solid. With the radius at 2.5 every node is `.ok`: the five picks
  resolve as that errata says, the Chamfer succeeds and the Output has its part.
  `BracketAcceptanceTests.swappingTheFlangeForAPolygonKeepsEveryPickOnceTheFilletFits` pins it (it replaces
  `swappingTheFlangeForAPolygonKeepsEveryPickButTheFilletedHexagonCantBeChamfered`).
```

- [ ] **Step 4: Carry-over note**

In `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`, replace:

```markdown
  counts runs as well as edges (`EdgePick.runCount`). The Chamfer still fails there, because OCCT's fillet of the
  hexagon returns an invalid solid (spec Errata (naming: merged faces)). Owner of that: roadmap row "Kernel: blends
  that return an invalid solid"; face picks on merged faces: roadmap row "Naming: face picks on merged faces".
```

with:

```markdown
  counts runs as well as edges (`EdgePick.runCount`). ✅ (kernel-invalid-blends plan) OCCT's R3 fillet of the hexagon
  returns a solid its checker rejects; the kernel now refuses it and the Fillet names the largest radius that works,
  2.5 mm, at which the Chamfer and the Output have their part (spec Errata (Kernel: invalid blends)). Face picks on
  merged faces: roadmap row "Naming: face picks on merged faces".
```

- [ ] **Step 5: Check**

Run: `grep -n "Kernel: invalid blends" CLAUDE.md docs/superpowers/roadmap.md docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`
Expected: at least one line from each file.
Run: `swift test 2>&1 | tee /tmp/kib-3.txt; grep -E "recorded an issue|failed after" /tmp/kib-3.txt; grep -c "Test run with" /tmp/kib-3.txt` and `swiftlint lint --strict`. Expected: as Task 2 (1377 tests, 11 lines, 0 violations).

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md docs/superpowers/roadmap.md docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md \
  docs/superpowers/notes/2026-10-07-m0-m1-carryover.md
git commit -m "docs(kernel): Errata (Kernel: invalid blends), roadmap rows, CLAUDE.md rule"
```

---

## Risks

- **MetalUI moved under this track.** The live `../MetalUI` keeps moving (at review `2155f1e`, which contains LF-b's fix `9ad2254`). Built against it, master's `CanvasClipRenderTests.aNodeAtANegativeCanvasPositionDrawsWhole` records "Known issue was not recorded" issues, from known issues that no longer happen, which trips the gate's "recorded an issue" rule for reasons unrelated to this plan. It isn't fixed here (the LF-b track owns removing the `withKnownIssue`), and `../MetalUI` and `Package.swift`'s MetalUI path stay untouched. Until it is, use Prerequisites' "Running the full suite": a scratch copy beside a `git archive 0b400b4` MetalUI, or count only issues outside `CanvasClipRenderTests` and report those to the LF-b owner.
- **The bisection assumes monotonic failure.** If OCCT fails at some size and works at a larger one, the search can name a smaller size than the largest that works. It never names one that fails, because every returned size was built and checked.
- **Cost.** `BRepCheck_Analyzer` now runs on every fillet and chamfer: about 3-4 ms per check on the hexagon flange's blend result (about 2 ms on its union), measured at review. That is paid on every drag step of a radius handle. A refused blend costs up to about 20 extra blend tries; the swap's costs 5. Each try releases the OCCT lock, so other kernels' OCCT work can interleave, but `largestValidBlend` is synchronous on the `OCCTKernel` actor, so this kernel (its tessellation, measuring and later blends) stays busy until the search ends or the evaluation is cancelled (checked between tries).
- **An invalid input blames the blend.** Only the output is checked. If the solid coming in is already invalid (say from a broken boolean, which isn't checked: Decision 3), every fillet or chamfer on it is refused after the search (up to about 20 tries) as "…gives a broken solid, even by 0.1 mm.", naming the blend and its size rather than the real cause. None was seen (Probe 6: every existing result is valid). Checking `source.isValid` on the failure path, with its own "input solid is invalid" message, belongs with the row that checks other operations.
- **A size under 0.1 mm.** When the size asked for is below 0.1 mm (say 0.05) and its result is refused, the search range is empty and the message still says "even by 0.1 mm", a size larger than the one asked for. No size is tried then, so the message claims more than was checked. Accepted as an edge case: a blend that small is not realistic, and any size on the 0.1 mm grid would be at least as large as the one refused.
- **A check that throws counts as invalid** (`queried` → -1). A shape OCCT can't even check would be refused as "a broken solid", which is the safer side.
- **Other operations aren't checked.** A boolean, extrude or transform that OCCT returns broken would still pass silently. None was seen. Extending the check (and choosing the message) is its own row if one appears.
- **OCCT-version dependence.** The thresholds (2.5 mm here, 9.9 mm on the box) are OCCT 7.9's. A Homebrew OCCT upgrade may move them, and `InvalidBlendTests`/the swap test pin them exactly, on purpose: a change there means re-probing.

## Self-review

- **Row coverage.** "Reject such a result with a plain message, or repair it": repair probed and refused with evidence (Probe 3–5); rejection with a plain message naming the sizes, and the edge count except in §3's own fillet wording (Decision 5; Task 2). "Never return an invalid solid silently": every blend is checked (Task 2's `blend`). "Keep face/edge tags and history through any repair": nothing is repaired; passing blends return the shim's own history (Decision 7, Review Focus 1). "All work under `OCCTKernel.serialized`": the check runs inside the blend's own `serialized` call and each search try in its own; tests call `isValid` only inside `serialized`. "Shim errors per CLAUDE.md": the query reports no text; the not-built messages are unchanged (`blendFailed`). "Test to flip": `swappingTheFlangeForAPolygonKeepsEveryPickOnceTheFilletFits` (Task 2).
- **Placeholders:** none; every code step has its complete code.
- **Type consistency:** `isValid`, `HexagonFlange.union`/`uprightEdges`, `largestValidBlend(of:edges:below:chamfer:)`, `KernelError.blendFailed(size:chamfer:)` and `invalidBlend(size:largest:edgeCount:chamfer:)` are spelled the same in every task.
- **Review Focus:** each of the five lines has its test in Task 2.
