# Kernel: Largest Size for Blends OCCT Can't Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A fillet or chamfer OCCT reports not done names the largest size that works ("max ≈ 9.9 mm"), as one OCCT builds but its checker rejects already does; the invalid-blends review's four minors are folded in; the cost of a refused blend is measured and recorded.

**Architecture:** `OCCTKernel.blend` sorts one try into four outcomes (built, rejected by the checker, checker threw, not built). Rejected and not built both run `largestValidBlend`; a checker that threw gets the generic message. The search's grid arithmetic and the "even by 0.1 mm" rule move into a small `BlendGrid` enum so the `ceil` overshoot and the clause cannot disagree. `occt_is_valid`'s three answers become `OCCTValidity`.

**Tech Stack:** Swift 6 strict concurrency, Swift Testing, the `COCCT` shim (unchanged), `swiftlint lint --strict`.

**Spec:** `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata: §3 (errors: "max ≈ where possible"), §5.2 (fillet and chamfer), §10 risks table ("OCCT fillets fail for some radii: clear errors with the maximum radius where possible"), and Errata (Kernel: invalid blends), which this completes. Roadmap row: `docs/superpowers/roadmap.md` "Kernel: largest size for blends OCCT can't build". Read first: `Sources/CreatorOCCT/OCCTKernel+Blend.swift`, `KernelError+Blend.swift`, `Tests/CreatorOCCTTests/InvalidBlendTests.swift`, and the Errata above.

**Branch / worktree:** `kernel-blend-max` at `/Users/maxburger/Developer/MetalCreator-blendmax`, off master `4e4be6e` (1643 tests). Run every command from the worktree; never `cd` to another worktree; never edit `Package.swift`'s MetalUI path; never modify `../MetalUI`; take no screenshots.

## Files shared with other tracks

Parallel tracks: groups-comments, groups-editor, sketcher-s5c, adopt-c10, naming-face-picks (CreatorKernel picks), viewport-final-edges. No other track is known to touch `Sources/CreatorOCCT/OCCTKernel+Blend.swift`, `KernelError+Blend.swift`, `InvalidBlendTests.swift` or the new files, but these documents are edited by every track. **The side that merges second keeps both sides' edits** in each:

| File | What this plan changes | What the second merger must keep |
|---|---|---|
| `docs/superpowers/roadmap.md` | rewrites one row (the "Kernel: largest size for blends OCCT can't build" row) | every other track's own row edit; resolve line by line, never take a whole-file side |
| `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` | one sentence edited in Errata (Kernel: invalid blends); one new section "Errata (Kernel: largest size for blends OCCT can't build)" inserted between that section and "Errata (multi-select)" | every other track's new Errata section (they append elsewhere or at the end), and this section's heading and bullets intact |
| `CLAUDE.md` | extends the one paragraph about `OCCTShape.isValid` / `largestValidBlend` (about line 156) | other tracks' status lines and paragraphs; the extended paragraph |
| `docs/verification/performance.md` | the "How to run" suite list gains `BlendRefusalBench`; a new section "Refused blends" before "Raw output" | other tracks' rows and sections; the union of the suite names in "How to run" |
| `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md` | appends a section at the end | other tracks' appended sections (both stay; order doesn't matter) |
| `docs/verification/human-checks.md` | adds one check, M6-15 (planned as an extension of M5-10's Fillet radius sentence) | other tracks' new and changed checks; if both sides edited M6-15, keep both sides' sentences in it |
| `Tests/CreatorOCCTTests/FeatureConformanceTests.swift` | one test's assertions (`impossibleFilletFailsCleanlyAndKernelRecovers`) | any other test in the file |
| `Tests/CreatorAppTests/Bench/` | adds `BlendRefusalBench.swift` and `BlendRefusalFixtureTests.swift` only | other benchmark files |

No new MetalUI gap: nothing here touches MetalUI.

No command, undo or `.mcgraph` change: the file format stays at version 5, and the error text this plan changes is not persisted (it is recomputed on every evaluation). Undo granularity is untouched (no command is added or changed).

## Global Constraints

- CLAUDE.md: Swift 6 strict concurrency; Swift Testing; `@MainActor @Observable` models (none are added); behaviour in models and thin views; one type per file (a private nested type is fine); no force unwraps; no GCD; `FormatStyle` for numbers (messages use `value.formatted(.number.precision(.fractionLength(0...2)))`); `swiftlint lint --strict` with zero violations (cyclomatic complexity 10 is enforced: `blend` is split into helpers for it).
- Only `COCCT` + `CreatorOCCT` may touch OCCT. The shim is not changed.
- Every user-facing message stays plain: no OCCT text, no "BRepCheck", no jargon.
- MetalUI gaps go in `docs/metalui-gaps.md` (entry and summary row), are never worked around. This plan finds none.
- Test counts are "master + N" (master has 1643). A full `swift test` passes only if the exit code is 0, no line says "recorded an issue" or "failed after" (Swift Testing prints glyphs, not ✘), and 11 "Test run with" lines appear. Skipped benchmark suites count as tests.
- A build warning is new if it names a file this plan touched. The linker warnings `ld: warning: building for macOS-26.0, but linking with dylib … opencascade …` and `ContextMenuTests.swift:96 'underPointer' mutated after capture` (CreatorViewportTests) exist on master.

## Review Focus

Failure modes the spec implies but a plain happy-path test would not exercise, most likely first. Each has a test in the task named.

1. A refused blend whose requested size is 0.1 mm or less must not say "even by 0.1 mm" (it never tried 0.1 mm): Task 2, `aSizeNoLargerThanTheSmallestOneDoesNotClaimToHaveTriedIt`.
2. A computed size a hair off the grid (`0.1 + 0.2`) must name a size below it, not itself: Task 2, `aSizeAHairOverTheGridNamesTheOneBelowIt` and `BlendGridTests`.
3. A checker that throws (`occt_is_valid` = -1) must give the generic message and run no search: Task 1, `aCheckerThatThrowsGivesTheGenericMessageInsteadOfASearch` (it counts the checker's calls: the search checks every try, so exactly one call means no search ran).
4. Cancelling an evaluation while the new (not-built) search runs must end in `CancellationError`, never a half-searched maximum: Task 3, `aCancelledBlendOCCTCantBuildStopsRatherThanNamingASize`.
5. A size far beyond the part (1e9 mm) must name the same maximum after the same few tries, with no `Int` overflow: Task 3, `aRadiusFarBeyondThePartNamesTheSameMaximum`.
6. A blend that fails at every size (the search finds none) keeps today's message with no maximum, through `blend`'s own wiring and not only at the message level: Task 1, `aCheckerThatRejectsEverySizeFindsNoMaximum` (the rejected path, via the `check:` seam), and Task 3, `aBlendNoSizeCanBuildKeepsTheGenericMessage` (the not-built path, on a real input: the vertical edge of a 0.1 mm square post, which no size from 0.1 mm up blends), with `theMessagesAddTheMaximumOnlyWhenOneWasFound` for the wording.
7. The benchmark's copy of the hexagon flange must stay the original: Task 4, `BlendRefusalFixtureTests.theBenchFlangeIsTheOneThatBreaksAtR3` (four upright edges, R3 refused naming 2.5 mm), run by a plain `swift test`.

---

## Decisions in this plan

- **Where the search lives:** `OCCTKernel.blend` calls `largestValidBlend` for both a rejected result and a not-built one. The not-built search assumes monotonicity like the existing one (a size that fails, every larger one fails); the size it names was built and checked, so a wrong assumption can only make the maximum smaller than the true one, never invalid.
- **`OCCTValidity`** (`valid`, `invalid`, `unchecked`) replaces the bare Bool at the blend; `OCCTShape.isValid` stays (`validity == .valid`) for the other callers and for tests.
- **A test seam, `check:`.** `blend` and `largestValidBlend` take `check: (OCCTShape) -> OCCTValidity = { $0.validity }` so a test can stand in for a checker that throws (no real shape reproduces that), reject every size, or count its calls (the search checks every try it makes, so a count of one proves no search ran).
- **`BlendGrid`** holds `step` (0.1), `mostTenths` (1_000_000), `firstFailingTenths(for:)` = `Int(min((size * 10 - 1e-9).rounded(.up), 1_000_000))` and `triesSmallest(below:)`. The message and the search read the same function, so "even by 0.1 mm" is said exactly when 0.1 mm was tried.
- **Off-grid sizes:** the 1e-9 slack in `firstFailingTenths` treats a size within 1e-9 above a grid value as that value, so for an off-grid size the maximum named is conservative (a step below a size that would still build). Harmless; a comment in `BlendGrid` says so, and `aSizeAHairOverTheGridNamesTheOneBelowIt` pins it.
- **Size ≤ 0.1 mm:** the clause is left out (see User decisions below); "at any size" would claim more than was tried.
- **Measurement:** `BlendRefusalBench` (a new suite in `Tests/CreatorAppTests/Bench`, run by `scripts/bench.sh BlendRefusalBench`), on the §8 flange at kernel level and the §7.2 bracket's Fillet node at app level. The figures are written in `docs/verification/performance.md` only; every other record says "tens of milliseconds" so a re-measure on an idle machine changes one file. `BlendRefusalFixtureTests` keeps the bench's flange copy equal to `HexagonFlange`.
- **Human check:** the one visible change, a refused Fillet radius drag now naming a maximum with a search on every step, is human check M6-15 (run in the app on the bracket with the real kernel; first planned as an addition to M5-10, moved by commit 008159f because Group M5 runs in a preview without the real kernel).

## User decisions (approved 2026-10-09, all recommended defaults)

The user approved this plan's decisions on 2026-10-09 with "go with your recommended defaults": the sizes-at-or-below-0.1 mm wording (clause left out), the 1e-9 slack on the grid (conservative for off-grid sizes), the search for a not-built blend too, `OCCTValidity` and the `check:` seam, the benchmark figures kept in `performance.md` only, and the drag check as a human check (M6-15, see Decisions above).

## File structure

| File | Change | Responsibility |
|---|---|---|
| `Sources/CreatorOCCT/OCCTValidity.swift` | create | the checker's three answers |
| `Sources/CreatorOCCT/OCCTShape.swift` | modify | `validity`; `isValid` derives from it |
| `Sources/CreatorOCCT/BlendGrid.swift` | create | the search's grid arithmetic and the "tried 0.1 mm" rule |
| `Sources/CreatorOCCT/OCCTKernel+Blend.swift` | modify | attempt sorting, the two searches, `check:` seam |
| `Sources/CreatorOCCT/KernelError+Blend.swift` | modify | `blendFailed(size:chamfer:largest:)`, the 0.1 mm clause |
| `Tests/CreatorOCCTTests/OCCTValidityTests.swift` | create | status mapping |
| `Tests/CreatorOCCTTests/BlendGridTests.swift` | create | grid arithmetic |
| `Tests/CreatorOCCTTests/UnbuildableBlendTests.swift` | create | the not-built search |
| `Tests/CreatorOCCTTests/InvalidBlendTests.swift` | modify | checker-threw, 0.1 mm and off-grid cases |
| `Tests/CreatorOCCTTests/FeatureConformanceTests.swift` | modify | `maxRadius` 9.9 |
| `Tests/CreatorAppTests/Bench/BlendRefusalBench.swift` | create | the cost of a refused blend |
| `Tests/CreatorAppTests/Bench/BlendRefusalFixtureTests.swift` | create | the bench's flange copy still matches `HexagonFlange` (runs in every `swift test`) |
| roadmap, spec, `CLAUDE.md`, `performance.md`, carry-over note, `human-checks.md` | modify | records |

## Verification recipe (every task)

After a task's last code step, from the worktree:

```bash
swift build --build-tests 2>&1 | grep 'warning:' | grep -v 'ld: warning'   # expect nothing naming a file you touched
swift test > "$TMPDIR/blend-test.log" 2>&1; echo "exit $?"                   # expect exit 0
grep -c 'recorded an issue\|failed after' "$TMPDIR/blend-test.log"          # expect 0
grep -c 'Test run with' "$TMPDIR/blend-test.log"                            # expect 11
grep 'Test run with' "$TMPDIR/blend-test.log" | sed -E 's/.*with ([0-9]+) tests.*/\1/' | paste -sd+ - | bc   # the total
swiftlint lint --strict                                                      # expect "Found 0 violations, 0 serious"
```

Compare the total to the task's "master + N".

---

### Task 1: The checker's three answers; a checker that throws gets the generic message

**Files:**
- Create: `Sources/CreatorOCCT/OCCTValidity.swift`
- Modify: `Sources/CreatorOCCT/OCCTShape.swift` (the `isValid` property, line ~31)
- Modify: `Sources/CreatorOCCT/OCCTKernel+Blend.swift` (whole file replaced below)
- Create: `Tests/CreatorOCCTTests/OCCTValidityTests.swift`
- Modify: `Tests/CreatorOCCTTests/InvalidBlendTests.swift`

**Interfaces:**
- Consumes: `occt_is_valid(raw) -> Int32` (1 valid, 0 invalid, -1 the checker threw); `OCCTKernel.serialized`; `KernelError.blendFailed(size:chamfer:)` (unchanged in this task).
- Produces: `enum OCCTValidity: Equatable, Sendable { case valid, invalid, unchecked; init(status: Int32) }`; `OCCTShape.validity: OCCTValidity`; `OCCTKernel.blend(_:edges:size:chamfer:tag:check:)` and `OCCTKernel.largestValidBlend(of:edges:below:chamfer:check:)`, each with `check: (OCCTShape) -> OCCTValidity = { $0.validity }`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorOCCTTests/OCCTValidityTests.swift`:

```swift
import Testing
@testable import CreatorOCCT

/// `occt_is_valid` answers 1, 0 or -1 (the checker itself threw); the kernel tells the last from a rejection.
struct OCCTValidityTests {
    @Test func theCheckersAnswerMapsToThreeStates() {
        #expect(OCCTValidity(status: 1) == .valid)
        #expect(OCCTValidity(status: 0) == .invalid)
        #expect(OCCTValidity(status: -1) == .unchecked)
    }

    @Test func aBoxIsValidAndIsValidAgreesWithValidity() throws {
        let box = try OCCTShape.box(10, 20, 30)
        let validity = OCCTKernel.serialized { box.validity }
        #expect(validity == .valid)
        #expect(OCCTKernel.serialized { box.isValid })
    }
}
```

In `InvalidBlendTests.swift`, add `import Synchronization` above `import Testing`, and add this inside the struct before `theMessagesNameOneEdgeAndSayWhenNoSizeWorks`:

```swift
    /// Counts the checker's calls from a closure the kernel runs on its own actor.
    final class CheckCount: Sendable {
        let calls = Mutex(0)
        func record() { calls.withLock { $0 += 1 } }
    }

    /// A checker that throws says nothing about any size: the blend fails with the generic message and no search runs.
    /// The search checks every try it makes, so exactly one call to the checker means no search ran.
    @Test func aCheckerThatThrowsGivesTheGenericMessageInsteadOfASearch() async throws {
        let kernel = OCCTKernel()
        let flange = try await HexagonFlange.make(kernel)
        let count = CheckCount()
        let error = await #expect(throws: KernelError.self) {
            try await kernel.blend(flange.union, edges: flange.uprightEdges, size: 3, chamfer: false, tag: newTag()) { _ in
                count.record()
                return .unchecked
            }
        }
        #expect(error == .filletFailed(radius: 3, maxRadius: nil, reason: "the selected edges can't be rounded this much."))
        #expect(count.calls.withLock { $0 } == 1)
        let chamfer = await #expect(throws: KernelError.self) {
            try await kernel.blend(flange.union, edges: flange.uprightEdges, size: 3, chamfer: true, tag: newTag()) { _ in
                count.record()
                return .unchecked
            }
        }
        #expect(chamfer?.userMessage == "Chamfer failed: the selected edges can't be chamfered by 3 mm.")
        #expect(count.calls.withLock { $0 } == 2)
    }

    /// A checker that rejects every size leaves the search nothing to name: the message keeps no maximum, and says "even
    /// by 0.1 mm" because the search did try it. (The not-built path has its own wiring of `largest`; see
    /// `UnbuildableBlendTests.aBlendNoSizeCanBuildKeepsTheGenericMessage`.)
    @Test func aCheckerThatRejectsEverySizeFindsNoMaximum() async throws {
        let kernel = OCCTKernel()
        let flange = try await HexagonFlange.make(kernel)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.blend(flange.union, edges: flange.uprightEdges, size: 3, chamfer: false, tag: newTag()) { _ in .invalid }
        }
        #expect(error == .filletFailed(radius: 3, maxRadius: nil,
                                       reason: "rounding the 4 selected edges gives a broken solid, even by 0.1 mm."))
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift build --build-tests 2>&1 | grep error:`
Expected: `cannot find 'OCCTValidity' in scope` and an extra argument in `blend`'s call.

- [ ] **Step 3: Implement**

`Sources/CreatorOCCT/OCCTValidity.swift`:

```swift
/// What OCCT's checker (`BRepCheck_Analyzer`, via `occt_is_valid`) says about a shape.
enum OCCTValidity: Equatable, Sendable {
    /// The checker accepts the shape.
    case valid
    /// The checker ran and rejects the shape.
    case invalid
    /// The checker itself threw (`occt_is_valid` returned -1): the shape is neither known good nor known bad.
    case unchecked

    /// Reads `occt_is_valid`'s result: 1 valid, 0 invalid, anything else (-1) unchecked.
    init(status: Int32) {
        switch status {
        case 1: self = .valid
        case 0: self = .invalid
        default: self = .unchecked
        }
    }
}
```

`Sources/CreatorOCCT/OCCTShape.swift`:

```diff
diff --git a/Sources/CreatorOCCT/OCCTShape.swift b/Sources/CreatorOCCT/OCCTShape.swift
index b35908e..7c40950 100644
--- a/Sources/CreatorOCCT/OCCTShape.swift
+++ b/Sources/CreatorOCCT/OCCTShape.swift
@@ -28,8 +28,10 @@ final class OCCTShape: Sendable {
     var volume: Double { occt_volume(raw) }
     var faceCount: Int { Int(occt_face_count(raw)) }
     var edgeCount: Int { Int(occt_edge_count(raw)) }
-    /// Whether OCCT's own checker (`BRepCheck_Analyzer`) accepts the shape. A check that fails counts as invalid.
-    var isValid: Bool { occt_is_valid(raw) == 1 }
+    /// What OCCT's own checker (`BRepCheck_Analyzer`) says about the shape.
+    var validity: OCCTValidity { OCCTValidity(status: occt_is_valid(raw)) }
+    /// Whether the checker accepts the shape. A check that fails counts as not valid.
+    var isValid: Bool { validity == .valid }
 
     /// Length of the edge at 1-based `index`, or -1 when out of range.
     func edgeLength(at index: Int) -> Double {
```

Replace `Sources/CreatorOCCT/OCCTKernel+Blend.swift` entirely (the searches are as before; a rejected blend still searches, a checker that threw or a not-built blend gets the generic message; Task 3 changes the last):

```swift
import CreatorKernel

extension OCCTKernel {
    /// What one try at a blend came to.
    private enum Attempt {
        case built(OCCTShape, [OCCTHistoryRecord])
        /// OCCT built a solid its checker rejects.
        case rejected
        /// OCCT built a solid and the checker itself failed.
        case unchecked
        /// OCCT reported the blend not done.
        case notBuilt
    }

    /// Fillets or chamfers `edges` (spec §5.2). OCCT can report a blend done yet return a solid its own checker rejects
    /// (spec §8's hexagon flange at R3, Errata (Kernel: invalid blends)); every later blend on such a solid fails. So a
    /// result `check` rejects is never returned: the blend fails, naming the largest size that works. `check` is
    /// `OCCTShape.validity`; a test passes another to stand in for a checker that throws or rejects every size, or to
    /// count the tries.
    func blend(_ solid: Solid, edges: [EdgeID], size: Double, chamfer: Bool, tag: NodeTag,
               check: (OCCTShape) -> OCCTValidity = { $0.validity }) throws -> Solid {
        guard size.isFinite, size > 0 else { throw KernelError.invalidInput("The size must be greater than 0 mm.") }
        guard !edges.isEmpty else { throw KernelError.invalidInput("No edges are selected.") }
        if let missing = edges.first(where: { solid.topology.edge($0) == nil }) {
            throw KernelError.invalidInput("Edge \(missing.rawValue) doesn't exist on the input solid.")
        }
        let source = try shape(of: solid)
        let attempt: Attempt
        do {
            // Untyped throws on purpose, as in `build`: Swift 6.4 crashes with typed throws returning a tuple.
            attempt = try Self.serialized { () throws -> Attempt in
                let result = try source.blended(edges: edges, size: size, chamfer: chamfer)
                switch check(result.0) {
                case .valid: return .built(result.0, result.1)
                case .invalid: return .rejected
                case .unchecked: return .unchecked
                }
            }
        } catch is OCCTError {
            attempt = .notBuilt
        }
        switch attempt {
        case .built(let shape, let history):
            return try self.solid(from: shape, history: history, inputs: [solid.topology], tag: tag,
                                  operation: chamfer ? "chamfer" : "fillet")
        case .unchecked, .notBuilt:
            // A checker that threw says nothing about any size, so there is nothing to search for.
            throw KernelError.blendFailed(size: size, chamfer: chamfer)
        case .rejected:
            let largest = try largestValidBlend(of: source, edges: edges, below: size, chamfer: chamfer, check: check)
            throw KernelError.invalidBlend(size: size, largest: largest, edgeCount: edges.count, chamfer: chamfer)
        }
    }

    /// The largest size below `size`, on a 0.1 mm grid, whose blend OCCT builds and `check` accepts; nil when not
    /// even 0.1 mm does. It bisects, assuming every size above one that fails fails too; the size it returns was built
    /// and checked. Each try takes the OCCT lock on its own, and a cancelled evaluation stops between tries.
    func largestValidBlend(of source: OCCTShape, edges: [EdgeID], below size: Double, chamfer: Bool,
                           check: (OCCTShape) -> OCCTValidity = { $0.validity }) throws -> Double? {
        var works = 0
        // In tenths of a millimetre; capped so a huge size can't overflow `Int` (sizes above it are never tried).
        var fails = Int(min((size * 10).rounded(.up), 1_000_000))
        while fails - works > 1 {
            try Task.checkCancellation()
            let tenths = (works + fails) / 2
            let valid = Self.serialized { () -> Bool in
                guard let built = try? source.blended(edges: edges, size: Double(tenths) / 10, chamfer: chamfer) else { return false }
                return check(built.0) == .valid
            }
            if valid { works = tenths } else { fails = tenths }
        }
        return works > 0 ? Double(works) / 10 : nil
    }
}
```

- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter 'OCCTValidityTests|InvalidBlendTests'`
Expected: PASS (`InvalidBlendTests` 9 tests, `OCCTValidityTests` 2).

- [ ] **Step 5: Full verification** (recipe above). Expected: master + 4 = **1647** tests, 0 new warnings, 0 lint violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorOCCT Tests/CreatorOCCTTests
git commit -m "kernel: OCCTValidity; a checker that throws gives the generic blend message"
```

---

### Task 2: The grid: no `ceil` overshoot, no false "even by 0.1 mm"

**Files:**
- Create: `Sources/CreatorOCCT/BlendGrid.swift`
- Modify: `Sources/CreatorOCCT/OCCTKernel+Blend.swift` (`largestValidBlend`'s `fails`)
- Modify: `Sources/CreatorOCCT/KernelError+Blend.swift` (`invalidBlend`)
- Create: `Tests/CreatorOCCTTests/BlendGridTests.swift`
- Modify: `Tests/CreatorOCCTTests/InvalidBlendTests.swift`

**Interfaces:**
- Consumes: Task 1's `blend`; `KernelError.invalidBlend(size:largest:edgeCount:chamfer:)`.
- Produces: `BlendGrid.step: Double` (0.1), `BlendGrid.mostTenths: Int` (1_000_000), `BlendGrid.firstFailingTenths(for size: Double) -> Int`, `BlendGrid.triesSmallest(below size: Double) -> Bool`.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorOCCTTests/BlendGridTests.swift`:

```swift
import Testing
@testable import CreatorOCCT

/// The search's grid: which sizes it tries, and when "even by 0.1 mm" is true.
struct BlendGridTests {
    @Test(arguments: [(3.0, 30), (2.5, 25), (0.7, 7), (0.1, 1), (0.15, 2), (0.05, 1), (1.25, 13)])
    func theFirstFailingCountIsTheSizeInTenthsRoundedUp(size: Double, tenths: Int) {
        #expect(BlendGrid.firstFailingTenths(for: size) == tenths)
    }

    /// `0.1 + 0.2` is 0.30000000000000004: `ceil(size * 10)` would give 4 and the search would try 0.3 mm, the size asked.
    @Test func aSizeAHairOverTheGridIsStillOnIt() {
        #expect(0.1 + 0.2 != 0.3)
        #expect(BlendGrid.firstFailingTenths(for: 0.1 + 0.2) == 3)
        #expect(BlendGrid.firstFailingTenths(for: 2.3 + 0.1) == 24)
    }

    @Test func aTinyOrHugeSizeStaysInRange() {
        #expect(BlendGrid.firstFailingTenths(for: 1e-12) == 0)
        #expect(BlendGrid.firstFailingTenths(for: .greatestFiniteMagnitude) == BlendGrid.mostTenths)
    }

    @Test func theSmallestSizeIsTriedOnlyBelowASizeAboveIt() {
        #expect(!BlendGrid.triesSmallest(below: 0.1))
        #expect(!BlendGrid.triesSmallest(below: 0.05))
        #expect(BlendGrid.triesSmallest(below: 0.15))
        #expect(BlendGrid.triesSmallest(below: 3))
    }
}
```

In `InvalidBlendTests.swift`, add inside the struct before `theMessagesNameOneEdgeAndSayWhenNoSizeWorks`:

```swift
    /// A size of 0.1 mm or less never tried 0.1 mm, so the messages can't say "even by 0.1 mm".
    @Test func aSizeNoLargerThanTheSmallestOneDoesNotClaimToHaveTriedIt() {
        #expect(KernelError.invalidBlend(size: 0.1, largest: nil, edgeCount: 1, chamfer: false).userMessage
            == "Radius 0.1 mm could not be applied: rounding the selected edge gives a broken solid.")
        #expect(KernelError.invalidBlend(size: 0.05, largest: nil, edgeCount: 4, chamfer: true).userMessage
            == "Chamfer failed: chamfering the 4 selected edges by 0.05 mm gives a broken solid.")
        #expect(KernelError.invalidBlend(size: 0.15, largest: nil, edgeCount: 4, chamfer: true).userMessage
            == "Chamfer failed: chamfering the 4 selected edges by 0.15 mm gives a broken solid, even by 0.1 mm.")
    }

    /// Computed sizes land a hair off the grid: asked for `0.1 + 0.2`, the search names a size below it (0.2), not 0.3.
    /// 0.3 would build; the maximum is conservative for an off-grid size (`BlendGrid`).
    @Test func aSizeAHairOverTheGridNamesTheOneBelowIt() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try #require(solid.topology.edges.first { $0.kind == .line && isClose($0.length, 30) })
        let source = try #require((solid.storage as? OCCTSolidStorage)?.shape)
        let largest = try await kernel.largestValidBlend(of: source, edges: [edge.id], below: 0.1 + 0.2, chamfer: false)
        #expect(largest == 0.2)
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift build --build-tests 2>&1 | grep error:`
Expected: `cannot find 'BlendGrid' in scope`.

- [ ] **Step 3: Implement**

`Sources/CreatorOCCT/BlendGrid.swift`:

```swift
/// The 0.1 mm grid `OCCTKernel.largestValidBlend` searches and the messages that report it.
enum BlendGrid {
    /// One step of the grid, in millimetres.
    static let step = 0.1

    /// The most tenths of a millimetre a search starts from, so a huge size can't overflow `Int`.
    static let mostTenths = 1_000_000

    /// Slack for products like `0.3 * 10` that land a hair above a whole number.
    private static let slack = 1e-9

    /// The first count of tenths of a millimetre at or above `size`: the search tries only counts below it, so it
    /// names a size below the one asked for. A size on the grid is exact even when float arithmetic put it a hair
    /// over (`0.1 + 0.2`, which `ceil` alone would round up to 4 tenths). The slack also means a size within 1e-9
    /// above a grid value counts as that value, so for an off-grid size the maximum named is conservative: it can be
    /// a step below a size that would still build.
    static func firstFailingTenths(for size: Double) -> Int {
        Int(min((size * 10 - slack).rounded(.up), Double(mostTenths)))
    }

    /// Whether a search for `size` tries the smallest grid size, 0.1 mm. When it didn't, finding none says nothing
    /// about 0.1 mm.
    static func triesSmallest(below size: Double) -> Bool {
        firstFailingTenths(for: size) > 1
    }
}
```

In `largestValidBlend` (Task 1's version), replace the two `fails` lines:

```swift
        // In tenths of a millimetre; capped so a huge size can't overflow `Int` (sizes above it are never tried).
        var fails = Int(min((size * 10).rounded(.up), 1_000_000))
```

with:

```swift
        // In tenths of a millimetre (sizes above `BlendGrid.mostTenths` are never tried).
        var fails = BlendGrid.firstFailingTenths(for: size)
```

`KernelError+Blend.swift` (diff against Task 1):

```diff
diff --git a/Sources/CreatorOCCT/KernelError+Blend.swift b/Sources/CreatorOCCT/KernelError+Blend.swift
index 72b4fef..253aa02 100644
--- a/Sources/CreatorOCCT/KernelError+Blend.swift
+++ b/Sources/CreatorOCCT/KernelError+Blend.swift
@@ -12,16 +12,17 @@ extension KernelError {
     }
 
     /// OCCT built the blend but its checker rejects the solid. `largest` is the largest size that gives a valid one,
-    /// nil when not even 0.1 mm does.
+    /// nil when none was found: then the message adds "even by 0.1 mm" only if 0.1 mm was tried (`size` above it).
     static func invalidBlend(size: Double, largest: Double?, edgeCount: Int, chamfer: Bool) -> KernelError {
         let edges = edgeCount == 1 ? "the selected edge" : "the \(edgeCount) selected edges"
+        let noneFound = BlendGrid.triesSmallest(below: size) ? ", even by \(millimetres(BlendGrid.step)) mm" : ""
         if chamfer {
-            let limit = largest.map { " (max ≈ \(millimetres($0)) mm)" } ?? ", even by 0.1 mm"
+            let limit = largest.map { " (max ≈ \(millimetres($0)) mm)" } ?? noneFound
             return .operationFailed(operation: "chamfer",
                                     reason: "chamfering \(edges) by \(millimetres(size)) mm gives a broken solid\(limit).")
         }
         let reason = largest == nil
-            ? "rounding \(edges) gives a broken solid, even by 0.1 mm."
+            ? "rounding \(edges) gives a broken solid\(noneFound)."
             : "rounding \(edges) by \(millimetres(size)) mm gives a broken solid."
         return .filletFailed(radius: size, maxRadius: largest, reason: reason)
     }
```

- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter 'BlendGridTests|InvalidBlendTests'`
Expected: PASS.

- [ ] **Step 5: Full verification.** Expected: master + 10 = **1653** tests (`BlendGridTests` 4, `InvalidBlendTests` +2 on Task 1's 9), 0 new warnings, 0 lint violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorOCCT Tests/CreatorOCCTTests
git commit -m "kernel: blend search grid without the ceil overshoot; no 'even by 0.1 mm' for sizes up to 0.1 mm"
```

---

### Task 3: A blend OCCT can't build names a maximum too

**Files:**
- Modify: `Sources/CreatorOCCT/OCCTKernel+Blend.swift` (whole file replaced below)
- Modify: `Sources/CreatorOCCT/KernelError+Blend.swift` (whole file replaced below)
- Modify: `Tests/CreatorOCCTTests/FeatureConformanceTests.swift` (`impossibleFilletFailsCleanlyAndKernelRecovers`)
- Create: `Tests/CreatorOCCTTests/UnbuildableBlendTests.swift`

**Interfaces:**
- Consumes: `BlendGrid` (Task 2), `OCCTValidity` (Task 1).
- Produces: `KernelError.blendFailed(size: Double, chamfer: Bool, largest: Double?) -> KernelError` (replaces the two-argument form; its only caller is `OCCTKernel.blend`); `OCCTKernel.blend` splits into `blendSource` (validation), `attempt(blending:…)` and the outcome switch, to stay under the lint's complexity limit of 10.

- [ ] **Step 1: Write the failing tests**

`Tests/CreatorOCCTTests/UnbuildableBlendTests.swift`:

```swift
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// A fillet or chamfer OCCT reports not done names the largest size that works, as one OCCT builds but its checker
/// rejects does (Errata (Kernel: largest size for blends OCCT can't build)).
struct UnbuildableBlendTests {
    func verticalEdge(of solid: Solid) throws -> EdgeInfo {
        try #require(solid.topology.edges.first { $0.kind == .line && isClose($0.length, 30) })
    }

    @Test func aChamferOCCTCantBuildNamesTheLargestDistanceThatWorks() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try verticalEdge(of: solid)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.chamfer(solid, edges: [edge.id], distance: 40, tag: newTag())
        }
        guard case .operationFailed(let operation, _)? = error else { Issue.record("expected operationFailed"); return }
        #expect(operation == "chamfer")
        #expect(error?.userMessage == "Chamfer failed: the selected edges can't be chamfered by 40 mm (max ≈ 9.9 mm).")
    }

    @Test func theSizeItNamesBuildsAndIsValid() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try verticalEdge(of: solid)
        let filleted = try await kernel.fillet(solid, edges: [edge.id], radius: 9.9, tag: newTag())
        let chamfered = try await kernel.chamfer(solid, edges: [edge.id], distance: 9.9, tag: newTag())
        for result in [filleted, chamfered] {
            let shape = try #require((result.storage as? OCCTSolidStorage)?.shape)
            #expect(OCCTKernel.serialized { shape.isValid })
        }
    }

    /// The search runs after OCCT's first build fails, so a cancelled evaluation must stop it rather than name a size.
    @Test func aCancelledBlendOCCTCantBuildStopsRatherThanNamingASize() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try verticalEdge(of: solid)
        let blend = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.blend(solid, edges: [edge.id], size: 40, chamfer: false, tag: newTag())
        }
        await #expect(throws: CancellationError.self) { try await blend.value }
    }

    /// The search starts from the size asked for, capped, so a size far beyond the part (here a metre-scale 1e9 mm) ends in
    /// the same maximum after the same few tries.
    @Test func aRadiusFarBeyondThePartNamesTheSameMaximum() async throws {
        let kernel = OCCTKernel()
        let solid = try await box(kernel, 10, 20, 30)
        let edge = try verticalEdge(of: solid)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.fillet(solid, edges: [edge.id], radius: 1e9, tag: newTag())
        }
        #expect(error?.userMessage.hasSuffix("(max ≈ 9.9 mm).") == true)
    }

    /// A real blend that no size can build: the vertical edge of a 0.1 mm square post, where even 0.1 mm rounds the
    /// whole face away. The search finds nothing, so the message keeps no maximum. OCCT's first build failed, not the
    /// checker, so this pins the not-built path's own wiring of `largest`.
    @Test func aBlendNoSizeCanBuildKeepsTheGenericMessage() async throws {
        let kernel = OCCTKernel()
        let post = try await box(kernel, 0.1, 0.1, 30)
        let edge = try verticalEdge(of: post)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.fillet(post, edges: [edge.id], radius: 5, tag: newTag())
        }
        #expect(error == .filletFailed(radius: 5, maxRadius: nil, reason: "the selected edges can't be rounded this much."))
        let chamfer = await #expect(throws: KernelError.self) {
            try await kernel.chamfer(post, edges: [edge.id], distance: 5, tag: newTag())
        }
        #expect(chamfer?.userMessage == "Chamfer failed: the selected edges can't be chamfered by 5 mm.")
    }

    @Test func theMessagesAddTheMaximumOnlyWhenOneWasFound() {
        #expect(KernelError.blendFailed(size: 40, chamfer: false, largest: 9.9).userMessage
            == "Radius 40 mm is too large for the selected edges (max ≈ 9.9 mm).")
        #expect(KernelError.blendFailed(size: 40, chamfer: false, largest: nil).userMessage
            == "Radius 40 mm could not be applied: the selected edges can't be rounded this much.")
        #expect(KernelError.blendFailed(size: 40, chamfer: true, largest: 9.9).userMessage
            == "Chamfer failed: the selected edges can't be chamfered by 40 mm (max ≈ 9.9 mm).")
        #expect(KernelError.blendFailed(size: 2.5, chamfer: true, largest: nil).userMessage
            == "Chamfer failed: the selected edges can't be chamfered by 2.5 mm.")
    }
}
```

`FeatureConformanceTests.impossibleFilletFailsCleanlyAndKernelRecovers` now expects the maximum (the box's narrower face is 10 mm wide, so 9.9):

```diff
diff --git a/Tests/CreatorOCCTTests/FeatureConformanceTests.swift b/Tests/CreatorOCCTTests/FeatureConformanceTests.swift
index c1db912..0571e72 100644
--- a/Tests/CreatorOCCTTests/FeatureConformanceTests.swift
+++ b/Tests/CreatorOCCTTests/FeatureConformanceTests.swift
@@ -54,10 +54,11 @@ struct FeatureConformanceTests {
         let error = await #expect(throws: KernelError.self) {
             try await kernel.fillet(solid, edges: [edge.id], radius: 40, tag: newTag())
         }
-        guard case .filletFailed(let radius, _, let reason)? = error else { Issue.record("expected filletFailed"); return }
+        guard case .filletFailed(let radius, let maxRadius, let reason)? = error else { Issue.record("expected filletFailed"); return }
         #expect(radius == 40)
+        #expect(maxRadius == 9.9, "the box's narrower face is 10 mm wide")
         #expect(reason == "the selected edges can't be rounded this much.")
-        #expect(error?.userMessage.contains("40") == true)
+        #expect(error?.userMessage == "Radius 40 mm is too large for the selected edges (max ≈ 9.9 mm).")
         // The kernel is still usable.
         let ok = try await kernel.fillet(solid, edges: [edge.id], radius: 1, tag: newTag())
         #expect(ok.topology.faces.count == 7)
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift build --build-tests 2>&1 | grep error:`
Expected: `blendFailed(size:chamfer:largest:)` does not exist.

- [ ] **Step 3: Implement**

Replace `Sources/CreatorOCCT/KernelError+Blend.swift` entirely:

```swift
import CreatorKernel
import Foundation

extension KernelError {
    /// OCCT couldn't build the blend (or its checker failed). `largest` is the largest size that works, nil when none
    /// was found or looked for.
    static func blendFailed(size: Double, chamfer: Bool, largest: Double?) -> KernelError {
        if chamfer {
            let limit = largest.map { " (max ≈ \(millimetres($0)) mm)" } ?? ""
            return .operationFailed(operation: "chamfer",
                                    reason: "the selected edges can't be chamfered by \(millimetres(size)) mm\(limit).")
        }
        return .filletFailed(radius: size, maxRadius: largest, reason: "the selected edges can't be rounded this much.")
    }

    /// OCCT built the blend but its checker rejects the solid. `largest` is the largest size that gives a valid one,
    /// nil when none was found: then the message adds "even by 0.1 mm" only if 0.1 mm was tried (`size` above it).
    static func invalidBlend(size: Double, largest: Double?, edgeCount: Int, chamfer: Bool) -> KernelError {
        let edges = edgeCount == 1 ? "the selected edge" : "the \(edgeCount) selected edges"
        let noneFound = BlendGrid.triesSmallest(below: size) ? ", even by \(millimetres(BlendGrid.step)) mm" : ""
        if chamfer {
            let limit = largest.map { " (max ≈ \(millimetres($0)) mm)" } ?? noneFound
            return .operationFailed(operation: "chamfer",
                                    reason: "chamfering \(edges) by \(millimetres(size)) mm gives a broken solid\(limit).")
        }
        let reason = largest == nil
            ? "rounding \(edges) gives a broken solid\(noneFound)."
            : "rounding \(edges) by \(millimetres(size)) mm gives a broken solid."
        return .filletFailed(radius: size, maxRadius: largest, reason: reason)
    }

    private static func millimetres(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
```

Replace `Sources/CreatorOCCT/OCCTKernel+Blend.swift` entirely:

```swift
import CreatorKernel

extension OCCTKernel {
    /// What one try at a blend came to.
    private enum Attempt {
        case built(OCCTShape, [OCCTHistoryRecord])
        /// OCCT built a solid its checker rejects.
        case rejected
        /// OCCT built a solid and the checker itself failed.
        case unchecked
        /// OCCT reported the blend not done.
        case notBuilt
    }

    /// Fillets or chamfers `edges` (spec §5.2). OCCT can report a blend done yet return a solid its own checker rejects
    /// (spec §8's hexagon flange at R3, Errata (Kernel: invalid blends)); every later blend on such a solid fails. So a
    /// result `check` rejects is never returned: the blend fails, naming the largest size that works. A blend OCCT
    /// can't build at all fails the same way (Errata (Kernel: largest size for blends OCCT can't build)); either search
    /// costs up to about 20 failing tries. `check` is `OCCTShape.validity`; a test passes another to stand in for a
    /// checker that throws or rejects every size, or to count the tries.
    func blend(_ solid: Solid, edges: [EdgeID], size: Double, chamfer: Bool, tag: NodeTag,
               check: (OCCTShape) -> OCCTValidity = { $0.validity }) throws -> Solid {
        let source = try blendSource(solid, edges: edges, size: size)
        switch try attempt(blending: source, edges: edges, size: size, chamfer: chamfer, check: check) {
        case .built(let shape, let history):
            return try self.solid(from: shape, history: history, inputs: [solid.topology], tag: tag,
                                  operation: chamfer ? "chamfer" : "fillet")
        case .unchecked:
            // A checker that threw says nothing about any size, so there is nothing to search for.
            throw KernelError.blendFailed(size: size, chamfer: chamfer, largest: nil)
        case .notBuilt:
            let largest = try largestValidBlend(of: source, edges: edges, below: size, chamfer: chamfer, check: check)
            throw KernelError.blendFailed(size: size, chamfer: chamfer, largest: largest)
        case .rejected:
            let largest = try largestValidBlend(of: source, edges: edges, below: size, chamfer: chamfer, check: check)
            throw KernelError.invalidBlend(size: size, largest: largest, edgeCount: edges.count, chamfer: chamfer)
        }
    }

    /// Builds the blend once under the OCCT lock and sorts what came of it.
    private func attempt(blending source: OCCTShape, edges: [EdgeID], size: Double, chamfer: Bool,
                         check: (OCCTShape) -> OCCTValidity) throws -> Attempt {
        do {
            // Untyped throws on purpose, as in `build`: Swift 6.4 crashes with typed throws returning a tuple.
            return try Self.serialized { () throws -> Attempt in
                let result = try source.blended(edges: edges, size: size, chamfer: chamfer)
                switch check(result.0) {
                case .valid: return .built(result.0, result.1)
                case .invalid: return .rejected
                case .unchecked: return .unchecked
                }
            }
        } catch is OCCTError {
            return .notBuilt
        }
    }

    /// The OCCT shape of `solid`, once the blend's size and edges are known to make sense for it.
    private func blendSource(_ solid: Solid, edges: [EdgeID], size: Double) throws -> OCCTShape {
        guard size.isFinite, size > 0 else { throw KernelError.invalidInput("The size must be greater than 0 mm.") }
        guard !edges.isEmpty else { throw KernelError.invalidInput("No edges are selected.") }
        if let missing = edges.first(where: { solid.topology.edge($0) == nil }) {
            throw KernelError.invalidInput("Edge \(missing.rawValue) doesn't exist on the input solid.")
        }
        return try shape(of: solid)
    }

    /// The largest size below `size`, on a 0.1 mm grid, whose blend OCCT builds and `check` accepts; nil when not
    /// even 0.1 mm does. It bisects, assuming every size above one that fails fails too; the size it returns was built
    /// and checked. Each try takes the OCCT lock on its own, and a cancelled evaluation stops between tries.
    func largestValidBlend(of source: OCCTShape, edges: [EdgeID], below size: Double, chamfer: Bool,
                           check: (OCCTShape) -> OCCTValidity = { $0.validity }) throws -> Double? {
        var works = 0
        // In tenths of a millimetre (sizes above `BlendGrid.mostTenths` are never tried).
        var fails = BlendGrid.firstFailingTenths(for: size)
        while fails - works > 1 {
            try Task.checkCancellation()
            let tenths = (works + fails) / 2
            let valid = Self.serialized { () -> Bool in
                guard let built = try? source.blended(edges: edges, size: Double(tenths) / 10, chamfer: chamfer) else { return false }
                return check(built.0) == .valid
            }
            if valid { works = tenths } else { fails = tenths }
        }
        return works > 0 ? Double(works) / 10 : nil
    }
}
```

- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter 'UnbuildableBlendTests|FeatureConformanceTests|InvalidBlendTests'`
Expected: PASS. If `aBlendNoSizeCanBuildKeepsTheGenericMessage` finds a maximum or a "broken solid" message instead, the post is not unbuildable on your OCCT: print what comes out and pick a thinner post or a larger size before changing the message code (it passed with `box(kernel, 0.1, 0.1, 30)` at 5 mm). If a size other than 9.9 comes out for the chamfer, that is a real result: print it, check the box is 10 wide and that 9.9 builds, then correct the two expectations (they were 9.9 for both when verified).

- [ ] **Step 5: Full verification.** Expected: master + 16 = **1659** tests (`UnbuildableBlendTests` 6), 0 new warnings, 0 lint violations.

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorOCCT Tests/CreatorOCCTTests
git commit -m "kernel: a fillet or chamfer OCCT can't build names the largest size that works"
```

---

### Task 4: Measure the refused blend's search

**Files:**
- Create: `Tests/CreatorAppTests/Bench/BlendRefusalBench.swift`
- Create: `Tests/CreatorAppTests/Bench/BlendRefusalFixtureTests.swift`

**Interfaces:**
- Consumes: `Bench` (`isRequested`, `requireRelease()`), `BenchSamples`, `makeBracketBenchApp()`, `AppBracket.fillet`, `OCCTKernel.largestValidBlend`, `OCCTSolidStorage.shape`.
- Produces: BENCH lines `blend-flange …` and `blend-bracket …`. The bench suite is skipped by a plain `swift test` (2 skipped tests count); `BlendRefusalFixtureTests` (1 test) runs in every `swift test`.

- [ ] **Step 1: Write the benchmark**

The flange recipe is copied from `Tests/CreatorOCCTTests/Support/HexagonFlange.swift`, which `CreatorAppTests` can't import; `BlendRefusalFixtureTests` below guards the copy. The bracket's Fillet is set through `DocumentModel.perform(.setInput(...))`, and radii change every step so the evaluator never serves a cached result.

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// What a refused fillet costs: the search for the largest size that works (up to about 20 failing tries, Errata
/// (Kernel: largest size for blends OCCT can't build)), against a blend that works, and the checker on its own
/// (`BRepCheck_Analyzer` on every blend result, the M0–M1 carry-over note's "watch" item). Two parts: §8's hexagon
/// flange at R3, whose result OCCT builds but its checker rejects, and the §7.2 bracket with its Fillet at a radius its
/// edges can't take (which of the two refusals it meets is not recorded; both run the search). Prints `BENCH blend-…`
/// lines.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct BlendRefusalBench {
    static func tag() -> NodeTag { NodeTag(node: NodeID(), item: 0) }

    /// The plate and hexagon flange of `Tests/CreatorOCCTTests/Support/HexagonFlange.swift` (CreatorOCCTTests, which this
    /// target can't import) and its four upright edges. A copy: `BlendRefusalFixtureTests` (run by a plain `swift test`)
    /// asserts what the original is known for, so the copies can't drift apart unnoticed.
    static func flange(_ kernel: OCCTKernel) async throws -> (union: Solid, edges: [EdgeID]) {
        let plate = try await kernel.extrude(.roundedRectangle(width: 60, height: 40, radius: 4, plane: .xy), distance: 6,
                                             mode: .oneSided, tag: tag())
        let hexagon = try await kernel.extrude(.regularPolygon(sides: 6, radius: 15, rotation: .degrees(30),
                                                               plane: Plane.xz.offset(by: -20)),
                                               distance: 8, mode: .oneSided, tag: tag())
        let lifted = try await kernel.transform(hexagon, by: Transform(translation: Vector3(0, 0, 15)), tag: tag())
        let union = try await kernel.boolean(.union, plate, [lifted], tag: tag())
        let upright = union.topology.edges.filter { edge in
            edge.kind == .line && edge.convexity == .convex && !edge.isSeam && abs((edge.direction ?? .zero).dot(.unitZ)) > 0.999
        }
        return (union, upright.map(\.id))
    }

    @Test func aRefusedFilletOnTheFlangeAgainstOneThatWorks() async throws {
        guard Bench.requireRelease() else { return }
        let kernel = OCCTKernel()
        let (union, edges) = try await Self.flange(kernel)
        let shape = try #require((union.storage as? OCCTSolidStorage)?.shape)
        var works = BenchSamples("blend-flange fillet R2.5 (works: build + check)")
        var refused = BenchSamples("blend-flange fillet R3 (refused: build + check + search)")
        var search = BenchSamples("blend-flange search alone (largestValidBlend below R3)")
        var check = BenchSamples("blend-flange checker alone (BRepCheck_Analyzer on the union)")
        let clock = ContinuousClock()
        for step in 0..<30 {
            let a = clock.now
            _ = try await kernel.fillet(union, edges: edges, radius: 2.5, tag: Self.tag())
            let b = clock.now
            let error = await #expect(throws: KernelError.self) {
                try await kernel.fillet(union, edges: edges, radius: 3, tag: Self.tag())
            }
            let c = clock.now
            #expect(error?.userMessage == "Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm).")
            _ = try await kernel.largestValidBlend(of: shape, edges: edges, below: 3, chamfer: false)
            let d = clock.now
            _ = OCCTKernel.serialized { shape.isValid }
            let e = clock.now
            guard step >= 5 else { continue }
            works.append(from: a, to: b)
            refused.append(from: b, to: c)
            search.append(from: c, to: d)
            check.append(from: d, to: e)
        }
        for samples in [works, refused, search, check] { print(samples.line()) }
    }

    @Test func aRefusedFilletOnTheBracketAgainstOneThatWorks() async throws {
        guard Bench.requireRelease() else { return }
        let (app, bracket) = try await makeBracketBenchApp()
        var works = BenchSamples("blend-bracket Fillet node R3.x (works; evaluation of the Fillet and what follows)")
        var refused = BenchSamples("blend-bracket Fillet node R8.x (refused; evaluation of the Fillet and what follows)")
        let clock = ContinuousClock()
        for step in 0..<25 {
            let a = clock.now
            try app.document.perform(.setInput(bracket.fillet.id, "radius", .number(3 + Double(step) * 0.01)))
            await app.settle()
            let b = clock.now
            try app.document.perform(.setInput(bracket.fillet.id, "radius", .number(8 + Double(step) * 0.05)))
            await app.settle()
            let c = clock.now
            guard step >= 5 else { continue }
            works.append(from: a, to: b)
            refused.append(from: b, to: c)
        }
        guard case .error(let message)? = app.document.results[bracket.fillet.id]?.state else {
            Issue.record("the Fillet at R8 should be in error")
            return
        }
        print("BENCH blend-bracket message: \(message)")
        print(works.line())
        print(refused.line())
    }
}
```

Then the guard that runs in every `swift test`, `Tests/CreatorAppTests/Bench/BlendRefusalFixtureTests.swift`:

```swift
import CreatorKernel
import Testing
@testable import CreatorOCCT

/// `BlendRefusalBench`'s hexagon flange is a copy of `HexagonFlange` (CreatorOCCTTests, which this target can't
/// import). The bench only runs on request, so this checks the copy in every run: the original's four upright edges,
/// and R3 refused naming 2.5 mm (`InvalidBlendTests`).
@MainActor
struct BlendRefusalFixtureTests {
    @Test func theBenchFlangeIsTheOneThatBreaksAtR3() async throws {
        let kernel = OCCTKernel()
        let (union, edges) = try await BlendRefusalBench.flange(kernel)
        #expect(edges.count == 4)
        let error = await #expect(throws: KernelError.self) {
            try await kernel.fillet(union, edges: edges, radius: 3, tag: BlendRefusalBench.tag())
        }
        #expect(error?.userMessage == "Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm).")
    }
}
```

- [ ] **Step 2: Check it compiles; the bench is skipped in a plain run and the guard passes**

Run: `swift build --build-tests 2>&1 | grep 'error:\|BlendRefusal'` then `swift test --filter BlendRefusal`
Expected: no errors; the two bench tests report skipped ("set METALCREATOR_BENCH=1"), `theBenchFlangeIsTheOneThatBreaksAtR3` passes.

- [ ] **Step 3: Run it in a release build, on as idle a machine as you can get**

Run: `scripts/bench.sh BlendRefusalBench`
Expected: seven `BENCH blend-…` lines. Record the machine and the load averages with them (`uptime` before and after). The numbers below and in Task 5's `performance.md` came from a run at load 79 / 163 / 143 (not idle, so upper bounds); replace them with yours and keep the load beside them, and re-measure on an idle machine before merging if you can. The bracket refusal's kind (OCCT not done, or the checker rejecting) is not recorded: both run the same search, so the cost is the same either way. The figures go only in `docs/verification/performance.md` (Task 5).

| Measured (median, p95; ms) | Flange (kernel) | Bracket (Fillet node and what follows) |
|---|---|---|
| a blend that works | 16.06 (37.11) | 32.96 (48.03) |
| a refused blend (build, check, search) | 95.48 (123.60) | 90.40 (126.25) |
| the search alone | 73.07 (135.48) | n/a |
| `BRepCheck_Analyzer` alone | 2.34 (4.97) | n/a |

- [ ] **Step 4: Full verification.** Expected: master + 19 = **1662** tests (+1 fixture test, +2 skipped bench tests), 0 new warnings, 0 lint violations.

- [ ] **Step 5: Commit**

```bash
git add Tests/CreatorAppTests/Bench
git commit -m "bench: the cost of a refused blend"
```

---

### Task 5: Records: roadmap, spec errata, carry-over note, performance, CLAUDE.md

**Files:**
- Modify: `docs/superpowers/roadmap.md`, `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`, `docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`, `docs/verification/performance.md`, `docs/verification/human-checks.md`, `CLAUDE.md`

**Interfaces:** none (documents). The Task 4 figures appear in one file only, `docs/verification/performance.md` (its table, its raw `BENCH` lines, and the closing paragraph). CLAUDE.md, the roadmap row, the spec Errata and the carry-over note say "tens of milliseconds" and point there, so a re-measure on an idle machine changes that one file. If your figures differ, replace them in those three places of `performance.md`.

- [ ] **Step 1: Apply these edits**

`CLAUDE.md`:

```diff
diff --git a/CLAUDE.md b/CLAUDE.md
index d534853..7f11a7c 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -155,7 +155,10 @@ records is the loop. Loft refuses profiles with holes. Create nodes only with `N
 Shim errors: `cocct::user_error` / `set_error` messages are user-facing and unprefixed; any other OCCT exception is prefixed "occt: " by `guarded` and mapped to a generic sentence by `KernelError.plainReason`.
 Every fillet and chamfer result is checked with OCCT's `BRepCheck_Analyzer` (`OCCTShape.isValid`) and never returned when
 the check rejects it: the blend fails naming the largest size that works (`OCCTKernel.largestValidBlend`, spec Errata
-(Kernel: invalid blends)).
+(Kernel: invalid blends)). A blend OCCT can't build names one too, and a checker that itself throws
+(`OCCTValidity.unchecked`) gives the generic message with no search (Errata (Kernel: largest size for blends OCCT can't
+build)); a refused blend costs tens of milliseconds more than one that works (`BlendRefusalBench`,
+`docs/verification/performance.md`).
 MetalUI exports its own `Angle`: a file importing both MetalUI and CreatorGeometry writes `CreatorGeometry.Angle`.
 The GPU structs in `Sources/CreatorViewport/Render` mirror the MSL in `ViewportShaders.swift`, and `GPUDataTests` pins their strides, so change both together.
 The viewport's pointer input is MetalUI C7's (spec §9): its bindings live in `ViewportInputMap`, its behaviour in
```

`docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`:

```diff
diff --git a/docs/superpowers/notes/2026-10-07-m0-m1-carryover.md b/docs/superpowers/notes/2026-10-07-m0-m1-carryover.md
index ed20706..f388ec1 100644
--- a/docs/superpowers/notes/2026-10-07-m0-m1-carryover.md
+++ b/docs/superpowers/notes/2026-10-07-m0-m1-carryover.md
@@ -202,3 +202,11 @@ Read this before writing the M2 and M3 plans.
   require tangent continuity at a joint (`Topology+EdgeRuns.swift`, `cocct_inspect.cpp`).
 - Sketch projections with several references add edges and runs across solids while narrowing per solid; compare
   drift per solid if multi-reference projections become common (`SketchProjections.swift`).
+
+## From kernel: largest size for blends OCCT can't build
+- Watch: `OCCTKernel.blend` runs `BRepCheck_Analyzer` (`OCCTShape.validity`) on the result of every fillet and chamfer,
+  under the OCCT lock. On §8's hexagon flange union it is a small part of a blend (a few milliseconds of a blend of
+  tens; `BlendRefusalBench`, figures in `docs/verification/performance.md`). The analyzer walks every face, edge and vertex, so it grows
+  with the part: on a large part with hundreds of faces, check how much of each blend it takes (`blend-flange checker
+  alone`), and if it dominates consider checking only the faces and edges the blend touched. Owner: whoever meets a slow
+  blend on a large part.
```

`docs/superpowers/roadmap.md`:

```diff
diff --git a/docs/superpowers/roadmap.md b/docs/superpowers/roadmap.md
index aa07e87..1408421 100644
--- a/docs/superpowers/roadmap.md
+++ b/docs/superpowers/roadmap.md
@@ -35,7 +35,7 @@ Status key: ✅ done · 🔄 in progress · ⏳ ready to start · 🔒 blocked (
 | — | C7 adoption: swap the viewport's, the graph panel's and the app's input stopgaps for MetalUI C7's APIs once `feat/input-apis` merges (lists in the carry-over note, From M4, From M5, From M6) | ✅ viewport (human checks VC pass); graph panel and app ✅ merged 2026-10-09 (human checks GI pending) | MetalUI decisions file `docs/superpowers/2026-10-08-input-apis-decisions.md` |
 | — | Naming: picks on merged faces — an Edges by Tag pick on a face a union merged must survive one operand changing (spec §8's polygon swap, Errata (M6)); needs the split-edge count handled too, not only a minimal tag subset | ✅ code done (plan `2026-10-09-naming-merged-faces.md`, Errata (naming: merged faces)): a key matching nothing is retried narrowed (`EdgeKey.narrowed`), drift counts runs as well as edges (`EdgePick.runCount`, no format bump) | `BracketAcceptanceTests+PolygonSwap` (flipped: Edges by Tag resolves with no warning; the Chamfer's failure was the invalid-blends row, now done), `BracketAcceptanceTests+MergedFaces` |
 | — | Kernel: blends that return an invalid solid — OCCT's fillet of the polygon-swap hexagon's vertical edges reports done but returns a solid `BRepCheck_Analyzer` rejects, so every later fillet or chamfer along the plate top's tangent chain fails (Errata (naming: merged faces)) | ✅ code done (plan `2026-10-09-kernel-invalid-blends.md`, Errata (Kernel: invalid blends)): every fillet and chamfer result is checked (`OCCTShape.isValid`); one OCCT's checker rejects is refused, naming the largest size that works ("Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm)."); repair was probed (ShapeFix, UnifySameDomain, tolerances, fillet shapes and parameters, edge order) and can't make it valid | `BracketAcceptanceTests+PolygonSwap` (flipped: the Fillet names 2.5 mm; at 2.5 mm the Chamfer and the Output have their part), `InvalidBlendTests`, `ShapeValidityTests` |
-| — | Kernel: largest size for blends OCCT can't build — a fillet or chamfer OCCT reports not done still says "can't be rounded this much" without a maximum (spec §3, risks table: "the maximum radius where possible"); `OCCTKernel.largestValidBlend` could name one there too, at the cost of up to ~20 failing tries | ⏳ | `FeatureConformanceTests.impossibleFilletFailsCleanlyAndKernelRecovers` (its `maxRadius` would become 9.9) |
+| — | Kernel: largest size for blends OCCT can't build — a fillet or chamfer OCCT reports not done still said "can't be rounded this much" without a maximum (spec §3, risks table: "the maximum radius where possible") | ✅ code done (plan `2026-10-09-kernel-blend-max.md`, Errata (Kernel: largest size for blends OCCT can't build)): `OCCTKernel.blend` searches `largestValidBlend` for a blend OCCT reports not done too ("Radius 40 mm is too large for the selected edges (max ≈ 9.9 mm)."; a chamfer likewise); a checker that itself throws gives the generic message with no search; a size ≤ 0.1 mm no longer says "even by 0.1 mm"; the search starts from `BlendGrid.firstFailingTenths` (no `ceil` overshoot). A refused blend costs tens of milliseconds more than one that works (`BlendRefusalBench`, `docs/verification/performance.md`) | `UnbuildableBlendTests`, `BlendGridTests`, `OCCTValidityTests`, `InvalidBlendTests`, `FeatureConformanceTests.impossibleFilletFailsCleanlyAndKernelRecovers` (`maxRadius` 9.9) |
 | — | Naming: face picks on merged faces — a `FacePick` (Plane from Face) on a face a union merged names both operands' tags and matches nothing once they stop merging; narrow it like `EdgeKey.narrowed` (it has no other side, so it needs its own rule). Also not narrowed yet: an edge pick between a merged face and a third operand's face (a hole through a merged plate+flange side), since the hole wall's tags share no origin with the merged side | 💬 | Errata (naming: merged faces) |
 | — | Viewport: a selected rule's edges over the Final part — in Final preview, show the edges of a selected rule whose solid isn't shown (spec §6.3, Errata (M6)) | ⏳ after M6 | `SceneTests.aRuleSelectedInFinalPreviewGlowsOnlyOnItsOwnSolid` |
 | — | Adopt MetalUI C10 (merged as MetalUI 2155f1e): `Slider` `onEditingChanged` for the inspector's coalescing (M5-a), materials and blur for the glass panels (M5-c), the window gradient (M5-d), the refused wire's keyframe shake (M5-i), `ProgressView` for the evaluating badge (M5-j); `ColorPicker` (M6-f) is already adopted (Themes Task 11) | ⏳ | docs/metalui-gaps.md summary table |
```

`docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`:

```diff
diff --git a/docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md b/docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md
index e98fd63..3ae5b38 100644
--- a/docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md
+++ b/docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md
@@ -576,14 +576,42 @@ Plan `2026-10-09-kernel-invalid-blends.md`, roadmap row "Kernel: blends that ret
   names was built and checked). A fillet reads "Radius 3 mm is too large for the selected edges (max ≈ 2.5 mm)."; a
   chamfer "Chamfer failed: chamfering the 4 selected edges by 3 mm gives a broken solid (max ≈ 2.5 mm)."; when not even
   0.1 mm works, "…gives a broken solid, even by 0.1 mm.". The fillet message with a maximum is §3's own wording and
-  doesn't name the edge count on purpose (the error's `reason` keeps it); the others do. A blend OCCT can't build at all keeps its message, with no
-  maximum (roadmap row "Kernel: largest size for blends OCCT can't build").
+  doesn't name the edge count on purpose (the error's `reason` keeps it); the others do. A blend OCCT can't build at all
+  keeps its message, with no maximum. (Superseded: see Errata (Kernel: largest size for blends OCCT can't build), which
+  names a maximum there too, and replaces "even by 0.1 mm" for a size of 0.1 mm or less.)
 - Errata (naming: merged faces)'s polygon swap: at R3 the Fillet is now the node in error, naming 2.5 mm, and the Edges
   by Tag, Chamfer and Output after it wait for its solid. With the radius at 2.5 every node is `.ok`: the five picks
   resolve as that errata says, the Chamfer succeeds and the Output has its part.
   `BracketAcceptanceTests.swappingTheFlangeForAPolygonKeepsEveryPickOnceTheFilletFits` pins it (it replaces
   `swappingTheFlangeForAPolygonKeepsEveryPickButTheFilletedHexagonCantBeChamfered`).
 
+## Errata (Kernel: largest size for blends OCCT can't build)
+
+Plan `2026-10-09-kernel-blend-max.md`, roadmap row "Kernel: largest size for blends OCCT can't build". It completes
+§3's "max ≈ where possible" and the risks table's "the maximum radius where possible" for the kernel's blends.
+
+- §3's errors: a fillet or chamfer OCCT reports not done runs the same search as one OCCT builds but its checker rejects
+  (`OCCTKernel.largestValidBlend`, Errata (Kernel: invalid blends)): "Radius 40 mm is too large for the selected edges
+  (max ≈ 9.9 mm)." for a fillet of the 10 × 20 × 30 box's vertical edge, "Chamfer failed: the selected edges can't be
+  chamfered by 40 mm (max ≈ 9.9 mm)." for a chamfer. It costs up to about 20 more tries, each under the OCCT lock on
+  its own and stopping when the evaluation is cancelled. When no size works, the message is the old one, with no
+  maximum ("…could not be applied: the selected edges can't be rounded this much.").
+- A blend whose result the checker itself fails on (`occt_is_valid` answered -1: it threw) says nothing about any size,
+  so it gets that same generic message and no search (`OCCTValidity.unchecked`).
+- The search's grid is in `BlendGrid`: it starts from `Int((size * 10 - 1e-9).rounded(.up))` tenths of a millimetre, so
+  a size float arithmetic put a hair over the grid (`0.1 + 0.2`) names a size below it, not itself. "…even by 0.1 mm"
+  is said only when the search tried 0.1 mm, that is for a size above it; for a size of 0.1 mm or less the clause is
+  left out ("Radius 0.1 mm could not be applied: rounding the selected edge gives a broken solid.").
+- Cost, measured in a release build (`BlendRefusalBench`; figures in `docs/verification/performance.md`): a refused
+  blend costs tens of milliseconds more than one that works, on §8's hexagon flange and on the §7.2 bracket's Fillet
+  node alike. While the Fillet's radius handle is dragged past the maximum, each step pays that search; the evaluation
+  is off the main actor and cancellable. Human check M6-15 covers the drag.
+- `BRepCheck_Analyzer` runs on every blend result: a few milliseconds on the flange union. Watch it on large parts
+  (`docs/superpowers/notes/2026-10-07-m0-m1-carryover.md`).
+- `FeatureConformanceTests.impossibleFilletFailsCleanlyAndKernelRecovers` now expects `maxRadius` 9.9.
+- The 1e-9 slack makes the maximum conservative for an off-grid size (it can be a step below a size that would still
+  build).
+
 ## Errata (multi-select)
 
 - §6.2's click, box and pan rules are superseded by `2026-10-09-selection-groups-comments-design.md` §3 and its
```

`docs/verification/performance.md`:

```diff
diff --git a/docs/verification/performance.md b/docs/verification/performance.md
index 458d189..5d274ea 100644
--- a/docs/verification/performance.md
+++ b/docs/verification/performance.md
@@ -8,7 +8,7 @@ viewport or the kernel, and replace the numbers here (keep the machine, load and
 
 ```sh
 scripts/bench.sh                      # every benchmark: about 10 minutes, most of it the release build
-scripts/bench.sh GraphPanZoomBench    # one suite (also OrbitBench, FilletDragBench, KernelBench)
+scripts/bench.sh GraphPanZoomBench    # one suite (also OrbitBench, FilletDragBench, KernelBench, BlendRefusalBench)
 ```
 
 The benchmarks are Swift Testing suites in `Tests/CreatorAppTests/Bench`. A plain `swift test` skips them
@@ -102,6 +102,38 @@ judged on an idle run, which is still to do: the machine stayed loaded while thi
 | Picking renders the ID pass only when the camera or scene changes, never during a drag | `orbit-*` | not on the orbit path (the orbit frames above include no ID pass) | Nothing to measure in an orbit; a pick after it settles is one ID pass. |
 | A dragged fillet radius re-tessellates each step | `fillet-drag evaluate+mesh` | 20.44 ms, evaluation and meshing together | Met within the drag's 100 ms. |
 
+## Refused blends (Errata: Kernel, largest size for blends OCCT can't build)
+
+A refused fillet or chamfer searches for the largest size that works (`OCCTKernel.largestValidBlend`: at most 20 tries
+on a 0.1 mm grid). `scripts/bench.sh BlendRefusalBench`, 2026-10-09, MacBook Pro (MacBookPro18,2, Apple M1 Max),
+macOS 27.0.1, a release build. Load averages 79.19 / 163.02 / 143.42 before the run and 202.71 / 187.43 / 160.09 after:
+**far from idle** (other worktrees were building and testing), so read these as upper bounds on the cost; re-measure
+on an idle machine to judge them.
+
+| Part | Case | Median (p95) |
+|---|---|---|
+| §8 hexagon flange (plate + hexagon, four upright edges) | fillet R2.5, works: build + check | 16.06 ms (37.11) |
+| | fillet R3, refused: build + check + search | 95.48 ms (123.60) |
+| | the search alone | 73.07 ms (135.48) |
+| | `BRepCheck_Analyzer` alone on the union | 2.34 ms (4.97) |
+| §7.2 bracket (the Fillet node and everything after it) | radius 3.05 to 3.24, works | 32.96 ms (48.03) |
+| | radius 8.25 to 9.20, refused (the message names max ≈ 3.9 mm) | 90.40 ms (126.25) |
+
+```text
+BENCH blend-flange fillet R2.5 (works: build + check): median 16.06 ms, p95 37.11 ms, max 54.62 ms (n 25)
+BENCH blend-flange fillet R3 (refused: build + check + search): median 95.48 ms, p95 123.60 ms, max 169.51 ms (n 25)
+BENCH blend-flange search alone (largestValidBlend below R3): median 73.07 ms, p95 135.48 ms, max 174.38 ms (n 25)
+BENCH blend-flange checker alone (BRepCheck_Analyzer on the union): median 2.34 ms, p95 4.97 ms, max 6.28 ms (n 25)
+BENCH blend-bracket message: Radius 9.2 mm is too large for the selected edges (max ≈ 3.9 mm).
+BENCH blend-bracket Fillet node R3.x (works; evaluation of the Fillet and what follows): median 32.96 ms, p95 48.03 ms, max 94.26 ms (n 20)
+BENCH blend-bracket Fillet node R8.x (refused; evaluation of the Fillet and what follows): median 90.40 ms, p95 126.25 ms, max 135.85 ms (n 20)
+```
+
+A refused blend costs about 60 to 80 ms more than one that works. The evaluation runs off the main actor and a
+cancelled one stops between tries, so the window never waits for it; but a radius handle dragged past the maximum pays
+the search on every step, so its error appears about 90 ms after the drag, not 33 ms. Which refusal the bracket's
+radius 8.25 to 9.20 met (OCCT not done, or the checker rejecting) is not recorded; both run the same search.
+
 ## Raw output
 
 The run the tables above come from (`scripts/bench.sh`, every suite):
```

`docs/verification/human-checks.md` (M6-15, the one pending check that drags a Fillet radius past its maximum):

```diff
diff --git a/docs/verification/human-checks.md b/docs/verification/human-checks.md
index 0000000..0000000 100644
--- a/docs/verification/human-checks.md
+++ b/docs/verification/human-checks.md
@@ -229,14 +229,19 @@ Run `swift run GraphPanelPreview`.
   plane picker and a 3×3 anchor grid; Document Parameters below. Drag the Width slider, release, then press ⌘Z
   once: width returns to where the drag started. Select Fillet: an EDGES section reads "All Edges · 12 edges" in
   pink, a "Show handle in view" toggle that starts On, and a "Pick edges in view…" button. Select All Edges: its
-  EDGES row reads "12 edges". Drag Radius above 10: Fillet's badge turns to a red ✕ and hovering it shows the message.
+  EDGES row reads "12 edges". Drag Radius above 10: Fillet's badge turns to a red ✕ and hovering it shows
+  "Radius N mm is too large for the selected edges (max ≈ X mm).", N the radius dragged to and X a size from the part
+  (a message without a maximum is wrong). The drag stays responsive (a refused radius searches for the maximum on every step, so the badge may trail the slider by
+  a fraction of a second); dragging back below X clears the error and shows the part again. Repeat with the bracket's
+  Fillet radius handle in the viewport (spec §7.2): past the maximum, the same message.
   Select Extrude: a Distance/Symmetric segmented control, the Distance slider and a "Reverse direction" toggle that
   starts Off (no Direction menu, spec Errata (M3)).
   Add a Transform (palette): its Move row has three fields; type 5 into the middle one and the node row reads
   "0 mm, 5 mm, 0 mm". Add a Graph Parameter: its menu lists Width; choose it and the menu shows Width.
   Add a Grid Points: its Total field is empty, showing "Not set", and the node row reads "—". Type 6 and press
   Return: the row reads "6". Empty the field and press Return: it's "Not set" again. Click empty canvas and press ⌘Z: 6 comes back.
-  Pinned: `InspectorTests` (`anOptionalInputStartsUnsetAndCanBeCleared`), `CoalescingTests`. **Observed:**
+  Pinned: `InspectorTests` (`anOptionalInputStartsUnsetAndCanBeCleared`), `CoalescingTests`; the maximum in the message:
+  `UnbuildableBlendTests`, `InvalidBlendTests` (the drag's feel is this check only). **Observed:**
 - [ ] **M5-11 Keys stay with fields.** Click into the Width number field, type "75" and press Delete: the digit is
   deleted, not the node. Press Return: Width becomes 75 mm. Pinned: design (`Window.onInput` fallback),
   `mappedKeysAreRunAndClaimed`. **Observed:**

```

- [ ] **Step 2: Check the records against the code**

Run: `grep -n "largestValidBlend\|BlendGrid\|OCCTValidity" CLAUDE.md docs/superpowers/specs/*.md docs/superpowers/roadmap.md | head`
Expected: each name appears and exists in `Sources/CreatorOCCT`.

- [ ] **Step 3: Full verification.** Expected: master + 19 = **1662** tests (documents change no count), 0 lint violations.

- [ ] **Step 4: Commit**

```bash
git add docs CLAUDE.md
git commit -m "docs: blend maximum errata, roadmap, performance record, carry-over note and the M6-15 drag check"
```

---

## Self-review

- **Spec coverage:** §3/§10 "max ≈ where possible" for a not-built blend: Task 3. The four minors: size ≤ 0.1 mm (Task 2), `fails` without overshoot (Task 2), -1 to the generic message (Task 1), analyzer cost noted in the carry-over note (Task 5). Measurement on bracket and flange in release: Task 4, recorded in Task 5 (figures in `performance.md` only). Roadmap row and spec errata: Task 5. `maxRadius` 9.9: Task 3. The visible change (a refused Fillet drag): the M6-15 human check, Task 5.
- **Placeholder scan:** none; every code step is a complete file or a diff from verified code. The only values that depend on the executor's machine are the measurements, stated as such.
- **Type consistency:** `OCCTValidity` (Task 1) → `check:` closures and `attempt(blending:…)`; `BlendGrid.firstFailingTenths(for:)` and `triesSmallest(below:)` (Task 2) used by `largestValidBlend` and `invalidBlend`; `blendFailed(size:chamfer:largest:)` (Task 3) replaces the Task 1 form, and Task 1's `InvalidBlendTests` case reaches it only through `blend`, so Task 3 breaks no earlier test. The Task 1 `blend` calls `KernelError.blendFailed(size:chamfer:)`; Task 3 replaces that whole file.
- **Review Focus:** all seven lines have a named test.

## Verification (scratch copy)

The first revision's code blocks were applied task by task in a scratch copy of the worktree (with a sibling `MetalUI` symlink), each task committed, and after each: `swift build --build-tests` (no new Swift warnings), full `swift test` (exit 0, no "recorded an issue" or "failed after", 11 "Test run with" lines), `swiftlint lint --strict` (0 violations). Counts: Task 1 1647 (master + 4), Task 2 1653 (+10), Task 3 1659 (+16), Task 4 and 5 1662 (+19). The final state (Tasks 1 to 4 together) was re-run in full in a scratch copy after the review revision: exit 0, no "recorded an issue" or "failed after", 11 "Test run with" lines, total 1662, `swiftlint lint --strict` 0 violations, no new build warning; the per-task counts above for the revision are the final suites' test counts added task by task, not separate full runs; every `diff` block applies with `git apply --check` to master in order (23 tests in the five blend suites at the end). The benchmark ran once in a release build under heavy load (79 / 163 / 143 before, 203 / 187 / 160 after).
