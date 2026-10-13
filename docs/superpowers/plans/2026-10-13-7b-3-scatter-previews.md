# 7b-3 Field Scatter and Previews Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Field Scatter, the layout node that scatters points where a field says, and the field previews: the part's surface tinted by the selected field node, a translucent slice plane through the part with a handle, and a legend, drawn in three new theme roles, `fieldLow`, `fieldMid` and `fieldHigh`.

**Architecture:** Field Scatter is variable-radius Poisson-disk sampling (`PoissonScatter`, seeded by `SeededRandom`) over a face (the existing face pick, `FaceRegion`) or a profile, asking `FieldSampler` for the spacing of each round of candidates in one batch. The previews are split by who knows what: `CreatorViewport` learns numbers and colours only (`ViewportItem.fieldValues` and `FieldRamp`, a second shader pipeline, a `ViewportSlice` quad with a texture), `CreatorApp` owns a `FieldPreviewModel` that follows the selected Fields node, samples its field off the main actor through the evaluator's distance cache, and hands the scene its tint, its slice and its handle; the legend is a glass card over the viewport. Nothing is saved: the toggles, the slice's pose and the samples are view state.

**Tech Stack:** Swift 6.4 (strict concurrency), Swift Testing, SwiftLint, Metal (the viewport's runtime-compiled MSL), MetalUI (`LinearGradient`, `Toggle`, segmented `Picker`, `GlassPanel`), the C++ OCCT shim for the acceptance test. MetalUI is not touched.

**Spec:** `docs/superpowers/specs/2026-10-12-fields-design.md` (binding; this plan is its §9 row "7b-3 scatter and previews": §3.3 Field Scatter, §6 previews, §7 performance including `FieldBench` row 4 and the 200,000-vertex cap, §8 testing including the acceptance test, §4 errors and every Errata (7b-1) bullet), under `docs/superpowers/specs/2026-10-10-patterns-trees-design.md` (7a: layout rules, `SeededRandom`, `InstanceGrid`, instance naming) and `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`, each with all its Errata. The deviations this plan makes from the spec, and why, are written into the spec as Errata (7b-3) by Task 12 and listed under "User decisions" below. Baseline: branch `7b-3` at `c20210b` (the 7b-core branch: 7b-1, all green), 3,473 tests. File format stays **6**: nothing here is saved.

## Global Constraints

- Swift 6 strict concurrency; Swift Testing (`@Test`, `#expect`), never XCTest; `@MainActor @Observable` models, behaviour in models and thin views.
- One type per file; no force unwraps and no force `try`; no `DispatchQueue` or other GCD; `Task.sleep(for:)` only; numbers in text through `FormatStyle` (`formatted(.number…)`), never `NumberFormatter`/`String(format:)`.
- Numbers in user-facing messages are written in `Locale.messages` (`en_US`): "2,431", "2.5".
- Kernel work stays behind the `Kernel` protocol; only `COCCT` and `CreatorOCCT` touch OCCT. This plan adds no kernel call and no C++.
- All randomness is `SeededRandom` under a pinned `Purpose` constant (`.scatter`, "Scattr_1"); never the system generator. A value never depends on the other points of a batch.
- Fields, the samples, the tint, the slice and the legend's toggles are computed or view state, never saved; `GraphFile.currentFormatVersion` stays 6; `.mctheme` gets three roles and no format change (a file without them reads Dracula's).
- `CreatorViewport` knows nothing of fields, the graph or themes' meaning: numbers and colours only. MetalUI gaps go in `docs/metalui-gaps.md` (an entry and a summary-table row), are sent to the MetalUI session and are never worked around. This plan found none.
- Do not edit `Package.swift`'s MetalUI path; do not modify `../MetalUI`; never take screenshots; never `pkill`/`killall` by a broad pattern (`swift-test`, `swift-build`, `xctest`): other sessions run `swift test` on this Mac, so stop only your own processes, by PID or by a pattern holding your own worktree path.
- `swiftlint lint --strict` reports zero violations. A task is not done with a new compiler warning. The one warning the baseline has (`ContextMenuTests.swift:153`, line 167 once Task 4 has added lines above it: "'underPointer' mutated after capture by sendable closure") is not new.
- **A full `swift test` run passes only if** the exit code is 0, no line says "recorded an issue" or "failed after" (Swift Testing prints glyphs, not ✘), and 11 "Test run with" lines appear. The counts below are "master + N" (master here is `c20210b`, 3,473 tests) and are the sum of the "Test run with … tests" lines. **Gate 0, before Task 1:** run `git -C ../MetalUI rev-parse --short HEAD` and the full suite once in this worktree with no change made. Expected: green by the rule above, 3,473 tests (the plan was verified against `../MetalUI` at `b17aee19`). If it is anything else (a red test, another count), stop and report it before Task 1.
- **Timings.** The Mac is shared and often saturated: a full `swift test` is slow, so run it in the background to a log and wait (`swift test > /tmp/7b3.log 2>&1; echo "exit $?" >> /tmp/7b3.log &`). A `FieldBench` timing taken on a loaded machine is recorded as **saturated** with the load it was taken under, never as met or missed.
- Messages follow the house style: plain sentences naming what to do ("Field Scatter needs a region: wire a solid and pick one of its flat faces, or wire a profile.").

## Review Focus

The spec says what scatter and the previews must do; it is silent on inputs like these, which a person using the software will meet. Each line names the input, what a reasonable person expects, and the test that pins it.

1. **A region the margin eats, or a region with a hole.** A 10 mm square with a 6 mm margin has no room: the node says so ("Field Scatter found no room for a point…") instead of returning nothing; a face's hole and its margin stay empty. Tasks 2 and 3: `aRegionTheMarginEatsGivesNoPoints`, `aMarginThatEatsTheRegionLeavesNoRoom`, `aHoleAndItsMarginStayEmpty` (the sampler's, on a polygon hole), `aHoleInTheFaceAndItsMarginStayEmpty` (a face's).
2. **A spacing that is a typo.** "minSpacing 0.01" over a big face must answer at once, not hang: the search stops at 8,000 points and says "more than 8,000"; a spacing of 0 or below, a maximum below the minimum, a negative margin and a list in an input each get their own sentence. Task 3: `farMoreThanThatSaysMoreThanTheCeiling`, `moreThanTwoThousandPointsSaysHowManyWouldHaveBeenPlaced`, `aBadNumberIsRefusedInWords`, `aMaximumBelowTheMinimumIsRefused`, `aListWiredIntoASingleValuedInputIsRefusedInTheLayoutsWords`.
3. **A field with a step in it, and a region in pieces.** Spacing that jumps from small to large, or islands a margin cuts off, must still be filled, not stop at the first piece. Task 2: `densityFollowsTheSpacing`, `islandsTheMarginCutOffAreAllFilled`.
4. **A field that fails, or has no value.** A kernel error or a NaN is the node's error or the legend's red sentence, never a silent zero or a stale tint. Tasks 3 and 8: `aFieldThatIsNotANumberSomewhereIsRefusedNotTreatedAsZero`, `aFailedSamplingSaysSoInTheKernelsWordsAndKeepsNoTint`, `withNothingSampledTheItemsAreHandedBackAsTheyAre`.
5. **Editing or selecting while the preview is sampling.** A newer request supersedes the older and publishes nothing of it; the old tint stays until the new one is ready (no grey flash); selecting something else, picking edges, or opening another document takes the preview away. Tasks 8 and 9: `aNewerRequestSupersedesAnOlderOneWhichPublishesNothing`, `anEditedFieldKeepsTheOldTintUntilTheNewOneIsReady`, `noRequestStopsEverythingAndIsQuietWhenThereWasNothing`, `aPickInProgressTakesThePreviewAwayAndEndingItBringsItBack`, `openingAnotherDocumentStartsThePreviewOver`, `theLegendGoesWhenTheSelectionDoes`.

(Also pinned where they bite: a mesh with more than 200,000 vertices, `CoarseSamplingTests`; a part with no vertices to tint or no box to size the slice, `thePartsSliceIsAbsentWithNoPart`; values of the wrong count or not numbers in the shader, `FieldTintRenderTests`, `valuesThatAreNotNumbersDrawTheMiddleColour`.)

## Files shared with other tracks

7b-2 (images and format 7, `../MetalCreator-7b-2`, also off `c20210b`) runs beside this plan, and 7b-core only waits on a bench run. The files this plan changes that 7b-2 changes too, and what the side that merges second must keep:

| File | This plan | 7b-2 | The second to merge keeps |
|---|---|---|---|
| `CLAUDE.md` | the 7b-3 paragraph, the node count 65 and "thirteen", Field Scatter, the roles, the viewport tint and slice, the app's preview | its own notes, the count, the image paragraphs | both sides' text; the node count is the sum (66 and "fourteen" with Image Field) |
| `docs/verification/human-checks.md` | group FI (before group C23) | its image and relink checks (FI-img) | both groups |
| `docs/superpowers/roadmap.md` | the 7b-3 row | the 7b-2 row | both rows |
| `docs/superpowers/specs/2026-10-12-fields-design.md` | "Errata (7b-3)" | an "Errata (7b-2)" | both sections |
| `Sources/CreatorNodes/BuiltInNodes.swift` | adds Field Scatter after Cull by Field | adds Image Field after Noise Field | both lists |
| `Tests/CreatorNodesTests/OutputNodeTests.swift`, `Tests/CreatorEditorTests/FieldsLibraryTests.swift` | counts 65 and `.fields: 13`, "Field Scatter" last, and the three that take a field | +1 each | the sums (66, `.fields: 14`) and both names |
| `Sources/CreatorGraph/Field/Field.swift` | `Field: Hashable` | `case image(…)` | the case, and a `GreyImage` that is `Hashable` (the derived conformance needs it) |
| `Sources/CreatorGraph/Field/Field+Preview.swift` (new) | `ownPlane`, `measuresWithKernel`, `isSignedDistance`, `unit`, each an exhaustive `switch` | adds the image case to all four: the compiler lists them (`ownPlane` is the image's plane, `measuresWithKernel` false, `unit` none) | 7b-2's cases |
| `Sources/CreatorGraph/DocumentModel.swift` | `fieldDistances` | may add an image-cache accessor | both |
| `Sources/CreatorGraph/InspectorControl.swift`, `Sources/CreatorEditor/InspectorControl+Socket.swift`, `Sources/CreatorEditor/InspectorBuilder.swift`, `Tests/CreatorNodesTests/CatalogTests.swift` | `case note(String)` and its row | the image chooser and Relink controls | every new case in the enum, the `socket` switch, the row builder and the two test switches |
| `Sources/CreatorApp/AppModel.swift`, `AppModel+Scene.swift`, `AppModel+Viewport.swift` | `fieldPreview`, the tint, slice and handle in `refreshScene()`, the handle in `handleChanged` | the relink alert and file switching, if it touches them | both edits |
| `docs/superpowers/plans/` | this plan | its plan | both |

Files only this plan touches: everything in `Sources/CreatorViewport` (the tint, the slice, the shaders), `Sources/CreatorStyle` (the roles, `GlassSurface.fieldLegend`), `Sources/CreatorApp/FieldPreview`, `FaceLayout`, the legend and layout, `LayoutPreview`, `FacePatternNode` (`pickedFace` stops being `private`), `FaceRegion+Profile`, the viewport's context menu and events, `UndoName`, the bench files and `docs/verification/performance.md` (7b-core's gate may replace its row 2 lines when it passes: keep both its lines and the rows added here).

## What 7b-2 will extend

- `Field` gets one case (`image`). Because `Field: Hashable` is derived, its payload (the decoded `GreyImage`, a plane, a size, an edge mode) must be `Hashable` too. The compiler then lists the places with no `default`: `Field.children`, `Field.recipe(inside:)`, `Sampling.values(of:at:)` (7b-1) and, from this plan, the four switches in `Field+Preview.swift`.
- A preview of Image Field needs nothing else: `FieldPreviewSelection` selects it (it is a Fields node), `FieldPreviewSampler` samples it, the slice starts on its plane through `ownPlane`.

## File structure

| File | Responsibility |
|---|---|
| `Sources/CreatorStyle/ThemeColors.swift`, `ThemeRole+All.swift`, `ThemeRoleGroup.swift`, `ColorTheme+*.swift`, `GlassSurface.swift` | the three ramp roles, their group, the legend's glass |
| `Sources/CreatorNodes/Fields/PoissonScatter.swift` | variable-radius Poisson-disk sampling, batched |
| `Sources/CreatorNodes/Fields/Using/FieldScatterNode.swift`, `Sources/CreatorNodes/Patterns/Layouts/FaceRegion+Profile.swift` | the node; a profile read as a region |
| `Sources/CreatorGraph/InspectorControl.swift`, `Sources/CreatorEditor/InspectorBuilder.swift` | the `.note` help line |
| `Sources/CreatorApp/LayoutPreview*.swift`, `FaceLayout.swift`, `AppModel+PatternOnFace.swift`, `AppModel+ScatterOnFace.swift`, `Sources/CreatorViewport/Model/ViewportMenuItem.swift`, `ViewportEvents.swift`, `ViewportModel+ContextMenu.swift`, `Sources/CreatorGraph/UndoName.swift` | triads for a scatter; "Scatter on Face" |
| `Sources/CreatorViewport/Model/FieldRamp.swift`, `ViewportItem.swift`, `ViewportSlice.swift`, `ViewportModel+Meshes.swift`, `ViewportModel.swift`, `ViewportRenderKey.swift` | the ramp, the item's tint, the slice, the mesh accessor |
| `Sources/CreatorViewport/Render/FieldShaders.swift`, `FieldRampUniforms.swift`, `SliceUniforms.swift`, `SliceTextures.swift`, `GPUGeometry+Field.swift`, `GPUMesh.swift`, `ViewportRenderer*.swift`, `ViewportPipelines.swift`, `ViewportFrame.swift`, `FrameItem.swift` | the tint and slice on the GPU |
| `Sources/CreatorGraph/Field/Field+DistanceSource.swift`, `Field+Preview.swift`, `FieldUnit.swift` | field equality and what the previews ask of a field |
| `Sources/CreatorApp/FieldPreview/*.swift` | selection, range, coarse sampling, sampler, slice pose, the model, the legend's words |
| `Sources/CreatorApp/AppModel+FieldPreview.swift`, `AppModel*.swift`, `ViewportItem+Comparison.swift` | the preview in the scene and the handle |
| `Sources/CreatorApp/FieldLegendView.swift`, `FieldLegendDock.swift`, `AppLayout.swift`, `AppRoot.swift` | the legend and where it stands |
| `Tests/CreatorNodesTests/FieldsAcceptanceTests.swift`, `Tests/CreatorAppTests/Bench/*` | the acceptance test; benchmark rows 3 and 4 |
| `CLAUDE.md`, `docs/…` | notes, errata, human checks, performance record |

## User decisions (confirm or change before building)

The spec leaves these open (theme roles and on-screen looks are yours). Each task is written for the recommended default; the alternative says what would change.

| # | Decision | Built (recommended) | Alternative and what it would change |
|---|---|---|---|
| 1 | The ramp's colours | Cool to warm from each theme's existing accents: Dracula cyan `#8be9fd`, yellow `#f1fa8c`, red `#ff5555`; Alucard `#036a96`, `#846e15`, `#cb3a2a`; Nord `#88c0d0`, `#ebcb8b`, `#bf616a`. Reads as cold, neutral, hot, and keeps the middle (0 of a signed distance) the neutral | A purple, pink, orange ramp (`#bd93f9`, `#ff79c6`, `#ffb86c`) in the theme's own accents: calmer, less self-explanatory. Only Task 1's twelve hex values change |
| 2 | Where the roles are listed | A new theme-editor group "Field preview", last | The roles under "The model": no new group, but `ThemeRoleGroup` keeps its eight cases and the roles sit in the middle of `ThemeRole.all` (Task 1's tests change) |
| 3 | The legend | A 220 pt glass card above the axis triad at the viewport's lower left: a ramp bar, three numbers ("-14.5 mm", "0 mm", "14.5 mm"), notes, a "0…1" toggle and the slice buttons (Plane when the field has one, XY, YZ, XZ, Off) | Over the triad's place, or at the lower right under the unit label: change `AppLayout.legendInsets` and the dock's alignment (Task 9) |
| 4 | The tint's look | The ramp colour shaded by the same light as the plain surface (`0.55 + 0.45 × lit`), edges still drawn, hover and selection blended | A flat ramp colour, no shading: simpler shader, but a part loses its form (Task 5's fragment shader and its test thresholds) |
| 5 | The slice's look | A quad at 85% opacity drawn over everything ignoring depth (it passes through the part), no border, moved by the existing arrow handle | Depth-tested so the part hides the half behind it (hides the half inside the solid too); or an outline, or a different opacity (Task 6) |
| 6 | The slice grid | 256 × 256, or 64 × 64 when the field measures a solid, faces or edges with the kernel (65,536 kernel distances take seconds on OCCT and the grid resamples on every step of a handle drag) | 256 × 256 always, as the spec says: a drag on a distance field would stall. Only `SlicePose.resolution` (Task 7) changes, and `field-4` would need re-measuring at 256² against its 150 ms budget (it may stall or miss, since each step resamples 65,536 kernel distances) |
| 7 | How a face gets a Field Scatter | A face-menu item "Scatter on Face" beside "Pattern on Face" (the pick is only ever made by such an item) | No item: a scatter could then only fill a profile (the `profile` input), and the spec's picked flat face would have no way to be picked; or a pick control in the inspector (a new control, not in this plan) |
| 8 | The slice when a field node is selected | Shown from the start (spec: "it starts on…"), hidden with the legend's Off | Hidden until a button is pressed: `FieldPreviewModel.follow` starts with `.hidden` and the start rule is used when a button first shows it |
| 9 | Field Scatter's defaults | `minSpacing` 6 mm, `maxSpacing` 12 mm, `margin` 3 mm (Face Pattern's), `field` the number 0.5 (spacing 9 mm everywhere), `seed` 0; a result with no room is an error, never an empty list | Other numbers: Task 3's `inputs` list only |
| 10 | The benchmark rows' numbers | Row 3 is Field Scatter (`field-3`); 7b-1's Sample Field + Cull by Field row is kept as `field-3b`; row 4 is `field-4` (a Remap of the bracket's signed distance), with `field-4b` (no kernel) and `field-4c` (the cold tint); `field-3` and `field-4` are verdict rows that need an idle `scripts/bench.sh FieldBench` run before 7b-3 merges (stop and ask on a miss), the others are recorded only | Fold 3b back or gate row 4 on the radial variant: Task 11's labels and budgets |

---

### Task 1: The three theme roles `fieldLow`, `fieldMid`, `fieldHigh`

**Files:**
- Modify: `Sources/CreatorStyle/ThemeColors.swift`, `Sources/CreatorStyle/ThemeRole+All.swift`, `Sources/CreatorStyle/ThemeRoleGroup.swift`
- Modify: `Sources/CreatorStyle/ColorTheme+Dracula.swift`, `ColorTheme+Alucard.swift`, `ColorTheme+Nord.swift`
- Modify: `Tests/CreatorStyleTests/ThemeRoleTests.swift`, `Tests/CreatorStyleTests/ThemeTests.swift`
- Test: `Tests/CreatorStyleTests/FieldRampRoleTests.swift`

**Interfaces:**
- Consumes: `ThemeColors`, `ThemeRole`, `ThemeRoleGroup`, `ThemeFile`, `HexColor` (all exist).
- Produces: `ThemeColors.fieldLow`, `.fieldMid`, `.fieldHigh` (`HexColor`); `ThemeRole.named("fieldLow")` and the other two, in `ThemeRoleGroup.fieldPreview` (title "Field preview"), last in `ThemeRole.all`. Task 6 and Task 10 read the colours as `colors.fieldLow.rgba` and `.color`.

A `.mctheme` file needs no change: `ThemeFile.decode` already starts from Dracula's quantized colours and keeps them for a role the file lacks (`ThemeFile` documentation), so a file written before this task reads the three roles as Dracula's. The theme editor lists roles by group (`ThemeRoleList` walks `ThemeRoleGroup.allCases`), so the new group appears there with no view change.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorStyleTests/FieldRampRoleTests.swift`:

```swift
import CreatorStyle
import Foundation
import Testing

/// The field preview's ramp (fields spec §6, D13): three theme roles, not a fixed palette.
struct FieldRampRoleTests {
    @Test func theThreeRolesAreTheLastAndShareOneGroup() {
        let names = ThemeRole.all.suffix(3).map(\.name)
        #expect(names == ["fieldLow", "fieldMid", "fieldHigh"])
        #expect(ThemeRoleGroup.fieldPreview.roles.map(\.name) == names)
        #expect(ThemeRoleGroup.fieldPreview.title == "Field preview")
        #expect(ThemeRoleGroup.allCases.last == .fieldPreview)
        #expect(ThemeRole.named("fieldMid")?.title == "Field middle")
        #expect(ThemeRole.all.suffix(3).allSatisfy { !$0.allowsOpacity })
    }

    @Test(arguments: ColorTheme.builtIns)
    func everyBuiltInGivesThreeDistinctRampColours(_ theme: ColorTheme) {
        let colours = [theme.colors.fieldLow, theme.colors.fieldMid, theme.colors.fieldHigh]
        #expect(Set(colours).count == 3, "\(theme.name): a ramp of two equal colours shows nothing")
        #expect(colours.allSatisfy { $0.opacity == 1 })
    }

    @Test func draculasRampRunsCoolToWarm() {
        let colors = ColorTheme.dracula.colors
        #expect(colors.fieldLow == HexColor(0x8be9fd) && colors.fieldMid == HexColor(0xf1fa8c) && colors.fieldHigh == HexColor(0xff5555))
    }

    @Test func aThemeFileWithoutTheRolesReadsDraculasValues() throws {
        let file = Data(##"{"version":1,"name":"Old","dark":true,"colors":{"accent":"#112233"}}"##.utf8)
        let theme = try ThemeFile.decode(file, id: "old", fallbackName: "Old")
        let dracula = ColorTheme.dracula.colors.quantized
        #expect(theme.colors.accent == HexColor(0x112233))
        #expect(theme.colors.fieldLow == dracula.fieldLow && theme.colors.fieldMid == dracula.fieldMid)
        #expect(theme.colors.fieldHigh == dracula.fieldHigh)
    }

    @Test func aThemeFileKeepsTheRolesItHolds() throws {
        var custom = ColorTheme.nord
        custom.colors.fieldLow = HexColor(0x010203)
        custom.colors.fieldHigh = HexColor(0xa0b0c0)
        let bytes = try ThemeFile.encode(custom)
        #expect(String(bytes: bytes, encoding: .utf8)?.contains("\"fieldLow\"") == true)
        let back = try ThemeFile.decode(bytes, id: "custom", fallbackName: "x")
        #expect(back.colors.fieldLow == HexColor(0x010203) && back.colors.fieldHigh == HexColor(0xa0b0c0))
        #expect(back.colors.fieldMid == ColorTheme.nord.colors.fieldMid.quantized)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | tail -20`
Expected: FAIL to compile, "value of type 'ThemeColors' has no member 'fieldLow'" and "type 'ThemeRoleGroup' has no member 'fieldPreview'".

- [ ] **Step 3: Add the three roles**

Edit `Sources/CreatorStyle/ThemeColors.swift`:

```swift-old
    /// Geometry projected from the model.
    public var sketchProjected: HexColor
}
```

```swift-new
    /// Geometry projected from the model.
    public var sketchProjected: HexColor

    // The field preview (fields spec §6, D13): the ramp a field's value is drawn in on the part's surface, on the slice plane
    // and in the legend, from its lowest value to its highest.
    public var fieldLow: HexColor
    /// The middle of the ramp: the range's midpoint, or 0 for a signed distance.
    public var fieldMid: HexColor
    public var fieldHigh: HexColor
}
```

Edit `Sources/CreatorStyle/ThemeRole+All.swift`:

```swift-old
        ThemeRole("sketchProjected", "Projected", .sketcher, \.sketchProjected),
    ]
```

```swift-new
        ThemeRole("sketchProjected", "Projected", .sketcher, \.sketchProjected),
        ThemeRole("fieldLow", "Field low", .fieldPreview, \.fieldLow),
        ThemeRole("fieldMid", "Field middle", .fieldPreview, \.fieldMid),
        ThemeRole("fieldHigh", "Field high", .fieldPreview, \.fieldHigh),
    ]
```

Edit `Sources/CreatorStyle/ThemeRoleGroup.swift`:

```swift-old
    case surfaces, text, interaction, nodes, status, model, widgets, sketcher
```

```swift-new
    case surfaces, text, interaction, nodes, status, model, widgets, sketcher, fieldPreview
```

Edit `Sources/CreatorStyle/ThemeRoleGroup.swift`:

```swift-old
        case .sketcher: "Sketcher"
```

```swift-new
        case .sketcher: "Sketcher"
        case .fieldPreview: "Field preview"
```

Edit `Sources/CreatorStyle/ColorTheme+Dracula.swift`:

```swift-old
        sketchProjected: HexColor(0xbd93f9)
    ))
```

```swift-new
        sketchProjected: HexColor(0xbd93f9),
        fieldLow: HexColor(0x8be9fd), fieldMid: HexColor(0xf1fa8c), fieldHigh: HexColor(0xff5555)
    ))
```

Edit `Sources/CreatorStyle/ColorTheme+Alucard.swift`:

```swift-old
        sketchProjected: HexColor(0x644ac9)
    ))
```

```swift-new
        sketchProjected: HexColor(0x644ac9),
        fieldLow: HexColor(0x036a96), fieldMid: HexColor(0x846e15), fieldHigh: HexColor(0xcb3a2a)
    ))
```

Edit `Sources/CreatorStyle/ColorTheme+Nord.swift`:

```swift-old
        sketchProjected: HexColor(0x5e81ac)
    ))
```

```swift-new
        sketchProjected: HexColor(0x5e81ac),
        fieldLow: HexColor(0x88c0d0), fieldMid: HexColor(0xebcb8b), fieldHigh: HexColor(0xbf616a)
    ))
```

Edit `Tests/CreatorStyleTests/ThemeRoleTests.swift`:

```swift-old
        #expect(ThemeRole.all.count == 38)
```

```swift-new
        #expect(ThemeRole.all.count == 41)
```

Edit `Tests/CreatorStyleTests/ThemeTests.swift`:

```swift-old
            (c.sketchProjected, 0xbd93f9),
        ]
```

```swift-new
            (c.sketchProjected, 0xbd93f9), (c.fieldLow, 0x8be9fd), (c.fieldMid, 0xf1fa8c), (c.fieldHigh, 0xff5555),
        ]
```

- [ ] **Step 4: Run the style and app tests**

Run: `swift test --filter CreatorStyleTests 2>&1 | tail -15` then `swift test --filter ThemeEditor 2>&1 | tail -15`
Expected: PASS (the theme editor's render tests draw the longer role list).

- [ ] **Step 5: Lint and run the whole suite**

Run: `swiftlint lint --strict` (zero violations), then the full run in the background: `swift test > /tmp/7b3-t1.log 2>&1; echo "exit $?" >> /tmp/7b3-t1.log &` and judge it by the rule in Global Constraints.
Expected: master + 5 tests (3,478).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorStyle Tests/CreatorStyleTests
git commit -m "feat: fieldLow, fieldMid and fieldHigh theme roles (7b-3)"
```
### Task 2: The scatter random purpose and Poisson-disk sampling

**Files:**
- Modify: `Sources/CreatorNodes/Patterns/Variation/SeededRandom.swift`
- Create: `Sources/CreatorNodes/Fields/PoissonScatter.swift`
- Test: `Tests/CreatorNodesTests/Fields/PoissonScatterTests.swift`

**Interfaces:**
- Consumes: `SeededRandom` (`init(seed:stream:purpose:)`, `unit(at:)`), `FaceRegion` (`bounds`, `allows(_:margin:)`), `Vector2`.
- Produces (Task 3 relies on these exact names):
  - `SeededRandom.Purpose.scatter`, raw value `0x5363_6174_7472_5F31` ("Scattr_1").
  - `struct PoissonScatter: Sendable` with
    `init(region: FaceRegion, margin: Double, minSpacing: Double, maxSpacing: Double, seed: Int, ceiling: Int)` and
    `func scatter(spacing: ([Vector2]) async throws -> [Double]) async throws -> PoissonScatter.Outcome`, where
    `Outcome` is `{ points: [Vector2], reachedCeiling: Bool }`. `spacing` receives a batch of points of the region and returns the spacing at each, in the same order.

**How it works (so a reader can check the maths).** Bridson's method with a radius that varies by point. A seed is a draw inside the region's box that the region allows, that is not closer than `minSpacing` to a placed point and, once the field gives its spacing, not closer than that spacing to any. Then rounds: every active point makes 30 candidates in the annulus between its own spacing `r` and `2r` (area-uniform), the candidates the region refuses or that lie closer than `minSpacing` to a placed point are dropped, the field is asked for the spacing of all that remain in **one** batch, and then, in the active points' order, each active point takes its first candidate that is at least its own spacing from every placed point (including the ones taken earlier in the round). A point that took a candidate stays active with 30 fresh draws; one that took none is retired. When nothing is active, a new seed is drawn: that is what fills a region the margin has split into islands, and a part of the region the annuli could not reach because the spacing jumped (a step in the field, from small spacing to large). The search ends when 1,024 seed draws in a row find no room. Every draw is `SeededRandom(seed:stream:purpose:.scatter)` with stream 0 for seeds (the draw index counting all seed draws) and the parent's index plus one for a parent's candidates (the draw index counting that parent's attempts), so a draw depends on the seed and the place and never on how the candidates were batched: the same inputs give the same points on the same platform (candidate positions use libm `cos` and `sin`, which can differ in the last bit between architectures or OS versions, so a point on a region's edge could flip; a libm change means re-pinning the counts in `FieldScatterNodeTests` and `FieldsAcceptanceTests`). Because a candidate's spacing is at least `minSpacing`, no two points are ever closer than `minSpacing`. The search stops once more than `ceiling` points exist, which lets the node say how many it would have placed.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorNodesTests/Fields/PoissonScatterTests.swift`:

```swift
import CreatorGeometry
import Testing
@testable import CreatorNodes

/// Variable-radius Poisson-disk sampling (fields spec §3.3, §8: "no two points closer than minSpacing; density follows the
/// field; same inputs, same points").
struct PoissonScatterTests {
    static func box(_ width: Double, _ height: Double) -> FaceRegion {
        FaceRegion(loops: [[Vector2(0, 0), Vector2(width, 0), Vector2(width, height), Vector2(0, height)]])
    }

    static func scatter(_ region: FaceRegion, margin: Double = 0, min: Double = 5, max: Double = 5, seed: Int = 1,
                        ceiling: Int = 8_000, spacing: @escaping @Sendable (Vector2) -> Double = { _ in 5 }) async throws
        -> PoissonScatter.Outcome {
        try await PoissonScatter(region: region, margin: margin, minSpacing: min, maxSpacing: max, seed: seed, ceiling: ceiling)
            .scatter { points in points.map(spacing) }
    }

    static func nearestPair(_ points: [Vector2]) -> Double {
        var nearest = Double.infinity
        for (index, a) in points.enumerated() {
            for b in points[(index + 1)...] { nearest = Swift.min(nearest, (a - b).length) }
        }
        return nearest
    }

    @Test func thePurposeAndItsFirstDrawArePinned() {
        #expect(SeededRandom.Purpose.scatter.rawValue == 0x5363_6174_7472_5F31)
        #expect(SeededRandom(seed: 5, purpose: .scatter).value(at: 0) == 0xC09C_3D16_F529_5801)
        #expect(SeededRandom(seed: 5, stream: 3, purpose: .scatter).value(at: 0) == 0xD7DC_9517_E196_AFB9)
        #expect(SeededRandom(seed: 5, purpose: .scatter).value(at: 0) != SeededRandom(seed: 5, purpose: .fieldCull).value(at: 0))
    }

    @Test func noTwoPointsAreCloserThanTheMinimumAndEveryPointIsInsideTheMargin() async throws {
        let region = Self.box(60, 40)
        let outcome = try await Self.scatter(region, margin: 3, min: 5, max: 5)
        #expect(outcome.points.count >= 40, "a 54 × 34 area at spacing 5 holds dozens: \(outcome.points.count)")
        #expect(Self.nearestPair(outcome.points) >= 5 - 1e-9)
        #expect(outcome.points.allSatisfy { region.allows($0, margin: 3) })
        #expect(!outcome.reachedCeiling)
    }

    @Test func aHoleAndItsMarginStayEmpty() async throws {
        let hole = [Vector2(20, 10), Vector2(40, 10), Vector2(40, 30), Vector2(20, 30)]
        let region = FaceRegion(loops: [[Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)], hole])
        let outcome = try await Self.scatter(region, margin: 2)
        #expect(outcome.points.count > 10)
        #expect(outcome.points.allSatisfy { !(18...42).contains($0.x) || !(8...32).contains($0.y) })
    }

    @Test func islandsTheMarginCutOffAreAllFilled() async throws {
        let left = [Vector2(0, 0), Vector2(20, 0), Vector2(20, 20), Vector2(0, 20)]
        let right = [Vector2(60, 0), Vector2(80, 0), Vector2(80, 20), Vector2(60, 20)]
        let outcome = try await Self.scatter(FaceRegion(loops: [left, right]), min: 5, max: 5)
        #expect(outcome.points.filter { $0.x < 40 }.count >= 8 && outcome.points.filter { $0.x > 40 }.count >= 8)
        #expect(Self.nearestPair(outcome.points) >= 5 - 1e-9)
    }

    @Test func sameInputsGiveTheSamePointsAndAnotherSeedGivesOthers() async throws {
        let region = Self.box(60, 40)
        let first = try await Self.scatter(region, seed: 7)
        let again = try await Self.scatter(region, seed: 7)
        let other = try await Self.scatter(region, seed: 8)
        #expect(first == again)
        #expect(first.points != other.points)
    }

    @Test func densityFollowsTheSpacing() async throws {
        // Spacing 4 in the left half of a 100 × 40 box and 10 in the right: about (10 / 4)² = 6 times the points on the left.
        let outcome = try await Self.scatter(Self.box(100, 40), min: 4, max: 10) { $0.x < 50 ? 4 : 10 }
        let left = outcome.points.filter { $0.x < 50 }.count
        let right = outcome.points.count - left
        #expect(right > 0 && left > 3 * right, "left \(left), right \(right)")
        #expect(Self.nearestPair(outcome.points) >= 4 - 1e-9)
    }

    @Test func aPointIsAtLeastItsOwnSpacingFromEveryOneBeforeIt() async throws {
        // The spacing grows along x: each point keeps its own spacing's distance from the points placed before it.
        let spacing: @Sendable (Vector2) -> Double = { 4 + $0.x / 20 }
        let outcome = try await Self.scatter(Self.box(100, 40), min: 4, max: 9, spacing: spacing)
        for (index, point) in outcome.points.enumerated() {
            let nearest = outcome.points[..<index].map { ($0 - point).length }.min() ?? .infinity
            #expect(nearest >= spacing(point) - 1e-9, "point \(index) at \(point)")
        }
    }

    @Test func theSpacingIsAskedForInBatchesNeverPointByPoint() async throws {
        let log = BatchLog()
        let outcome = try await PoissonScatter(region: Self.box(60, 40), margin: 0, minSpacing: 5, maxSpacing: 5, seed: 1, ceiling: 8_000)
            .scatter { points in
                await log.record(points.count)
                return points.map { _ in 5 }
            }
        let calls = await log.sizes
        #expect(calls.count < outcome.points.count, "one call per round of candidates, fewer calls than points")
        #expect(calls.max() ?? 0 > 1)
    }

    @Test func itStopsOnceMoreThanTheCeilingExist() async throws {
        let outcome = try await Self.scatter(Self.box(200, 200), min: 2, max: 2, ceiling: 100) { _ in 2 }
        #expect(outcome.reachedCeiling && outcome.points.count == 101)
    }

    @Test func aRegionTheMarginEatsGivesNoPoints() async throws {
        let outcome = try await Self.scatter(Self.box(10, 10), margin: 6)
        #expect(outcome.points.isEmpty && !outcome.reachedCeiling)
    }

    @Test func aCancelledScatterStopsWithCancellationError() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await Self.scatter(Self.box(60, 40))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

/// Collects the sizes of the batches the sampler was asked for.
actor BatchLog {
    private(set) var sizes: [Int] = []

    func record(_ count: Int) {
        sizes.append(count)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: FAIL to compile, "cannot find 'PoissonScatter' in scope" and "type 'SeededRandom.Purpose' has no member 'scatter'".

- [ ] **Step 3: Add the purpose and the sampler**

Edit `Sources/CreatorNodes/Patterns/Variation/SeededRandom.swift`:

```swift-old
        /// Cull by Field, Probability: "FCull__1".
        case fieldCull = 0x4643_756C_6C5F_5F31
```

```swift-new
        /// Cull by Field, Probability: "FCull__1".
        case fieldCull = 0x4643_756C_6C5F_5F31
        /// Field Scatter: "Scattr_1".
        case scatter = 0x5363_6174_7472_5F31
```

Create `Sources/CreatorNodes/Fields/PoissonScatter.swift`:

```swift
import CreatorGeometry
import Foundation

/// Variable-radius Poisson-disk sampling of a flat region (fields spec §3.3), Bridson's method: "Fast Poisson Disk Sampling
/// in Arbitrary Dimensions" (SIGGRAPH 2007), with the radius taken from a field at each candidate.
///
/// A seed is a draw inside the region's box that the region allows and that is clear of the points placed so far. Then, in
/// rounds, every active point makes `candidatesPerPoint` candidates in the annulus from its own spacing `r` to `2r` (uniform by
/// area); the candidates the region refuses, or that are closer than `minSpacing` to a placed point, are dropped without asking
/// the field; the spacing of all that remain is asked for in one batch (the field is sampled once per round, never once per
/// candidate); and then each active point, in order, takes its first candidate that is at least that candidate's spacing from
/// every placed point, those taken earlier in the round included. A point that took one stays active with a fresh set of
/// draws, one that took none is retired. When none is active a new seed is drawn, which fills islands the margin cut off and
/// the parts of the region the annuli cannot reach across a jump in the spacing; the search ends when `seedingTries` seed draws
/// in a row find no room.
///
/// Every draw is `SeededRandom(seed:stream:purpose: .scatter)`: stream 0 for seeds, parent index + 1 for a parent's
/// candidates, the draw index counting that stream's draws. A draw depends on the seed and the place alone, never on how the
/// candidates were batched, so the same inputs give the same points on the same platform (libm `cos` and `sin` may differ in the last bit across architectures or OS versions). A spacing is at least `minSpacing`, so
/// no two points are ever closer than that.
struct PoissonScatter: Sendable {
    /// Candidates tried round an active point before it is retired.
    static let candidatesPerPoint = 30
    /// Seed draws in a row that may find no room before the search ends.
    static let seedingTries = 1_024
    /// Seed draws spaced by one call to the field.
    static let seedBatch = 64

    let region: FaceRegion
    let margin: Double
    let minSpacing: Double
    let maxSpacing: Double
    let seed: Int
    /// The search stops once more than this many points exist, so a node can say how many it would have placed.
    let ceiling: Int

    struct Outcome: Equatable, Sendable {
        var points: [Vector2]
        /// True when the search stopped at the ceiling: there would have been more than `points.count - 1` points.
        var reachedCeiling: Bool
    }

    /// The points, in the order they were placed. `spacing` is given a batch of points of the region and returns the spacing at
    /// each, in the same order (at least `minSpacing` and at most `maxSpacing`).
    func scatter(spacing: ([Vector2]) async throws -> [Double]) async throws -> Outcome {
        try Task.checkCancellation()
        guard let box = region.bounds, minSpacing > 0, maxSpacing >= minSpacing else {
            return Outcome(points: [], reachedCeiling: false)
        }
        var placed = Placed(origin: box.min, width: max(minSpacing, maxSpacing / 16))
        var seedDraws = 0
        var active: [Active] = []
        while placed.points.count <= ceiling {
            try Task.checkCancellation()
            if active.isEmpty {
                guard let seed = try await nextSeed(in: box, placed: placed, draws: &seedDraws, spacing: spacing) else { break }
                placed.add(seed.point, radius: seed.radius)
                active = [Active(index: placed.points.count - 1, attempt: 0)]
                continue
            }
            let options = active.map { candidates(of: $0, placed: placed) }
            let flat = options.flatMap { $0 }
            let radii = flat.isEmpty ? [] : try await spacing(flat)
            precondition(radii.count == flat.count, "the spacing closure must return one value per point")
            var kept: [Active] = []
            var children: [Active] = []
            var next = 0
            for (parent, choices) in zip(active, options) {
                var tookOne = false
                for (offset, point) in choices.enumerated() where placed.isClear(point, within: radii[next + offset]) {
                    placed.add(point, radius: radii[next + offset])
                    children.append(Active(index: placed.points.count - 1, attempt: 0))
                    tookOne = true
                    break
                }
                next += choices.count
                if tookOne { kept.append(Active(index: parent.index, attempt: parent.attempt + Self.candidatesPerPoint)) }
                if placed.points.count > ceiling { break }
            }
            active = kept + children
        }
        return Outcome(points: placed.points, reachedCeiling: placed.points.count > ceiling)
    }

    /// The next seed and its spacing: the first of the next `seedingTries` stream-0 draws that the region allows, that is not
    /// closer than `minSpacing` to a placed point and not closer than its own spacing to any. The field is asked in batches of
    /// `seedBatch` draws. `draws` counts every seed draw made so far, so no draw is ever used twice. `nil` when none has room.
    private func nextSeed(in box: (min: Vector2, max: Vector2), placed: Placed, draws: inout Int,
                          spacing: ([Vector2]) async throws -> [Double]) async throws -> (point: Vector2, radius: Double)? {
        let random = SeededRandom(seed: seed, stream: 0, purpose: .scatter)
        var tried = 0
        while tried < Self.seedingTries {
            try Task.checkCancellation()
            let batch = (0..<Self.seedBatch).compactMap { offset -> Vector2? in
                let draw = 2 * (draws + offset)
                let point = Vector2(box.min.x + (box.max.x - box.min.x) * random.unit(at: draw),
                                    box.min.y + (box.max.y - box.min.y) * random.unit(at: draw + 1))
                return region.allows(point, margin: margin) && placed.isClear(point, within: minSpacing) ? point : nil
            }
            draws += Self.seedBatch
            tried += Self.seedBatch
            guard !batch.isEmpty else { continue }
            let radii = try await spacing(batch)
            precondition(radii.count == batch.count, "the spacing closure must return one value per point")
            if let found = zip(batch, radii).first(where: { placed.isClear($0, within: $1) }) {
                return (found.0, found.1)
            }
        }
        return nil
    }

    /// The candidates round `parent` that the region allows and that are not closer than `minSpacing` to a placed point.
    private func candidates(of parent: Active, placed: Placed) -> [Vector2] {
        let random = SeededRandom(seed: seed, stream: parent.index + 1, purpose: .scatter)
        let centre = placed.points[parent.index]
        let radius = placed.radii[parent.index]
        return (0..<Self.candidatesPerPoint).compactMap { offset in
            let draw = 2 * (parent.attempt + offset)
            let distance = radius * (1 + 3 * random.unit(at: draw)).squareRoot()
            let angle = 2 * Double.pi * random.unit(at: draw + 1)
            let point = Vector2(centre.x + distance * cos(angle), centre.y + distance * sin(angle))
            guard region.allows(point, margin: margin), placed.isClear(point, within: minSpacing) else { return nil }
            return point
        }
    }

    /// A placed point that can still take candidates, and how many draws it has used.
    private struct Active {
        var index: Int
        var attempt: Int
    }

    private struct Cell: Hashable {
        var x: Int
        var y: Int
    }

    /// The points placed so far and a grid of them, `width` wide, for neighbour tests.
    private struct Placed {
        let origin: Vector2
        let width: Double
        private(set) var points: [Vector2] = []
        private(set) var radii: [Double] = []
        private var cells: [Cell: [Int]] = [:]

        init(origin: Vector2, width: Double) {
            self.origin = origin
            self.width = width
        }

        mutating func add(_ point: Vector2, radius: Double) {
            cells[cell(of: point), default: []].append(points.count)
            points.append(point)
            radii.append(radius)
        }

        /// True when no placed point is closer to `point` than `distance`.
        func isClear(_ point: Vector2, within distance: Double) -> Bool {
            let reach = Self.index((distance / width).rounded(.up))
            let centre = cell(of: point)
            for dx in -reach...reach {
                for dy in -reach...reach {
                    guard let neighbours = cells[Cell(x: centre.x + dx, y: centre.y + dy)] else { continue }
                    if neighbours.contains(where: { (points[$0] - point).length < distance }) { return false }
                }
            }
            return true
        }

        private func cell(of point: Vector2) -> Cell {
            Cell(x: Self.index((point.x - origin.x) / width), y: Self.index((point.y - origin.y) / width))
        }

        /// A grid index, held far inside `Int`'s range so a tiny spacing can't trap.
        private static func index(_ value: Double) -> Int {
            Int(Swift.max(Swift.min(value.rounded(.down), 1e15), -1e15))
        }
    }
}
```

- [ ] **Step 4: Run the scatter tests**

Run: `swift test --filter PoissonScatterTests 2>&1 | tail -20`
Expected: PASS, 11 tests.

- [ ] **Step 5: Lint and run the whole suite**

Run `swiftlint lint --strict` (zero violations) and the full `swift test` (background, to a log), judged by the rule in Global Constraints.
Expected: master + 16 tests (3,489).

- [ ] **Step 6: Commit**

```bash
git add Sources/CreatorNodes Tests/CreatorNodesTests
git commit -m "feat: Poisson-disk sampling for Field Scatter, and its random purpose (7b-3)"
```
### Task 3: The Field Scatter node

**Files:**
- Create: `Sources/CreatorNodes/Fields/Using/FieldScatterNode.swift`
- Create: `Sources/CreatorNodes/Patterns/Layouts/FaceRegion+Profile.swift`
- Modify: `Sources/CreatorNodes/Patterns/Layouts/FacePatternNode.swift` (`pickedFace` stops being `private`)
- Modify: `Sources/CreatorNodes/BuiltInNodes.swift`
- Modify: `Sources/CreatorGraph/InspectorControl.swift`, `Sources/CreatorEditor/InspectorControl+Socket.swift`, `Sources/CreatorEditor/InspectorBuilder.swift` (a `.note` control: a line of help under the inspector's last section)
- Modify: `Tests/CreatorNodesTests/CatalogTests.swift`, `Tests/CreatorNodesTests/OutputNodeTests.swift`, `Tests/CreatorEditorTests/FieldsLibraryTests.swift`
- Test: `Tests/CreatorNodesTests/FaceRegionProfileTests.swift`, `Tests/CreatorNodesTests/Fields/FieldScatterNodeTests.swift`, `Tests/CreatorNodesTests/Fields/FieldScatterFaceTests.swift`, `Tests/CreatorNodesTests/Fields/FieldScatterPickTests.swift`, `Tests/CreatorEditorTests/InspectorNoteTests.swift`

**Interfaces:**
- Consumes: `PoissonScatter` (Task 2), `FieldSampler.sample(_:at:kernel:cache:)`, `FaceRegion`, `FacePatternNode.pickedFace(of:context:)` and `FacePatternNode.Frame`, `LayoutChecks`, `PatternLimit`.
- Produces:
  - `FieldScatterNode` (`typeID` `"creator.fieldScatter"`, display name "Field Scatter", category `.fields`), inputs `solid` (optional), `profile` (optional), `field`, `minSpacing`, `maxSpacing`, `margin`, `seed`; output `placements` (a flat list of planes, in the order they were generated); the picked face is the existing `NodeSetting.face`.
  - `FieldScatterNode.ceiling` (8,000) and `FieldScatterNode.help` (the inspector's note, spec §4).
  - `FaceRegion.outline(of profile: Profile2D) -> FaceRegion`.
  - `InspectorControl.note(String)`, shown as an `InspectorRow.recipe(label: "Note", text:)` row.
  - `FacePatternNode.pickedFace(of:context:)` internal (was private).

**Behaviour (fields spec §3.3 and §4).** The region is either a picked flat face (`solid` wired and the `face` setting, read exactly as Face Pattern reads it: holes and the margin respected) or a `profile` on its plane (its holes respected too). The spacing at a point is `minSpacing + clamp(field, 0, 1) × (maxSpacing − minSpacing)`; the field is sampled at the candidates' world positions in batches (`PoissonScatter`'s one call per round) through the evaluator's distance cache. Placements face the region's normal with the plane's x axis. Refusals, all plain sentences: no region, two regions, `minSpacing` not above 0, `maxSpacing` below `minSpacing`, a negative or infinite margin, a field that is not a number somewhere, no room at all, and more than 2,000 points ("Field Scatter would place 2,431 points; patterns are limited to 2,000 instances."; when the search had to stop at `ceiling` it says "more than 8,000" instead of a count). A list wired into any single-valued input is refused before the node runs, in the layouts' words (`singleValuesRefusal`). Messages that Face Pattern words for itself ("Face Pattern works on flat faces for now.") are said with this node's name.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorNodesTests/FaceRegionProfileTests.swift`:

```swift
import CreatorGeometry
import Testing
@testable import CreatorNodes

/// A profile read as a region (`FaceRegion.outline(of:)`), the way Field Scatter reads one: outer loop and holes.
struct FaceRegionProfileTests {
    /// A 60 × 40 rectangle on the XY plane with a Ø20 hole (an arc over a full turn) at its centre.
    static let holed: Profile2D = {
        let corners = [Vector2(-30, -20), Vector2(30, -20), Vector2(30, 20), Vector2(-30, 20)]
        let outer = corners.indices.map { Segment2D.line(corners[$0], corners[($0 + 1) % 4]) }
        let hole = Segment2D.arc(center: .zero, radius: 10, start: Angle(radians: 0), end: Angle(radians: 2 * .pi))
        return Profile2D(plane: .xy, outer: outer, holes: [[hole]])
    }()

    @Test func theOuterLoopAndTheHoleBecomeTwoLoops() {
        let region = FaceRegion.outline(of: Self.holed)
        #expect(region.loops.count == 2 && region.loops[0].count == 4 && region.loops[1].count > 50)
        let box = region.bounds
        #expect(box?.min == Vector2(-30, -20) && box?.max == Vector2(30, 20))
    }

    @Test func theHoleIsOutsideTheRegionAndTheRingAroundItIsInside() {
        let region = FaceRegion.outline(of: Self.holed)
        #expect(!region.allows(.zero, margin: 0) && !region.allows(Vector2(9, 0), margin: 0))
        #expect(region.allows(Vector2(15, 0), margin: 2) && !region.allows(Vector2(11, 0), margin: 2), "2 mm clear of the hole's edge")
        #expect(!region.allows(Vector2(29, 0), margin: 2), "and of the outline")
    }

    @Test func aClockwiseArcIsChordedTheSameWay() {
        let arc = Segment2D.arc(center: .zero, radius: 5, start: Angle(radians: 2 * .pi), end: Angle(radians: 0))
        let region = FaceRegion.outline(of: Profile2D(plane: .xy, segments: [arc]))
        #expect(region.contains(Vector2(1, 1)) && !region.contains(Vector2(6, 0)))
    }
}
```

Create `Tests/CreatorNodesTests/Fields/FieldScatterNodeTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Field Scatter on a profile (fields spec §3.3): the region, the spacing from the field, determinism and the refusals.
struct FieldScatterNodeTests {
    /// A Rectangle on the XY plane wired into a Field Scatter's `profile`.
    struct Fixture {
        var h = Harness()
        let rectangle: Node
        let scatter: Node

        init(_ settings: [SocketName: ConstantValue] = [:], width: Double = 60, height: Double = 40) {
            rectangle = h.add(RectangleNode.self, ["width": .number(width), "height": .number(height), "plane": .plane(.xy)])
            scatter = h.add(FieldScatterNode.self, settings)
            h.wire(rectangle, "profile", to: scatter, "profile")
        }

        func run(kernel: any Kernel = FakeKernel()) async throws -> EvaluationReport {
            try await h.run([scatter], kernel: kernel)
        }

        func planes(_ report: EvaluationReport) throws -> [Plane] {
            try #require(report.value(scatter, "placements")?.planes, "\(String(describing: report.state(scatter)))")
        }

        func points(_ report: EvaluationReport) throws -> [Vector3] { try planes(report).map(\.origin) }
    }

    static func nearestPair(_ points: [Vector3]) -> Double {
        var nearest = Double.infinity
        for (index, a) in points.enumerated() {
            for b in points[(index + 1)...] { nearest = min(nearest, (a - b).length) }
        }
        return nearest
    }

    @Test func itMakesAFlatListOfPlacementsFacingTheProfilesNormal() async throws {
        let f = Fixture(["minSpacing": .number(6), "maxSpacing": .number(6), "margin": .number(3)])
        let report = try await f.run()
        let value = try #require(report.value(f.scatter, "placements"))
        #expect(value.isList && report.isOK(f.scatter))
        let planes = try f.planes(report)
        #expect(planes.count >= 20)
        #expect(planes.allSatisfy { $0.normal == .unitZ && $0.xAxis == .unitX && $0.origin.z == 0 })
        #expect(planes.allSatisfy { abs($0.origin.x) <= 27 + 1e-9 && abs($0.origin.y) <= 17 + 1e-9 }, "inside the 3 mm margin")
        #expect(Self.nearestPair(planes.map(\.origin)) >= 6 - 1e-9)
    }

    @Test func theSpacingIsTheMinimumPlusTheClampedFieldTimesTheRange() async throws {
        // A constant field of 0.5 is spacing 8 between 6 and 10; 5 clamps to 1 (spacing 10); -3 clamps to 0 (spacing 6).
        var spacings: [Double: [Vector3]] = [:]
        for (field, spacing) in [(0.5, 8.0), (5.0, 10.0), (-3.0, 6.0)] {
            let f = Fixture(["minSpacing": .number(6), "maxSpacing": .number(10), "field": .number(field), "margin": .number(0)])
            let points = try f.points(try await f.run())
            spacings[spacing] = points
            #expect(Self.nearestPair(points) >= spacing - 1e-9, "field \(field)")
        }
        let counts = [6.0, 8.0, 10.0].map { spacings[$0]?.count ?? 0 }
        #expect(counts[0] > counts[1] && counts[1] > counts[2], "a smaller spacing places more points: \(counts)")
    }

    @Test func theSameInputsGiveTheSamePointsAndAnotherSeedOthers() async throws {
        var f = Fixture(["minSpacing": .number(5), "maxSpacing": .number(8), "seed": .integer(3)])
        let first = try f.points(try await f.run())
        let again = try f.points(try await f.run())
        #expect(again == first)
        f.h.set(f.scatter, "seed", .integer(4))
        let other = try f.points(try await f.run())
        #expect(other != first)
    }

    @Test func pointsAreDenserWhereTheFieldIsLow() async throws {
        // A linear gradient along +X from x = -30 (0) to x = 30 (1): spacing 4 at the left edge, 10 at the right.
        var f = Fixture(["minSpacing": .number(4), "maxSpacing": .number(10), "margin": .number(0)], width: 60, height: 40)
        let gradient = f.h.add(LinearGradientNode.self, [
            "plane": .plane(Plane(origin: Vector3(-30, 0, 0), normal: .unitX, xAxis: .unitY)), "length": .number(60),
        ])
        f.h.wire(gradient, "field", to: f.scatter, "field")
        let points = try f.points(try await f.run())
        let left = points.filter { $0.x < 0 }.count
        let right = points.count - left
        #expect(left > 2 * right && right > 5, "left \(left), right \(right)")
        #expect(Self.nearestPair(points) >= 4 - 1e-9)
    }

    // MARK: refusals

    @Test func withNoRegionOrTwoItSaysSo() async throws {
        var f = Fixture()
        f.h.set(f.scatter, "minSpacing", .number(5))
        var bare = Harness()
        let lone = bare.add(FieldScatterNode.self)
        let lonely = try await bare.run([lone])
        #expect(lonely.error(lone) == FieldScatterNode.noRegion)
        let plate = f.h.box(60, 40, 6)
        f.h.wire(plate, "solid", to: f.scatter, "solid")
        let both = try await f.run()
        #expect(both.error(f.scatter) == FieldScatterNode.bothRegions)
    }

    @Test(arguments: [
        ("minSpacing", ConstantValue.number(0), "“minSpacing” must be greater than 0 mm."),
        ("minSpacing", .number(-2), "“minSpacing” must be greater than 0 mm."),
        ("margin", .number(-1), "“margin” must be 0 or more."),
    ])
    func aBadNumberIsRefusedInWords(_ socket: String, _ value: ConstantValue, _ message: String) async throws {
        let f = Fixture([SocketName(socket): value])
        let report = try await f.run()
        #expect(report.error(f.scatter) == message)
    }

    @Test func aMaximumBelowTheMinimumIsRefused() async throws {
        let f = Fixture(["minSpacing": .number(8), "maxSpacing": .number(5)])
        let report = try await f.run()
        #expect(report.error(f.scatter) == "“maxSpacing” can't be less than “minSpacing” (8 mm).")
    }

    @Test func aMarginThatEatsTheRegionLeavesNoRoom() async throws {
        let f = Fixture(["margin": .number(25)])
        let report = try await f.run()
        #expect(report.error(f.scatter) == FieldScatterNode.noRoom)
    }

    @Test func moreThanTwoThousandPointsSaysHowManyWouldHaveBeenPlaced() async throws {
        let f = Fixture(["minSpacing": .number(1.5), "maxSpacing": .number(1.5), "margin": .number(0)], width: 100, height: 100)
        let message = try #require(try await f.run().error(f.scatter))
        #expect(message.hasPrefix("Field Scatter would place ") && !message.contains("more than"), "\(message)")
        #expect(message.hasSuffix(" points; patterns are limited to 2,000 instances."), "\(message)")
    }

    @Test func farMoreThanThatSaysMoreThanTheCeiling() async throws {
        let f = Fixture(["minSpacing": .number(2), "maxSpacing": .number(2), "margin": .number(0)], width: 400, height: 400)
        let report = try await f.run()
        #expect(report.error(f.scatter)
            == "Field Scatter would place more than 8,000 points; patterns are limited to 2,000 instances.")
    }

    @Test func aListWiredIntoASingleValuedInputIsRefusedInTheLayoutsWords() async throws {
        var f = Fixture()
        let series = f.h.add(SeriesNode.self, ["count": .integer(3)])
        f.h.wire(series, "values", to: f.scatter, "minSpacing")
        let report = try await f.run()
        #expect(report.error(f.scatter) == "Field Scatter takes single values, not lists: wire one value into each input, "
            + "or pick one out of the list first with List Item.")
    }

    @Test func anOpenProfileIsRefused() async throws {
        var h = Harness()
        let points = h.add(GridPointsNode.self, ["countX": .integer(3), "countY": .integer(1), "spacingX": .number(10)])
        let line = h.add(PolylineNode.self, ["closed": .bool(false)])
        let scatter = h.add(FieldScatterNode.self)
        h.wire(points, "points", to: line, "points")
        h.wire(line, "profile", to: scatter, "profile")
        let message = try #require(try await h.run([scatter]).error(scatter))
        #expect(message == "“profile” isn't a closed outline.")
    }

    @Test func aFieldThatIsNotANumberSomewhereIsRefusedNotTreatedAsZero() async throws {
        let inputs = NodeInputs(item: 0, slots: [
            "profile": .item(.profile(.rectangle(width: 20, height: 20, plane: .xy))), "field": .item(.field(.constant(.nan))),
            "minSpacing": .item(.number(4)), "maxSpacing": .item(.number(8)), "margin": .item(.number(1)), "seed": .item(.integer(0)),
        ])
        let context = EvalContext(node: BuiltInNodes.registry.makeNode(FieldScatterNode.typeID), item: 0, parameters: [:])
        await #expect(throws: NodeError.invalidValue(FieldScatterNode.notANumber)) {
            try await FieldScatterNode.evaluate(inputs, kernel: FakeKernel(), context: context)
        }
    }

    // MARK: the node's place in the catalogue

    @Test func theNodeIsDeclaredAsASingleValuedFieldsLayoutWithAHelpNote() {
        #expect(FieldScatterNode.category == .fields && FieldScatterNode.outputs.map(\.type) == [.plane])
        #expect(FieldScatterNode.inputs.map(\.name) == ["solid", "profile", "field", "minSpacing", "maxSpacing", "margin", "seed"])
        #expect(FieldScatterNode.inputs.prefix(2).allSatisfy { $0.isOptional })
        #expect(FieldScatterNode.inspector.last?.controls == [.note(FieldScatterNode.help)])
        #expect(FieldScatterNode.help
            == "Points renumber when the field or region changes; a pick on a scattered instance may stop matching.")
    }
}
```

Create `Tests/CreatorNodesTests/Fields/FieldScatterFaceTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

/// Field Scatter on a picked flat face (fields spec §3.3): the same face pick, holes and margin as Face Pattern.
struct FieldScatterFaceTests {
    /// The 60 × 40 × 6 plate (top on z = 0) with an optional Ø20 hole, and a Field Scatter wired to its solid.
    struct Fixture {
        var plate = PatternPlate()
        let scatter: Node
        let part: Node

        init(drilled: Bool = false, _ settings: [SocketName: ConstantValue] = [:]) {
            scatter = plate.h.add(FieldScatterNode.self, settings)
            if drilled {
                let hole = plate.cylinder(diameter: 20, from: -7, to: 1)
                let cut = plate.h.add(BooleanNode.self, ["operation": .integer(1)])
                plate.h.wire(plate.plate, "solid", to: cut, "target")
                plate.h.wire(hole, "solid", to: cut, "tools")
                part = cut
            } else {
                part = plate.plate
            }
            plate.h.wire(part, "solid", to: scatter, "solid")
        }

        /// Picks the face of the part facing `normal`, then runs the scatter.
        mutating func pick(normal: Vector3 = .unitZ, kind: SurfaceKind = .plane, kernel: any Kernel = OCCTKernel()) async throws
            -> EvaluationReport {
            let solid = try onlySolid(try await plate.h.run([part], kernel: kernel), part)
            let face = try #require(solid.topology.faces.filter { face in
                face.kind == kind && (kind != .plane || face.normal.map { isClose($0, normal) } == true)
            }.max { $0.centroid.dot(normal) < $1.centroid.dot(normal) })
            plate.h.set(scatter, NodeSetting.face, .facePick(try #require(solid.topology.facePick(for: face.id))))
            return try await plate.h.run([scatter], kernel: kernel)
        }
    }

    @Test func pointsFillTheTopFaceKeepingTheMargin() async throws {
        var f = Fixture(["minSpacing": .number(6), "maxSpacing": .number(6), "margin": .number(3)])
        let report = try await f.pick()
        let planes = try #require(report.value(f.scatter, "placements")?.planes, "\(String(describing: report.state(f.scatter)))")
        #expect(planes.count >= 20)
        #expect(planes.allSatisfy { isClose($0.origin.z, 0) && isClose($0.normal, .unitZ) })
        #expect(planes.allSatisfy { abs($0.origin.x) <= 27 + 1e-6 && abs($0.origin.y) <= 17 + 1e-6 })
    }

    @Test func aHoleInTheFaceAndItsMarginStayEmpty() async throws {
        var f = Fixture(drilled: true, ["minSpacing": .number(4), "maxSpacing": .number(4), "margin": .number(2)])
        let report = try await f.pick()
        let planes = try #require(report.value(f.scatter, "placements")?.planes, "\(String(describing: report.state(f.scatter)))")
        #expect(planes.count > 15)
        #expect(planes.allSatisfy { Vector3($0.origin.x, $0.origin.y, 0).length >= 12 - 1e-6 }, "Ø20 hole plus the 2 mm margin")
    }

    @Test func aFaceThatIsNotFlatIsRefusedInThisNodesName() async throws {
        var f = Fixture(drilled: true)
        let report = try await f.pick(kind: .cylinder)
        #expect(report.error(f.scatter) == "Field Scatter works on flat faces for now.")
    }

    @Test func aSolidWithNoPickedFaceAsksForOne() async throws {
        let f = Fixture()
        let report = try await f.plate.h.run([f.scatter], kernel: FakeKernel())
        #expect(report.error(f.scatter) == "Pick a face for this pattern to fill.")
    }

    @Test func theResultIsTheSameOnASecondRun() async throws {
        var f = Fixture(["minSpacing": .number(5), "maxSpacing": .number(9)])
        let first = try #require(try await f.pick().value(f.scatter, "placements")?.planes)
        let second = try #require(try await f.plate.h.run([f.scatter], kernel: OCCTKernel()).value(f.scatter, "placements")?.planes)
        #expect(first == second && !first.isEmpty)
    }
}
```

Create `Tests/CreatorNodesTests/Fields/FieldScatterPickTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

/// Fields spec D7 and §8 (Paths): a pick on a scattered instance follows its number, and when the field, region or seed
/// renumbers the points so that the number no longer exists, it warns "Instance {n} no longer exists".
struct FieldScatterPickTests {
    /// A 60 × 40 profile at z = 0, scattered at spacing 6, Ø3 holes through the plate at the points, and an Edges by Tag.
    struct Fixture {
        var plate = PatternPlate()
        let scatter: Node, holes: Node, rule: Node

        init() {
            let region = plate.h.add(RectangleNode.self, ["width": .number(60), "height": .number(40), "plane": .plane(.xy)])
            scatter = plate.h.add(FieldScatterNode.self, ["minSpacing": .number(6), "maxSpacing": .number(6), "margin": .number(3)])
            holes = plate.h.add(HolePatternNode.self, ["diameter": .number(3), "depth": .number(6)])
            rule = plate.h.add(EdgesByTagNode.self)
            plate.h.wire(region, "profile", to: scatter, "profile")
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            plate.h.wire(scatter, "placements", to: holes, "placements")
            plate.h.wire(holes, "solid", to: rule, "solid")
        }

        func bore(_ index: Int) -> TopoTag {
            TopoTag(node: NodeID.instanceScoped([holes.id, holes.id]), item: index, role: .side(segment: 1))
        }

        func rim(of index: Int, in solid: Solid) -> EdgeInfo? {
            let top = TopoTag(node: plate.plate.id, item: 0, role: .endCap)
            return solid.topology.edges.first { edge in
                guard edge.kind == .circle, !edge.isSeam, edge.faces.count == 2 else { return false }
                let sides = edge.faces.compactMap { solid.topology.face($0) }
                return sides.contains { $0.tags.contains(bore(index)) } && sides.contains { $0.tags.contains(top) }
            }
        }
    }

    @Test func aPickOnTheLastScatteredPointWarnsOnceFewerPointsExist() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        let report = try await f.plate.h.run([f.holes], kernel: kernel)
        let count = try #require(report.value(f.scatter, "placements")?.items.count)
        #expect(count > 20)
        let last = count - 1
        let solid = try onlySolid(report, f.holes)
        let edge = try #require(f.rim(of: last, in: solid))
        f.plate.h.set(f.rule, NodeSetting.picks, .edgePicks(solid.topology.picks(for: [edge.id])))
        let before = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(before.isOK(f.rule), "the pick resolves while its instance exists: \(String(describing: before.state(f.rule)))")

        f.plate.h.set(f.scatter, "minSpacing", .number(12))
        f.plate.h.set(f.scatter, "maxSpacing", .number(12))
        let after = try await f.plate.h.run([f.rule], kernel: kernel)
        let fewer = try #require(after.value(f.scatter, "placements")?.items.count)
        #expect(fewer < count)
        #expect(after.warning(f.rule) == "Instance {\(last)} no longer exists, so the edge picked on it isn't selected.")
    }
}
```

Create `Tests/CreatorEditorTests/InspectorNoteTests.swift`:

```swift
import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorEditor

/// A node's `.note` control (fields spec §4: Field Scatter's help) is a read-only line of text in the inspector.
@MainActor
struct InspectorNoteTests {
    @Test func aNoteControlHasNoSocketAndBecomesARecipeRow() {
        #expect(InspectorControl.note("Hello").socket == nil)
        let node = BuiltInNodes.registry.makeNode(FieldScatterNode.typeID)
        let page = InspectorBuilder.page(graph: Graph(nodes: [node.id: node], links: []), selection: [node.id],
                                         registry: BuiltInNodes.registry, results: [:])
        let note = page.sections.first { $0.title == "Note" }
        #expect(note?.rows == [.recipe(label: "Note", text: FieldScatterNode.help)])
    }

    @Test func fieldScatterShowsItsSpacingDensityAndSeedControls() {
        let node = BuiltInNodes.registry.makeNode(FieldScatterNode.typeID)
        let page = InspectorBuilder.page(graph: Graph(nodes: [node.id: node], links: []), selection: [node.id],
                                         registry: BuiltInNodes.registry, results: [:])
        #expect(page.sections.map(\.title) == ["Spacing", "Density", "Random", "Note"])
        #expect(page.header?.title == "Field Scatter")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: FAIL to compile, "cannot find 'FieldScatterNode' in scope" and "type 'InspectorControl' has no member 'note'".

- [ ] **Step 3: Write the node and the note control**

Create `Sources/CreatorNodes/Patterns/Layouts/FaceRegion+Profile.swift`:

```swift
import CreatorGeometry
import Foundation

extension FaceRegion {
    /// The outline of a profile in its plane's own 2D coordinates: its outer loop and each hole as closed polylines, arcs cut
    /// into chords no more than `chordTolerance` from the arc, so Field Scatter reads a profile as it reads a face.
    static func outline(of profile: Profile2D) -> FaceRegion {
        FaceRegion(loops: profile.loops.map { loop in loop.flatMap { points(of: $0) } })
    }

    /// The points that stand for `segment`, from its start up to but not including its end: just the start for a line, chords
    /// for an arc (run from its `start` to its `end` angle, clockwise when `end < start`).
    private static func points(of segment: Segment2D) -> [Vector2] {
        switch segment {
        case .line(let start, _):
            return [start]
        case .arc(let center, let radius, let start, let end):
            let sweep = end.radians - start.radians
            let step = chordTolerance < radius ? 2 * acos(1 - chordTolerance / radius) : .pi
            let chords = min(max(Int((abs(sweep) / step).rounded(.up)), 1), 720)
            return (0..<chords).map { index in
                let angle = start.radians + sweep * Double(index) / Double(chords)
                return center + Vector2(cos(angle), sin(angle)) * radius
            }
        }
    }
}
```

Edit `Sources/CreatorNodes/Patterns/Layouts/FacePatternNode.swift`:

```swift-old
    private static func pickedFace(of solid: Solid, context: EvalContext) throws -> (FaceInfo, [String]) {
```

```swift-new
    static func pickedFace(of solid: Solid, context: EvalContext) throws -> (FaceInfo, [String]) {
```

Create `Sources/CreatorNodes/Fields/Using/FieldScatterNode.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Scatters points over a flat region where a field says (fields spec §3.3): variable-radius Poisson-disk sampling
/// (`PoissonScatter`), the spacing at a point `minSpacing + clamp(field, 0, 1) × (maxSpacing − minSpacing)`, so no two points
/// are ever closer than `minSpacing`, and a field of 0 gives the densest scatter and 1 the sparsest. A layout node, in 7a's
/// rules: a list in any single-valued input is refused before it runs (`singleValuesRefusal`), and more than 2,000 points
/// refuses (`PatternLimit`).
///
/// The region is a picked flat face of `solid` (the `face` setting, read as Face Pattern reads it: holes and the margin
/// respected) or a `profile` on its plane (its holes respected too). The output is one flat list of placements on the region's
/// plane, facing its normal with the plane's x axis, numbered in the order they were generated. Changing the field, the
/// region or the seed renumbers them (decision D7): a pick on a scattered instance then warns "Instance {n} no longer
/// exists" by the existing rule, and the inspector's note says so.
public enum FieldScatterNode: NodeDefinition {
    public static let typeID = "creator.fieldScatter"
    public static let displayName = "Field Scatter"
    public static let category = NodeCategory.fields
    public static let inputs = [
        SocketSpec("solid", .solid, optional: true),
        SocketSpec("profile", .profile, optional: true),
        SocketSpec("field", .field, defaultValue: .number(0.5)),
        SocketSpec("minSpacing", .number, defaultValue: .number(6), unit: .millimetres, range: 0.5...200),
        SocketSpec("maxSpacing", .number, defaultValue: .number(12), unit: .millimetres, range: 0.5...200),
        SocketSpec("margin", .number, defaultValue: .number(3), unit: .millimetres, range: 0...50),
        SocketSpec("seed", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static var singleValuesRefusal: String? { LayoutChecks.singleValues(displayName) }

    /// The inspector's note (fields spec §4).
    public static let help = "Points renumber when the field or region changes; a pick on a scattered instance may stop matching."
    public static let inspector = [
        InspectorSection(title: "Spacing", controls: [.slider("minSpacing"), .slider("maxSpacing"), .slider("margin")]),
        InspectorSection(title: "Density", controls: [.number("field")]),
        InspectorSection(title: "Random", controls: [.integer("seed")]),
        InspectorSection(title: "Note", controls: [.note(help)]),
    ]

    /// The most points the search makes before it stops and says "more than": four times the limit, so the refusal usually
    /// names the real count and a typo ("spacing 0.01") still answers at once.
    public static let ceiling = 4 * PatternLimit.maximumInstances

    public static let noRegion = "Field Scatter needs a region: wire a solid and pick one of its flat faces, or wire a profile."
    public static let bothRegions = "Wire either a solid with a picked face or a profile, not both."
    public static let noRoom = "Field Scatter found no room for a point: the region is smaller than its margin, "
        + "or the margin leaves none of it."
    public static let notANumber = "Field Scatter's field has no value at some points of the region: check the field's inputs."

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let minSpacing = try inputs.number("minSpacing")
        guard minSpacing.isFinite, minSpacing > 0 else { throw NodeError.invalidValue("“minSpacing” must be greater than 0 mm.") }
        let maxSpacing = try inputs.number("maxSpacing")
        guard maxSpacing.isFinite, maxSpacing >= minSpacing else {
            throw NodeError.invalidValue("“maxSpacing” can't be less than “minSpacing” (\(minSpacing.display) mm).")
        }
        let margin = try LayoutChecks.number(try inputs.number("margin"), "margin")
        let seed = try inputs.integer("seed")
        let field = try inputs.field("field")
        let (region, surface, warnings) = try self.region(inputs, context: context)

        let outcome = try await PoissonScatter(region: region, margin: margin, minSpacing: minSpacing, maxSpacing: maxSpacing,
                                               seed: seed, ceiling: ceiling).scatter { local in
            let values = try await FieldSampler.sample(field, at: local.map(surface.point), kernel: kernel,
                                                       cache: context.fieldDistances)
            guard values.allSatisfy(\.isFinite) else { throw NodeError.invalidValue(notANumber) }
            return values.map { minSpacing + min(max($0, 0), 1) * (maxSpacing - minSpacing) }
        }
        if outcome.points.count > PatternLimit.maximumInstances {
            let count = outcome.reachedCeiling ? "more than \(ceiling.display)" : outcome.points.count.display
            throw NodeError.invalidValue("Field Scatter would place \(count) points; patterns are limited to "
                + "\(PatternLimit.maximumInstances.display) instances.")
        }
        guard !outcome.points.isEmpty else { throw NodeError.invalidValue(noRoom) }
        let placements = outcome.points.map {
            LayoutChecks.placement(surface.point($0), normal: surface.normal, xAxis: surface.xAxis)
        }
        return NodeOutputs(trees: ["placements": .list(placements)], warnings: warnings)
    }

    /// A flat region's plane: where its 2D coordinates stand in space.
    private struct Surface {
        let origin: Vector3
        let normal: Vector3
        let xAxis: Vector3
        let yAxis: Vector3

        func point(_ local: Vector2) -> Vector3 { origin + xAxis * local.x + yAxis * local.y }
    }

    /// The region the inputs name, where it lies, and the warnings its face pick earns.
    private static func region(_ inputs: NodeInputs, context: EvalContext) throws -> (FaceRegion, Surface, [String]) {
        let (hasSolid, hasProfile) = (inputs.has("solid"), inputs.has("profile"))
        guard hasSolid || hasProfile else { throw NodeError.invalidValue(noRegion) }
        guard !(hasSolid && hasProfile) else { throw NodeError.invalidValue(bothRegions) }
        if hasProfile {
            let profile = try inputs.profile("profile")
            guard profile.isClosed else { throw NodeError.invalidValue("“profile” isn't a closed outline.") }
            let plane = profile.plane
            return (.outline(of: profile), Surface(origin: plane.origin, normal: plane.normal, xAxis: plane.xAxis, yAxis: plane.yAxis), [])
        }
        do {
            let solid = try inputs.solid("solid")
            let (face, warnings) = try FacePatternNode.pickedFace(of: solid, context: context)
            let frame = try FacePatternNode.Frame(of: face)
            let region = try FaceRegion.outline(of: face, in: solid.topology, origin: frame.origin, xAxis: frame.xAxis,
                                                yAxis: frame.yAxis)
            return (region, Surface(origin: frame.origin, normal: frame.normal, xAxis: frame.xAxis, yAxis: frame.yAxis), warnings)
        } catch let error as NodeError {
            // Face Pattern words its refusals for itself ("Face Pattern works on flat faces for now."); say them as this node.
            guard case .invalidValue(let text) = error else { throw error }
            throw NodeError.invalidValue(text.replacing(FacePatternNode.displayName, with: displayName))
        }
    }
}
```

Edit `Sources/CreatorNodes/BuiltInNodes.swift`:

```swift-old
        FieldSmoothBlendNode.self, SampleFieldNode.self, CullByFieldNode.self,
```

```swift-new
        FieldSmoothBlendNode.self, SampleFieldNode.self, CullByFieldNode.self, FieldScatterNode.self,
```

Edit `Sources/CreatorGraph/InspectorControl.swift`:

```swift-old
    case button(title: String, action: InspectorAction)
}
```

```swift-new
    case button(title: String, action: InspectorAction)
    /// A line of help under the node's controls, shown read-only (Field Scatter's note on renumbering). It edits nothing.
    case note(String)
}
```

Edit `Sources/CreatorEditor/InspectorControl+Socket.swift`:

```swift-old
        case .button:
            nil
```

```swift-new
        case .button, .note:
            nil
```

Edit `Sources/CreatorEditor/InspectorBuilder.swift`:

```swift-old
            if case .button(let title, let action) = control { return .button(title: title, action: action) }
            return .readOnly(label: "", text: "")
```

```swift-new
            if case .button(let title, let action) = control { return .button(title: title, action: action) }
            if case .note(let text) = control { return .recipe(label: "Note", text: text) }
            return .readOnly(label: "", text: "")
```

Edit `Tests/CreatorNodesTests/CatalogTests.swift`:

```swift-old
        case .button:
            nil
        }
    }
```

```swift-new
        case .button, .note:
            nil
        }
    }
```

Edit `Tests/CreatorNodesTests/CatalogTests.swift`:

```swift-old
        case .parameterPicker, .text, .button: []
```

```swift-new
        case .parameterPicker, .text, .button, .note: []
```

Edit `Tests/CreatorNodesTests/OutputNodeTests.swift`:

```swift-old
        #expect(BuiltInNodes.all.count == 64)
```

```swift-new
        #expect(BuiltInNodes.all.count == 65)
```

Edit `Tests/CreatorNodesTests/OutputNodeTests.swift`:

```swift-old
.lists: 7, .fields: 12, .output: 1,
```

```swift-new
.lists: 7, .fields: 13, .output: 1,
```

Edit `Tests/CreatorEditorTests/FieldsLibraryTests.swift`:

```swift-old
            "Sample Field", "Cull by Field",
        ])
```

```swift-new
            "Sample Field", "Cull by Field", "Field Scatter",
        ])
```

Edit `Tests/CreatorEditorTests/FieldsLibraryTests.swift`:

```swift-old
    @Test func everyFieldNodeMakesAFieldExceptTheTwoThatUseOne() {
        let users = ["Sample Field", "Cull by Field"]
```

```swift-new
    @Test func everyFieldNodeMakesAFieldExceptTheThreeThatUseOne() {
        let users = ["Sample Field", "Cull by Field", "Field Scatter"]
```

- [ ] **Step 4: Run the new tests**

Run: `swift test --filter 'FieldScatter|InspectorNoteTests|FieldsLibraryTests|OutputNodeTests|CatalogTests' 2>&1 | grep -E "recorded|failed|Test run" | head -20`
Expected: PASS.

- [ ] **Step 5: Lint and run the whole suite**

Run `swiftlint lint --strict` (zero violations) and the full `swift test` (background, to a log), judged by the rule in Global Constraints.
Expected: master + 41 tests (3,514).

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat: Field Scatter, a layout node scattering points where a field says (7b-3)"
```
### Task 4: Field Scatter in the viewport: triads, and "Scatter on Face"

**Files:**
- Modify: `Sources/CreatorApp/LayoutPreview.swift`
- Create: `Sources/CreatorApp/LayoutPreview+Nearest.swift`
- Create: `Sources/CreatorApp/FaceLayout.swift`, `Sources/CreatorApp/AppModel+ScatterOnFace.swift`
- Modify: `Sources/CreatorApp/AppModel+PatternOnFace.swift`, `Sources/CreatorApp/AppModel+Viewport.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportMenuItem.swift`, `ViewportEvents.swift`, `ViewportModel+ContextMenu.swift`
- Modify: `Sources/CreatorGraph/UndoName.swift`
- Modify: `Tests/CreatorViewportTests/ContextMenuTests.swift`
- Test: `Tests/CreatorAppTests/ScatterPreviewTests.swift`, `Tests/CreatorAppTests/ScatterOnFaceTests.swift`

**Interfaces:**
- Consumes: `FieldScatterNode` (Task 3), `LayoutPreview`, `PlaneFromFaceNode.plane(of:)`, `AppModel.producer(of:)`.
- Produces:
  - `LayoutPreview.layoutTypes` contains `FieldScatterNode.typeID` (so `AppModel.applyPreview` evaluates a selected Field Scatter even before anything is wired to it, and `layoutOverlay` draws it).
  - `LayoutPreview.nearestDistance(between:) -> Double?` and `LayoutPreview.scatterTriadLength(of:)`.
  - `ViewportMenuItem.scatterOnFace(ViewportFaceRef)` (title "Scatter on Face"), `ViewportEvents.scatterOnFace`, `UndoName.scatterOnFace`, `AppModel.scatterOnFace(_:_:)`.
  - `FaceLayout` (`.pattern`, `.scatter`): what "Pattern on Face" and "Scatter on Face" differ by, so `AppModel.layoutOnFace(_:_:as:)` serves both.

**Why these.** Spec §6: Field Scatter shows its placements as 7a's axis-triad overlay. A triad is sized from the distance between neighbouring placements; for the layouts that is the step between consecutive placements, but a scatter's consecutive points are parent and child (6 to 12 mm apart) while some other pair may be at the minimum, so a scatter uses the true nearest-neighbour distance. The area a scatter fills is dashed on a face as Face Pattern's is. Spec §3.3 has a picked face as a region, and the face pick is only ever made by a face-menu item (Face Pattern's "Pattern on Face"), so Field Scatter gets the same item: **user decision 7**.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorAppTests/ScatterPreviewTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// A selected Field Scatter shows its points as axis triads (fields spec §6), sized by the nearest neighbours.
@MainActor
struct ScatterPreviewTests {
    func plane(_ x: Double, _ y: Double = 0) -> Plane { Plane(origin: Vector3(x, y, 0), normal: .unitZ, xAxis: .unitX) }

    @Test func theNearestPairIsFoundWhereverItIsInTheList() {
        let points = [Vector3(0, 0, 0), Vector3(50, 0, 0), Vector3(10, 30, 0), Vector3(51, 0.5, 0), Vector3(80, 80, 0)]
        let nearest = LayoutPreview.nearestDistance(between: points)
        #expect(nearest.map { abs($0 - (1 + 0.25).squareRoot()) < 1e-12 } == true)
        #expect(LayoutPreview.nearestDistance(between: []) == nil)
        #expect(LayoutPreview.nearestDistance(between: [.zero]) == nil)
        #expect(LayoutPreview.nearestDistance(between: [.zero, .zero]) == nil, "points in one place have no distance to size by")
    }

    @Test func aScattersTriadIsAShareOfItsNearestNeighbourNotOfTheStepBetweenConsecutivePoints() {
        // Consecutive points are 30, 20 and 50 apart, but the first and third are 10 apart.
        let planes = [plane(0), plane(30), plane(10, 0), plane(50, 30)]
        #expect(LayoutPreview.triadLength(of: planes) == 8, "0.4 of the closest consecutive step, 20")
        #expect(LayoutPreview.scatterTriadLength(of: planes) == 4, "0.4 of the closest pair, 10")
        #expect(LayoutPreview.scatterTriadLength(of: [plane(0)]) == LayoutPreview.singleTriad)
    }

    func scatterApp() async -> (AppModel, Node) {
        var builder = GraphBuilder()
        let region = builder.add(RectangleNode.self, ["width": .number(60), "height": .number(40)])
        let scatter = builder.add(FieldScatterNode.self, ["minSpacing": .number(8), "maxSpacing": .number(8), "margin": .number(2)])
        builder.wire(region, "profile", to: scatter, "profile")
        return (await makeApp(builder.graph), scatter)
    }

    @Test func aSelectedFieldScatterShowsATriadPerPointAndNoPart() async throws {
        let (app, scatter) = await scatterApp()
        #expect(app.viewport.overlay.isEmpty)
        app.editor.selection = [scatter.id]
        await app.settle()
        let points = app.document.results[scatter.id]?.outputs?["placements"]?.items.count ?? 0
        #expect(points > 15)
        #expect(app.viewport.overlay.lines.count == 3 * points)
        #expect(Set(app.viewport.overlay.lines.map(\.tint)) == [.axisX, .axisY, .axisZ])
        #expect(app.viewport.items.isEmpty, "no part: nothing to pick, frame or open a menu on")
    }

    @Test func theTriadsFollowAnEditAndGoWithTheSelection() async throws {
        let (app, scatter) = await scatterApp()
        app.editor.selection = [scatter.id]
        await app.settle()
        let before = app.viewport.overlay.lines.count
        try app.document.perform(.setInput(scatter.id, "minSpacing", .number(16)))
        try app.document.perform(.setInput(scatter.id, "maxSpacing", .number(16)))
        await app.settle()
        #expect(app.viewport.overlay.lines.count < before)
        app.editor.selection = []
        await app.settle()
        #expect(app.viewport.overlay.isEmpty)
    }

    @Test func aScatterThatFailsDrawsNothing() async throws {
        let (app, scatter) = await scatterApp()
        try app.document.perform(.setInput(scatter.id, "margin", .number(30)))
        app.editor.selection = [scatter.id]
        await app.settle()
        #expect(app.viewport.overlay.isEmpty)
    }
}
```

Create `Tests/CreatorAppTests/ScatterOnFaceTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// "Scatter on Face" (fields spec §3.3): the face menu inserts a Field Scatter holding the face's pick, wired from the part's
/// producer, as one undo step, exactly as "Pattern on Face" inserts a Face Pattern.
@MainActor
struct ScatterOnFaceTests {
    /// A box on xy: face 0 is its bottom, face 1 its top (flat, with normals); faces 2…5 are flat with none (FakeKernel).
    func open() async -> (app: AppModel, box: (rectangle: Node, extrude: Node, output: Node)) {
        var builder = GraphBuilder()
        let box = builder.box()
        let app = await makeApp(builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        await app.viewport.waitForMeshes()
        return (app, box)
    }

    func scatter(_ app: AppModel) -> Node? {
        app.document.graph.nodes.values.first { $0.typeID == FieldScatterNode.typeID }
    }

    func choose(_ app: AppModel, on face: FaceID) throws {
        app.viewport.pick = { _ in .face(solid: 0, face) }
        let items = app.viewport.contextMenuItems(at: ScreenPoint(700, 450))
        let item = try #require(items.first { if case .scatterOnFace = $0 { true } else { false } })
        app.viewport.choose(item)
    }

    @Test func theFaceMenuInsertsAFieldScatterWiredFromThePartAsOneNamedStep() async throws {
        let (app, box) = await open()
        try choose(app, on: FaceID(1))
        let node = try #require(scatter(app))
        let topology = app.viewport.items[0].solid.topology
        #expect(node.inputValues[NodeSetting.face] == .facePick(try #require(topology.facePick(for: FaceID(1)))))
        #expect(app.document.graph.links.contains(Link(from: Endpoint(node: box.extrude.id, socket: "solid"),
                                                       to: Endpoint(node: node.id, socket: "solid"))))
        #expect(app.editor.selection == [node.id])
        #expect(app.document.undoName == "Scatter on Face")
        app.document.undo()
        await app.settle()
        #expect(scatter(app) == nil && app.document.canUndo == false, "one step")
    }

    @Test func theItemFollowsPatternOnFaceInTheMenuAndNeedsAFlatFaceWithANormal() async throws {
        let (app, _) = await open()
        app.viewport.pick = { _ in .face(solid: 0, FaceID(1)) }
        let titles = app.viewport.contextMenuItems(at: ScreenPoint(700, 450)).map(\.title)
        #expect(titles.prefix(5) == ["Look At", "Select Edges of Face", "New Sketch on Face", "Pattern on Face", "Scatter on Face"])
        app.viewport.pick = { _ in .face(solid: 0, FaceID(2)) }
        #expect(!app.viewport.contextMenuItems(at: ScreenPoint(701, 450)).map(\.title).contains("Scatter on Face"))
    }

    @Test func aFaceThatIsNotFlatIsRefusedInWordsAndChangesNothing() async throws {
        let (app, _) = await open()
        let pick = try #require(app.viewport.items[0].solid.topology.facePick(for: FaceID(2)))
        app.scatterOnFace(ViewportFaceRef(solidIndex: 0, face: FaceID(2)), pick)
        guard case .problem(let problem)? = app.alert else {
            Issue.record("no alert")
            return
        }
        #expect(problem.title == "No scatter was made" && problem.message == "Only a flat face can hold a scatter.")
        #expect(scatter(app) == nil && app.document.canUndo == false)
    }

    @Test func aFaceOfASolidThatIsGoneChangesNothing() async throws {
        let (app, _) = await open()
        let pick = try #require(app.viewport.items[0].solid.topology.facePick(for: FaceID(1)))
        app.scatterOnFace(ViewportFaceRef(solidIndex: 9, face: FaceID(1)), pick)
        #expect(app.alert == nil && scatter(app) == nil && app.document.canUndo == false)
    }

    @Test func thePatternItemStillMakesAFacePattern() async throws {
        let (app, _) = await open()
        app.viewport.pick = { _ in .face(solid: 0, FaceID(1)) }
        let items = app.viewport.contextMenuItems(at: ScreenPoint(700, 450))
        let item = try #require(items.first { if case .patternOnFace = $0 { true } else { false } })
        app.viewport.choose(item)
        #expect(app.document.graph.nodes.values.contains { $0.typeID == FacePatternNode.typeID } && scatter(app) == nil)
        #expect(app.document.undoName == "Pattern on Face")
    }
}
```

Edit `Tests/CreatorViewportTests/ContextMenuTests.swift`:

```swift-old
        #expect(items.prefix(4).map(\.title) == ["Look At", "Select Edges of Face", "New Sketch on Face", "Pattern on Face"])
        #expect(items.contains(.newSketchOnFace(cap)) && items.contains(.patternOnFace(cap)))
```

```swift-new
        #expect(items.prefix(5).map(\.title)
            == ["Look At", "Select Edges of Face", "New Sketch on Face", "Pattern on Face", "Scatter on Face"])
        #expect(items.contains(.newSketchOnFace(cap)) && items.contains(.patternOnFace(cap)) && items.contains(.scatterOnFace(cap)))
```

Edit `Tests/CreatorViewportTests/ContextMenuTests.swift`:

```swift-old
    @Test func nothingUnderThePressMeansNoMenu() async throws {
```

```swift-new
    @Test func choosingScatterOnFaceReportsTheFaceAndItsRememberedPick() async throws {
        let solid = try await fakeBox()
        let model = await model(showing: [solid])
        var reported: [(face: ViewportFaceRef, pick: FacePick)] = []
        model.events.scatterOnFace = { reported.append(($0, $1)) }
        let ref = ViewportFaceRef(solidIndex: 0, face: FaceID(1))
        model.choose(.scatterOnFace(ref))
        #expect(reported.map(\.face) == [ref])
        #expect(reported.first?.pick == solid.topology.facePick(for: FaceID(1)))
        model.choose(.scatterOnFace(ViewportFaceRef(solidIndex: 5, face: FaceID(1))))
        #expect(reported.count == 1, "a face of a solid that is gone reports nothing")
    }

    @Test func nothingUnderThePressMeansNoMenu() async throws {
```

Edit `Tests/CreatorViewportTests/ContextMenuTests.swift` (the producing-node items now follow five items, not four):

```swift-old
        #expect(Array(titles.dropFirst(4)) == expected)
```

```swift-new
        #expect(Array(titles.dropFirst(5)) == expected)
```

Edit `Tests/CreatorViewportTests/ContextMenuTests.swift`:

```swift-old
        for item in model.contextMenuItems(at: ScreenPoint(300, 200)).dropFirst(4) { model.choose(item) }
```

```swift-new
        for item in model.contextMenuItems(at: ScreenPoint(300, 200)).dropFirst(5) { model.choose(item) }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: FAIL to compile, "type 'ViewportMenuItem' has no member 'scatterOnFace'", "type 'LayoutPreview' has no member 'nearestDistance'".

- [ ] **Step 3: The viewport's menu item and event**

Edit `Sources/CreatorViewport/Model/ViewportMenuItem.swift`:

```swift-old
    case patternOnFace(ViewportFaceRef)
```

```swift-new
    case patternOnFace(ViewportFaceRef)
    /// A Field Scatter on the face, wired from the solid (fields spec §3.3). Offered with the same faces as Pattern on Face.
    case scatterOnFace(ViewportFaceRef)
```

Edit `Sources/CreatorViewport/Model/ViewportMenuItem.swift`:

```swift-old
        case .patternOnFace: "Pattern on Face"
```

```swift-new
        case .patternOnFace: "Pattern on Face"
        case .scatterOnFace: "Scatter on Face"
```

Edit `Sources/CreatorViewport/Model/ViewportEvents.swift`:

```swift-old
    public var patternOnFace: @MainActor (ViewportFaceRef, FacePick) -> Void = { _, _ in }
```

```swift-new
    public var patternOnFace: @MainActor (ViewportFaceRef, FacePick) -> Void = { _, _ in }
    /// "Scatter on Face" (fields spec §3.3): the flat face and its remembered pick, which Field Scatter stores as Face Pattern does.
    public var scatterOnFace: @MainActor (ViewportFaceRef, FacePick) -> Void = { _, _ in }
```

Edit `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift`:

```swift-old
        // Plane from Face and Face Pattern take a flat face with a normal; another face would only make an error.
        if face.kind == .plane, face.normal != nil { menu += [.newSketchOnFace(ref), .patternOnFace(ref)] }
```

```swift-new
        // Plane from Face, Face Pattern and Field Scatter take a flat face with a normal; another face would only make an error.
        if face.kind == .plane, face.normal != nil { menu += [.newSketchOnFace(ref), .patternOnFace(ref), .scatterOnFace(ref)] }
```

Edit `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift`:

```swift-old
            events.patternOnFace(ref, pick)
        }
```

```swift-new
            events.patternOnFace(ref, pick)
        case .scatterOnFace(let ref):
            guard items.indices.contains(ref.solidIndex),
                  let pick = items[ref.solidIndex].solid.topology.facePick(for: ref.face) else { return }
            events.scatterOnFace(ref, pick)
        }
```

- [ ] **Step 4: The app's "Scatter on Face"**

Edit `Sources/CreatorGraph/UndoName.swift`:

```swift-old
    public static let patternOnFace = "Pattern on Face"
```

```swift-new
    public static let patternOnFace = "Pattern on Face"
    public static let scatterOnFace = "Scatter on Face"
```

Create `Sources/CreatorApp/FaceLayout.swift`:

```swift
import CreatorGraph
import CreatorNodes

/// What a face-menu item that inserts a layout node on a face differs by: the node, the undo step's name and the words of its
/// refusals. "Pattern on Face" makes a Face Pattern, "Scatter on Face" a Field Scatter; both wire the part's producer into the
/// node's `solid` and store the face's pick in its `face` setting.
struct FaceLayout {
    let typeID: String
    let undoName: String
    /// "pattern" or "scatter", as the alerts say it.
    let noun: String
    let insideGroup: String
    let notFlat: String

    var failureTitle: String { "No \(noun) was made" }

    static let pattern = FaceLayout(
        typeID: FacePatternNode.typeID, undoName: UndoName.patternOnFace, noun: "pattern",
        insideGroup: "Patterns on a face can't be made inside a group yet. Make it before grouping, or from the top level.",
        notFlat: "Only a flat face can hold a pattern.")

    static let scatter = FaceLayout(
        typeID: FieldScatterNode.typeID, undoName: UndoName.scatterOnFace, noun: "scatter",
        insideGroup: "A scatter on a face can't be made inside a group yet. Make it before grouping, or from the top level.",
        notFlat: "Only a flat face can hold a scatter.")
}
```

Replace `Sources/CreatorApp/AppModel+PatternOnFace.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport

extension AppModel {
    /// "Pattern on Face" (patterns spec §3): a Face Pattern holding the face's remembered pick.
    func patternOnFace(_ ref: ViewportFaceRef, _ pick: FacePick) {
        layoutOnFace(ref, pick, as: .pattern)
    }

    /// A layout node of type `layout` holding the face's remembered pick, wired from the node that made the face's solid and
    /// placed beside it, as one undo step, and selected so its placements show (`LayoutPreview`). A face that isn't flat is said
    /// in words, a face of a solid that is gone does nothing. Inside a group it is refused, as New Sketch on Face is: the pick
    /// would have to be written relative to the group (groups Errata (C2)).
    func layoutOnFace(_ ref: ViewportFaceRef, _ pick: FacePick, as layout: FaceLayout) {
        guard viewport.items.indices.contains(ref.solidIndex) else { return }
        guard !editor.isInsideGroup else {
            alert = .problem(AppProblem(layout.failureTitle, layout.insideGroup))
            return
        }
        let solid = viewport.items[ref.solidIndex].solid
        guard let face = solid.topology.face(ref.face), PlaneFromFaceNode.plane(of: face) != nil else {
            alert = .problem(AppProblem(layout.failureTitle, layout.notFlat))
            return
        }
        guard let source = producer(of: solid) else {
            alert = .problem(AppProblem(layout.failureTitle, "The node that made this solid can't be found."))
            return
        }
        let from = document.graph.nodes[source.node]?.position ?? .zero
        var node = registry.makeNode(layout.typeID, at: from + Vector2(240, 140))
        node.inputValues[NodeSetting.face] = .facePick(pick)
        let commands: [GraphCommand] = [
            .addNode(node), .connect(Link(from: source, to: Endpoint(node: node.id, socket: "solid"))),
        ]
        do {
            try document.perform(.batch(commands), name: layout.undoName)
        } catch {
            alert = .problem(AppProblem(layout.failureTitle, error.message))
            return
        }
        editor.selection = [node.id]
    }
}
```

Create `Sources/CreatorApp/AppModel+ScatterOnFace.swift`:

```swift
import CreatorGraph
import CreatorKernel
import CreatorViewport

extension AppModel {
    /// "Scatter on Face" (fields spec §3.3): a Field Scatter holding the face's remembered pick (`layoutOnFace`).
    func scatterOnFace(_ ref: ViewportFaceRef, _ pick: FacePick) {
        layoutOnFace(ref, pick, as: .scatter)
    }
}
```

Edit `Sources/CreatorApp/AppModel+Viewport.swift`:

```swift-old
        viewport.events.patternOnFace = { face, pick in events()?.patternOnFace(face, pick) }
```

```swift-new
        viewport.events.patternOnFace = { face, pick in events()?.patternOnFace(face, pick) }
        viewport.events.scatterOnFace = { face, pick in events()?.scatterOnFace(face, pick) }
```

- [ ] **Step 5: The triads**

Create `Sources/CreatorApp/LayoutPreview+Nearest.swift`:

```swift
import CreatorGeometry
import CreatorGraph

extension LayoutPreview {
    /// The distance between the two closest of `points` that are not in one place, or `nil` with fewer than two such points.
    /// Sorted along x and swept, so a few thousand scattered points cost a few thousand comparisons, not millions.
    static func nearestDistance(between points: [Vector3]) -> Double? {
        let sorted = points.sorted { $0.x < $1.x }
        var best = Double.infinity
        for (index, a) in sorted.enumerated() {
            for b in sorted[(index + 1)...] {
                if b.x - a.x >= best { break }
                let distance = (b - a).length
                if distance > 1e-9 { best = min(best, distance) }
            }
        }
        return best.isFinite ? best : nil
    }

    /// A scatter's triad length: `triadShare` of the distance between its two closest points (`singleTriad` for a lone point).
    /// A scatter's consecutive points are parent and child, so the step between them says nothing about its closest pair.
    static func scatterTriadLength(of planes: [Plane]) -> Double {
        guard let nearest = nearestDistance(between: planes.map(\.origin)) else { return singleTriad }
        return nearest * triadShare
    }
}
```

Edit `Sources/CreatorApp/LayoutPreview.swift`:

```swift-old
        LinearPatternNode.typeID, GridPatternNode.typeID, CircularPatternNode.typeID, CurvePatternNode.typeID, FacePatternNode.typeID,
    ]
```

```swift-new
        LinearPatternNode.typeID, GridPatternNode.typeID, CircularPatternNode.typeID, CurvePatternNode.typeID, FacePatternNode.typeID,
        FieldScatterNode.typeID,
    ]
```

Edit `Sources/CreatorApp/LayoutPreview.swift`:

```swift-old
        var overlay = ViewportOverlay(lines: triads(of: planes))
        if node.typeID == FacePatternNode.typeID {
            overlay.lines += clippedArea(of: node, graph: graph, results: results)
        }
        return overlay
    }

    /// An x, y and z line for each placement.
    static func triads(of planes: [Plane]) -> [OverlayLine] {
        let length = triadLength(of: planes)
        return planes.flatMap { plane in
```

```swift-new
        let isScatter = node.typeID == FieldScatterNode.typeID
        var overlay = ViewportOverlay(lines: triads(of: planes, length: isScatter ? scatterTriadLength(of: planes) : nil))
        if node.typeID == FacePatternNode.typeID || isScatter {
            overlay.lines += clippedArea(of: node, graph: graph, results: results)
        }
        return overlay
    }

    /// An x, y and z line for each placement, `length` long, or sized by the steps between placements.
    static func triads(of planes: [Plane], length: Double? = nil) -> [OverlayLine] {
        let length = length ?? triadLength(of: planes)
        return planes.flatMap { plane in
```

Edit `Sources/CreatorApp/LayoutPreview.swift`:

```swift-old
        let spec = FacePatternNode.inputs.first { $0.name == socket }
```

```swift-new
        let spec = (node.typeID == FieldScatterNode.typeID ? FieldScatterNode.inputs : FacePatternNode.inputs).first { $0.name == socket }
```

- [ ] **Step 6: Run the tests**

Run: `swift test --filter 'ScatterPreviewTests|ScatterOnFaceTests|ContextMenuTests|PatternOnFaceTests|LayoutPreviewTests|GroupViewportTests|UndoName' 2>&1 | grep -E "recorded|failed|Test run" | head`
Expected: PASS.

- [ ] **Step 7: Lint and run the whole suite**

Run `swiftlint lint --strict` (zero violations) and the full `swift test` (background, to a log), judged by the rule in Global Constraints.
Expected: master + 52 tests (3,525).

- [ ] **Step 8: Commit**

```bash
git add Sources Tests
git commit -m "feat: Field Scatter shows triads and Scatter on Face inserts one (7b-3)"
```
### Task 5: The surface tint in the viewport

**Files:**
- Create: `Sources/CreatorViewport/Model/FieldRamp.swift`, `Sources/CreatorViewport/Render/FieldRampUniforms.swift`, `Sources/CreatorViewport/Render/ViewportRenderer+Field.swift`, `Sources/CreatorViewport/Render/GPUGeometry+Field.swift`, `Sources/CreatorViewport/Model/ViewportModel+Meshes.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportItem.swift`, `Sources/CreatorViewport/Render/FrameItem.swift`, `Sources/CreatorViewport/Model/ViewportModel+Frame.swift`
- Create: `Sources/CreatorViewport/Render/FieldShaders.swift` (the new MSL, appended to `ViewportShaders.source`: that enum is at SwiftLint's body-length limit)
- Modify: `Sources/CreatorViewport/Render/ViewportPipelines.swift`, `GPUMesh.swift`, `ViewportRenderer.swift`
- Test: `Tests/CreatorViewportTests/FieldRampTests.swift`, `Tests/CreatorViewportTests/FieldTintDataTests.swift`, `Tests/CreatorViewportTests/FieldTintRenderTests.swift`, `Tests/CreatorViewportTests/FieldTintModelTests.swift`

**Interfaces:**
- Consumes: `DisplayMesh`, `ViewportRenderer`, `GPUBuffers`, `TestFrames` and `RendererCacheTests.Rig` (test support).
- Produces (Tasks 6 to 9 rely on these exact names):
  - `public struct FieldRamp: Hashable, Sendable` with `low`, `mid`, `high` (`SIMD4<Float>`, gamma-space RGBA as `HexColor.rgba` gives), `lowValue`, `midValue`, `highValue` (`Float`), `init(low:mid:high:lowValue:midValue:highValue:)`, `init(low:mid:high:range:)` (mid in the middle of a `ClosedRange<Float>`) and `func color(at value: Float) -> SIMD4<Float>`.
  - `ViewportItem.fieldValues: [Float]?` (one per vertex of the item's `DisplayMesh`) and `ViewportItem.fieldRamp: FieldRamp?`, both defaulting to `nil` in `init`.
  - `ViewportModel.displayMesh(of solid: Solid) -> DisplayMesh?`: the tessellation the viewport holds for a solid of the scene shown or loading (the host needs its vertices to sample a field at them).
  - `FieldRampUniforms` (64 bytes) and `GPUGeometry.fieldCorners(_:values:ramp:) -> [Float]?` (one value per de-indexed corner, `nil` when `values.count != mesh.positions.count`).

**Spec §6, "Surface tint".** The part is coloured by the field sampled at its mesh vertices; `ViewportItem` carries `fieldValues` and a `FieldRamp`; the renderer adds one float vertex buffer and a ramp lookup in the shader; the Swift GPU structs mirror the MSL and `GPUDataTests`-style tests pin them; `CreatorViewport` knows nothing about fields. So: the mesh vertex buffer is unchanged (it is cached by mesh serial and a new tint must not re-upload it); a second buffer holds one `Float` per de-indexed corner, rebuilt only when the values change (`GPUMesh.fieldUploads` counts); a second pipeline (`field_mesh_vertex` / `field_mesh_fragment`) interpolates the value across the triangle and looks the colour up per pixel, shaded by the same light as the plain surface (`0.55 + 0.45 × lit`), with hover and selection blended in as before. A ghost is never tinted; values of the wrong count, or none, draw the plain surface; a non-finite value takes the ramp's middle. Edges are drawn over the tint as before, and the ID pass is untouched, so picking, hover and the face menu work on a tinted part. **Look: user decision 4** (a lit tint, not a flat one).

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorViewportTests/FieldRampTests.swift`:

```swift
import Testing
@testable import CreatorViewport

/// The ramp a field is drawn in (fields spec §6): three colours at three values, straight blends between, held beyond.
struct FieldRampTests {
    static let red = SIMD4<Float>(1, 0, 0, 1)
    static let green = SIMD4<Float>(0, 1, 0, 1)
    static let blue = SIMD4<Float>(0, 0, 1, 1)
    let ramp = FieldRamp(low: red, mid: green, high: blue, lowValue: -2, midValue: 0, highValue: 4)

    @Test func theStopsAreTheirColours() {
        #expect(ramp.color(at: -2) == Self.red && ramp.color(at: 0) == Self.green && ramp.color(at: 4) == Self.blue)
    }

    @Test func betweenTheStopsItBlendsInAStraightLine() {
        #expect(ramp.color(at: -1) == SIMD4<Float>(0.5, 0.5, 0, 1))
        #expect(ramp.color(at: 2) == SIMD4<Float>(0, 0.5, 0.5, 1))
    }

    @Test func beyondTheEndsItIsHeld() {
        #expect(ramp.color(at: -50) == Self.red && ramp.color(at: 50) == Self.blue)
    }

    @Test func aRangeInitialiserPutsTheMiddleStopInTheMiddle() {
        let centred = FieldRamp(low: Self.red, mid: Self.green, high: Self.blue, range: 2...10)
        #expect(centred.lowValue == 2 && centred.midValue == 6 && centred.highValue == 10)
        #expect(centred.color(at: 6) == Self.green)
    }

    @Test func stopsAtOneValueDoNotDivideByZero() {
        let flat = FieldRamp(low: Self.red, mid: Self.green, high: Self.blue, lowValue: 3, midValue: 3, highValue: 3)
        #expect(flat.color(at: 3) == Self.green && flat.color(at: 1) == Self.green && flat.color(at: 9) == Self.blue)
    }

    @Test func aValueThatIsNotANumberTakesTheMiddleColour() {
        #expect(ramp.color(at: .nan) == Self.green && ramp.color(at: .infinity) == Self.green)
    }
}
```

Create `Tests/CreatorViewportTests/FieldTintDataTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The tint's GPU data: the uniform's layout and one value per de-indexed corner, in the order `meshVertices` makes them.
struct FieldTintDataTests {
    let mesh = TestMeshes.box(BoundingBox(min: Vector3(-5, -10, 0), max: Vector3(5, 10, 30)))
    let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: -5...5)

    @Test func theRampUniformHasTheShaderLayout() {
        #expect(MemoryLayout<FieldRampUniforms>.stride == 64)
        #expect(MemoryLayout<FieldRampUniforms>.offset(of: \FieldRampUniforms.range) == 48)
        let uniforms = FieldRampUniforms(ramp)
        #expect(uniforms.low == ramp.low && uniforms.high == ramp.high)
        #expect(uniforms.range == SIMD4<Float>(-5, 0, 5, 0))
    }

    @Test func eachCornerCarriesItsVerticesValue() throws {
        let values = mesh.positions.map { Float($0.x) }
        let corners = try #require(GPUGeometry.fieldCorners(mesh, values: values, ramp: ramp))
        let vertices = GPUGeometry.meshVertices(mesh)
        #expect(corners.count == vertices.count && corners.count == mesh.indices.count)
        #expect(zip(corners, vertices).allSatisfy { $0 == $1.position.x })
    }

    @Test func aTriangleThatMeshVerticesSkipsIsSkippedHereToo() throws {
        var broken = mesh
        broken.indices[0] = 999
        let corners = try #require(GPUGeometry.fieldCorners(broken, values: broken.positions.map { Float($0.x) }, ramp: ramp))
        #expect(corners.count == GPUGeometry.meshVertices(broken).count && corners.count == mesh.indices.count - 3)
    }

    @Test func valuesOfTheWrongCountMakeNoBuffer() {
        #expect(GPUGeometry.fieldCorners(mesh, values: [], ramp: ramp) == nil)
        #expect(GPUGeometry.fieldCorners(mesh, values: [Float](repeating: 1, count: mesh.positions.count + 1), ramp: ramp) == nil)
    }

    @Test func aValueThatIsNotANumberBecomesTheRampsMiddle() throws {
        var values = mesh.positions.map { Float($0.x) }
        values[0] = .nan
        values[1] = .infinity
        let corners = try #require(GPUGeometry.fieldCorners(mesh, values: values, ramp: ramp))
        #expect(corners.allSatisfy { $0.isFinite })
        #expect(corners[0] == ramp.midValue, "the first corner is vertex 0")
    }
}
```

Create `Tests/CreatorViewportTests/FieldTintRenderTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import Metal
import Testing
@testable import CreatorViewport

/// Spec §8: "one headless render test that the tint changes pixels". `OffscreenRenderTests`' front view of a 10 × 20 × 30 box
/// (5 points per mm): its front face fills view x 75…125, y 25…175, and a vertex's x, from −5 to 5, is its field value.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct FieldTintRenderTests {
    static let bounds = BoundingBox(min: Vector3(-5, -10, 0), max: Vector3(5, 10, 30))
    static let mesh = TestMeshes.box(bounds)
    /// Red at x = −5, green at 0, blue at 5.
    static let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: -5...5)

    func frame(values: [Float]? = nil, isGhost: Bool = false) -> ViewportFrame {
        var frame = TestFrames.frame(mesh: Self.mesh, pose: OffscreenRenderTests.front, size: OffscreenRenderTests.size,
                                     bounds: Self.bounds)
        frame.items[0].isGhost = isGhost
        frame.items[0].fieldValues = values
        frame.items[0].fieldRamp = values == nil ? nil : Self.ramp
        return frame
    }

    var xValues: [Float] { Self.mesh.positions.map { Float($0.x) } }

    /// The colour at view point (`x`, `y`) of the 400 × 400 target (2 pixels per point), as red, green and blue.
    func color(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let at = (y * 2 * 400 + x * 2) * 4
        return [Int(bytes[at + 2]), Int(bytes[at + 1]), Int(bytes[at])]
    }

    @Test func theFrontFaceTakesTheRampLeftToRight() throws {
        let bytes = try RendererCacheTests.Rig().draw(frame(values: xValues))
        let left = color(bytes, 80, 100), middle = color(bytes, 100, 100), right = color(bytes, 120, 100)
        #expect(left[0] > left[1] + 40 && left[0] > left[2] + 60, "red towards x = −5: \(left)")
        #expect(middle[1] > middle[0] + 40 && middle[1] > middle[2] + 40, "green in the middle: \(middle)")
        #expect(right[2] > right[0] + 60 && right[2] > right[1] + 40, "blue towards x = 5: \(right)")
    }

    @Test func theTintChangesThePixelsOfThePlainSurface() throws {
        let rig = try RendererCacheTests.Rig()
        let plain = try rig.draw(frame())
        let tinted = try rig.draw(frame(values: xValues))
        let before = color(plain, 80, 100)
        #expect(abs(before[0] - before[2]) < 40, "the plain surface is a lavender grey: \(before)")
        #expect(plain != tinted)
        #expect(color(plain, 100, 190) == color(tinted, 100, 190), "off the part, the background is the same")
    }

    @Test func valuesOfTheWrongCountOrNoneDrawThePlainSurface() throws {
        let rig = try RendererCacheTests.Rig()
        let plain = try rig.draw(frame())
        #expect(try rig.draw(frame(values: [1, 2, 3])) == plain)
        #expect(try rig.draw(frame(values: [])) == plain)
    }

    @Test func aGhostIsNeverTinted() throws {
        let rig = try RendererCacheTests.Rig()
        #expect(try rig.draw(frame(values: xValues, isGhost: true)) == rig.draw(frame(isGhost: true)))
    }

    @Test func valuesThatAreNotNumbersDrawTheMiddleOfTheRamp() throws {
        let nothing = [Float](repeating: .nan, count: Self.mesh.positions.count)
        let bytes = try RendererCacheTests.Rig().draw(frame(values: nothing))
        let middle = color(bytes, 100, 100)
        #expect(middle[1] > middle[0] + 40 && middle[1] > middle[2] + 40, "green: \(middle)")
    }

    @Test func theValueBufferIsKeptUntilTheValuesChange() throws {
        let rig = try RendererCacheTests.Rig()
        _ = try rig.draw(frame(values: xValues))
        _ = try rig.draw(frame(values: xValues))
        #expect(rig.renderer.meshes[1]?.fieldUploads == 1, "the same values: one upload")
        _ = try rig.draw(frame(values: xValues.map { $0 * 0.5 }))
        #expect(rig.renderer.meshes[1]?.fieldUploads == 2)
        _ = try rig.draw(frame())
        #expect(rig.renderer.meshes[1]?.fieldUploads == 2, "a plain frame uploads nothing")
    }

    @Test func theIDPassStillSeesATintedPart() throws {
        var tinted = frame(values: xValues)
        tinted.items[0].fieldRamp = Self.ramp
        let device = try #require(MTLCreateSystemDefaultDevice())
        let picker = try ViewportPicker(renderer: try ViewportRenderer(device: device))
        #expect(picker.pick(at: ScreenPoint(100, 100), in: tinted) == .face(solid: 0, FaceID(2)), "the front face, as untinted")
    }
}
```

Create `Tests/CreatorViewportTests/FieldTintModelTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorViewport

/// The model carries an item's field values to the frame the renderer draws, and lends the host its meshes to sample.
@MainActor
struct FieldTintModelTests {
    let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: 0...1)

    @Test func anItemWithoutAFieldHasNone() async throws {
        let item = ViewportItem(solid: try await fakeBox())
        #expect(item.fieldValues == nil && item.fieldRamp == nil)
    }

    @Test func theValuesReachTheFrameAndTheHostCanReadTheMesh() async throws {
        let box = try await fakeBox()
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        #expect(model.displayMesh(of: box) == nil, "nothing is loaded before a scene is shown")
        let mesh = TestMeshes.box(box.bounds)
        let values = (0..<mesh.positions.count).map { Float($0) / 24 }
        model.show([ViewportItem(solid: box, fieldValues: values, fieldRamp: ramp)])
        await model.waitForMeshes()
        #expect(model.displayMesh(of: box)?.positions.count == mesh.positions.count)
        #expect(model.items[0].fieldValues == values && model.items[0].fieldRamp == ramp)
        let frame = model.frame(at: 0)
        #expect(frame.items[0].fieldValues == values && frame.items[0].fieldRamp == ramp)
    }

    @Test func aSceneWithoutValuesHasAFrameWithout() async throws {
        let box = try await fakeBox()
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.show([ViewportItem(solid: box)])
        await model.waitForMeshes()
        #expect(model.frame(at: 0).items[0].fieldValues == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: FAIL to compile, "cannot find 'FieldRamp' in scope", "extra argument 'fieldValues' in call".

- [ ] **Step 3: The ramp, the item's fields and the model's accessor**

Create `Sources/CreatorViewport/Model/FieldRamp.swift`:

```swift
/// The colours a field's value is drawn in (fields spec §6, D13): `low` at `lowValue`, `mid` at `midValue` and `high` at
/// `highValue`, blended in straight lines between them and held beyond the ends. The viewport knows nothing of fields: this is
/// numbers and colours only, the colours in the gamma-space RGBA the GPU takes (`HexColor.rgba`). The shader's `field_ramp`
/// does the same sum, and `FieldTintRenderTests` checks the two agree on screen.
public struct FieldRamp: Hashable, Sendable {
    public var low: SIMD4<Float>
    public var mid: SIMD4<Float>
    public var high: SIMD4<Float>
    public var lowValue: Float
    public var midValue: Float
    public var highValue: Float

    public init(low: SIMD4<Float>, mid: SIMD4<Float>, high: SIMD4<Float>, lowValue: Float, midValue: Float, highValue: Float) {
        self.low = low
        self.mid = mid
        self.high = high
        self.lowValue = lowValue
        self.midValue = midValue
        self.highValue = highValue
    }

    /// A ramp over `range` with its middle colour at the range's midpoint.
    public init(low: SIMD4<Float>, mid: SIMD4<Float>, high: SIMD4<Float>, range: ClosedRange<Float>) {
        self.init(low: low, mid: mid, high: high, lowValue: range.lowerBound, midValue: (range.lowerBound + range.upperBound) / 2,
                  highValue: range.upperBound)
    }

    /// The colour of `value`. A value that is not a number takes the middle colour; two stops at one value (a ramp over a
    /// range of nothing) take the further colour, never a division by zero.
    public func color(at value: Float) -> SIMD4<Float> {
        guard value.isFinite else { return mid }
        if value <= midValue {
            let span = midValue - lowValue
            let t = span > 0 ? min(max((value - lowValue) / span, 0), 1) : 1
            return low + (mid - low) * t
        }
        let span = highValue - midValue
        let t = span > 0 ? min(max((value - midValue) / span, 0), 1) : 1
        return mid + (high - mid) * t
    }
}
```

Replace `Sources/CreatorViewport/Model/ViewportItem.swift`:

```swift
import CreatorKernel

/// One solid the viewport shows (spec §6.3). The host builds these from the document:
/// - output solids, and last-good results drawn as ghosts while their node is in error (spec §4.4)
/// - the faces and edges the active selection rule picks, which glow pink
/// - guides: the edges a selected rule picks on a solid the scene doesn't show, drawn over the part (`isGuide`)
/// - a field's tint (fields spec §6): a value per mesh vertex and the ramp to draw them in
public struct ViewportItem: Sendable {
    public var solid: Solid
    public var isGhost: Bool
    public var selectedFaces: Set<FaceID>
    public var selectedEdges: Set<EdgeID>
    /// A guide is not part of the scene (spec §6.3, Errata (M6)): it carries a solid the host doesn't show, and only
    /// its `selectedEdges` are drawn, in the selection colour, over the shown scene. They glow where they lie on a
    /// shown part and float free where they don't. A guide's surfaces and edges are otherwise never drawn, picked,
    /// hovered or offered in the face menu, and it never widens `sceneBounds` or the point the camera orbits about.
    public var isGuide: Bool
    /// A number at each vertex of this solid's `DisplayMesh` (`ViewportModel.displayMesh(of:)`, the vertices in its order),
    /// drawn in `fieldRamp`'s colours across the surface. Values that are not one per vertex, or no ramp, draw the plain
    /// surface; a ghost is never tinted.
    public var fieldValues: [Float]?
    public var fieldRamp: FieldRamp?

    public init(solid: Solid, isGhost: Bool = false, selectedFaces: Set<FaceID> = [], selectedEdges: Set<EdgeID> = [],
                isGuide: Bool = false, fieldValues: [Float]? = nil, fieldRamp: FieldRamp? = nil) {
        self.solid = solid
        self.isGhost = isGhost
        self.selectedFaces = selectedFaces
        self.selectedEdges = selectedEdges
        self.isGuide = isGuide
        self.fieldValues = fieldValues
        self.fieldRamp = fieldRamp
    }
}
```

Create `Sources/CreatorViewport/Model/ViewportModel+Meshes.swift`:

```swift
import CreatorKernel

extension ViewportModel {
    /// The tessellation the viewport holds for `solid`, at `displayTolerance`: its vertices are what a host samples a field at
    /// for `ViewportItem.fieldValues`. It is there once a scene holding the solid has loaded (`waitForMeshes()`), and `nil`
    /// for a solid the viewport has not been shown.
    public func displayMesh(of solid: Solid) -> DisplayMesh? {
        cache.mesh(for: solid)?.mesh
    }
}
```

Edit `Sources/CreatorViewport/Render/FrameItem.swift`:

```swift-old
    /// Only the selected edges are drawn, over everything else (`ViewportItem.isGuide`).
    var isGuide = false
}
```

```swift-new
    /// Only the selected edges are drawn, over everything else (`ViewportItem.isGuide`).
    var isGuide = false
    /// The field tint (`ViewportItem.fieldValues`, `fieldRamp`).
    var fieldValues: [Float]?
    var fieldRamp: FieldRamp?
}
```

Edit `Sources/CreatorViewport/Model/ViewportModel+Frame.swift`:

```swift-old
                                        selectedFaces: item.selectedFaces, selectedEdges: item.selectedEdges,
                                        isGuide: item.isGuide))
```

```swift-new
                                        selectedFaces: item.selectedFaces, selectedEdges: item.selectedEdges,
                                        isGuide: item.isGuide, fieldValues: item.fieldValues, fieldRamp: item.fieldRamp))
```

- [ ] **Step 4: The GPU side**

Create `Sources/CreatorViewport/Render/FieldRampUniforms.swift`:

```swift
/// The field ramp for the tint's fragment shader: the three colours, and in `range` the three values (x low, y middle, z high;
/// w unused). Mirrors `FieldRampUniforms` in `FieldShaders` (stride pinned by `FieldTintDataTests`).
struct FieldRampUniforms {
    var low: SIMD4<Float>
    var mid: SIMD4<Float>
    var high: SIMD4<Float>
    var range: SIMD4<Float>

    init(_ ramp: FieldRamp) {
        low = ramp.low
        mid = ramp.mid
        high = ramp.high
        range = SIMD4(ramp.lowValue, ramp.midValue, ramp.highValue, 0)
    }
}
```

Create `Sources/CreatorViewport/Render/GPUGeometry+Field.swift`:

```swift
import CreatorKernel

extension GPUGeometry {
    /// One field value per de-indexed corner, in the order `meshVertices` makes the corners (the same triangles are skipped), so
    /// the tint's vertex shader reads `values[vertex_id]`. A value that is not a number becomes the ramp's middle. `nil` when
    /// `values` is not one per vertex of the mesh.
    static func fieldCorners(_ mesh: DisplayMesh, values: [Float], ramp: FieldRamp) -> [Float]? {
        guard values.count == mesh.positions.count else { return nil }
        let triangles = min(mesh.indices.count / 3, mesh.triangleFaces.count)
        var corners: [Float] = []
        corners.reserveCapacity(triangles * 3)
        for triangle in 0..<triangles {
            let vertices = (0..<3).map { Int(mesh.indices[3 * triangle + $0]) }
            guard vertices.allSatisfy({ $0 < mesh.positions.count && $0 < mesh.normals.count }) else { continue }
            for vertex in vertices {
                let value = values[vertex]
                corners.append(value.isFinite ? value : ramp.midValue)
            }
        }
        return corners
    }
}
```

Create `Sources/CreatorViewport/Render/FieldShaders.swift`:

```swift
/// The viewport's field-preview shaders (fields spec section 6), appended to `ViewportShaders.source` when the library is
/// compiled (`ViewportPipelines`), so they may use its `MeshVertex`, `FrameUniforms`, `DrawUniforms` and `ShadeUniforms`. The
/// structs here mirror the Swift ones in this folder (strides pinned by `FieldTintDataTests`).
enum FieldShaders {
    static let source = """

struct FieldRampUniforms { float4 low; float4 mid; float4 high; float4 range; };

// MARK: Field tint: the surface coloured by a value per corner

struct FieldOut {
    float4 position [[position]];
    float3 viewNormal;
    uint face [[flat]];
    float value;
};

vertex FieldOut field_mesh_vertex(uint vid [[vertex_id]],
                                  device const MeshVertex *vertices [[buffer(0)]],
                                  constant FrameUniforms &uniforms [[buffer(1)]],
                                  device const float *values [[buffer(2)]]) {
    MeshVertex v = vertices[vid];
    FieldOut out;
    out.position = uniforms.viewProjection * float4(v.position, 1.0);
    out.viewNormal = (uniforms.view * float4(v.normal, 0.0)).xyz;
    out.face = v.face;
    out.value = values[vid];
    return out;
}

// FieldRamp.color(at:) in Swift: low to mid up to the middle value, mid to high above it, held beyond the ends.
float3 field_ramp(constant FieldRampUniforms &ramp, float value) {
    if (value <= ramp.range.y) {
        float span = ramp.range.y - ramp.range.x;
        float t = span > 0.0 ? saturate((value - ramp.range.x) / span) : 1.0;
        return mix(ramp.low.rgb, ramp.mid.rgb, t);
    }
    float span = ramp.range.z - ramp.range.y;
    float t = span > 0.0 ? saturate((value - ramp.range.y) / span) : 1.0;
    return mix(ramp.mid.rgb, ramp.high.rgb, t);
}

fragment float4 field_mesh_fragment(FieldOut in [[stage_in]],
                                    constant DrawUniforms &draw [[buffer(0)]],
                                    device const uint *faceFlags [[buffer(1)]],
                                    constant ShadeUniforms &shade [[buffer(2)]],
                                    constant FieldRampUniforms &ramp [[buffer(3)]]) {
    float3 n = normalize(in.viewNormal);
    float3 key = normalize(float3(-0.4, 0.7, 0.6));
    float diffuse = saturate(dot(n, key));
    float rim = pow(1.0 - saturate(n.z), 2.0);
    float lit = saturate(0.15 + 0.75 * diffuse + 0.1 * n.y);
    float3 color = field_ramp(ramp, in.value) * (0.55 + 0.45 * lit) + rim * 0.06;
    uint flags = in.face < draw.faceCount ? faceFlags[in.face] : 0u;
    if ((flags & 2u) != 0u) {
        color = mix(color, shade.selection.rgb, 0.55);
    } else if ((flags & 1u) != 0u) {
        color = mix(color, shade.hover.rgb, 0.18);
    }
    return float4(saturate(color), 1.0);
}
"""
}
```

Edit `Sources/CreatorViewport/Render/ViewportPipelines.swift`:

```swift-old
        let library = try device.makeLibrary(source: ViewportShaders.source, options: nil)
```

```swift-new
        let library = try device.makeLibrary(source: ViewportShaders.source + FieldShaders.source, options: nil)
```

Edit `Sources/CreatorViewport/Render/ViewportPipelines.swift`:

```swift-old
    let mesh: any MTLRenderPipelineState
    let ghost: any MTLRenderPipelineState
```

```swift-new
    let mesh: any MTLRenderPipelineState
    /// The surface coloured by a field's values (`field_mesh_*`).
    let fieldMesh: any MTLRenderPipelineState
    let ghost: any MTLRenderPipelineState
```

Edit `Sources/CreatorViewport/Render/ViewportPipelines.swift`:

```swift-old
        mesh = try pipeline("mesh_vertex", "mesh_fragment", blended: false)
```

```swift-new
        mesh = try pipeline("mesh_vertex", "mesh_fragment", blended: false)
        fieldMesh = try pipeline("field_mesh_vertex", "field_mesh_fragment", blended: false)
```

Edit `Sources/CreatorViewport/Render/GPUMesh.swift`:

```swift-old
    private var flagBuffer: (hovered: FaceID?, selected: Set<FaceID>, buffer: any MTLBuffer)?
```

```swift-new
    private var flagBuffer: (hovered: FaceID?, selected: Set<FaceID>, buffer: any MTLBuffer)?
    /// The field values last uploaded for the tint, with the ramp middle that stood in for any that were not numbers.
    private var fieldBuffer: (values: [Float], middle: Float, buffer: any MTLBuffer)?
    /// Field value buffers made so far. Tests use it to tell "kept" from "rebuilt".
    private(set) var fieldUploads = 0
```

Edit `Sources/CreatorViewport/Render/GPUMesh.swift`:

```swift-old
    /// The face flags for a mesh too big for inline bytes, rebuilt only when the hover or selection changes.
```

```swift-new
    /// The tint's value buffer, one float per de-indexed corner, rebuilt only when the values change (comparing two arrays that
    /// share storage costs nothing). `nil` when the values are not one per vertex of `mesh`.
    func fieldValues(_ values: [Float], mesh: DisplayMesh, ramp: FieldRamp, device: any MTLDevice) -> (any MTLBuffer)? {
        if let cached = fieldBuffer, cached.middle == ramp.midValue, cached.values == values { return cached.buffer }
        guard let corners = GPUGeometry.fieldCorners(mesh, values: values, ramp: ramp), corners.count == vertexCount,
              let buffer = GPUBuffers.make(device, corners) else { return nil }
        fieldBuffer = (values, ramp.midValue, buffer)
        fieldUploads += 1
        return buffer
    }

    /// The face flags for a mesh too big for inline bytes, rebuilt only when the hover or selection changes.
```

Create `Sources/CreatorViewport/Render/ViewportRenderer+Field.swift`:

```swift
import Metal

extension ViewportRenderer {
    /// Binds what an opaque item's field tint needs (fields spec §6) and returns true: the field pipeline, its value buffer
    /// (one float per de-indexed corner, kept on the mesh until the values change) and the ramp. Returns false, binding
    /// nothing, when the item has no values or ramp, or the values are not one per vertex: the caller draws the plain surface.
    func bindFieldTint(of item: FrameItem, on gpu: GPUMesh, _ encoder: any MTLRenderCommandEncoder) -> Bool {
        guard let values = item.fieldValues, let ramp = item.fieldRamp,
              let buffer = gpu.fieldValues(values, mesh: item.mesh, ramp: ramp, device: device) else { return false }
        var uniforms = FieldRampUniforms(ramp)
        encoder.setRenderPipelineState(pipelines.fieldMesh)
        encoder.setVertexBuffer(buffer, offset: 0, index: 2)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FieldRampUniforms>.stride, index: 3)
        return true
    }
}
```

Edit `Sources/CreatorViewport/Render/ViewportRenderer.swift`:

```swift-old
        if ghosts {
            encoder.setRenderPipelineState(pipelines.ghostDepth)
            encoder.setDepthStencilState(pipelines.depthWrite)
            drawMeshes(items, ghost: true, encoder)
        }
        encoder.setRenderPipelineState(ghosts ? pipelines.ghost : pipelines.mesh)
        encoder.setDepthStencilState(ghosts ? pipelines.depthTest : pipelines.depthWrite)
        drawMeshes(items, ghost: ghosts, encoder)
    }

    private func drawMeshes(_ items: [FrameItem], ghost: Bool, _ encoder: any MTLRenderCommandEncoder) {
        for item in items {
            guard let gpu = meshes[item.meshSerial], let vertices = gpu.vertexBuffer else { continue }
            var draw = DrawUniforms(pickBase: 0, ghost: ghost ? 1 : 0, faceCount: UInt32(gpu.faceCount), padding: 0)
            encoder.setVertexBuffer(vertices, offset: 0, index: 0)
```

```swift-new
        if ghosts {
            encoder.setDepthStencilState(pipelines.depthWrite)
            drawMeshes(items, ghost: true, pipeline: pipelines.ghostDepth, encoder)
        }
        encoder.setDepthStencilState(ghosts ? pipelines.depthTest : pipelines.depthWrite)
        drawMeshes(items, ghost: ghosts, pipeline: ghosts ? pipelines.ghost : pipelines.mesh, encoder)
    }

    /// Draws each item with `pipeline`, or with the field pipeline when it is an opaque item with a tint to show (fields spec §6).
    private func drawMeshes(_ items: [FrameItem], ghost: Bool, pipeline: any MTLRenderPipelineState,
                            _ encoder: any MTLRenderCommandEncoder) {
        for item in items {
            guard let gpu = meshes[item.meshSerial], let vertices = gpu.vertexBuffer else { continue }
            var draw = DrawUniforms(pickBase: 0, ghost: ghost ? 1 : 0, faceCount: UInt32(gpu.faceCount), padding: 0)
            if ghost || !bindFieldTint(of: item, on: gpu, encoder) { encoder.setRenderPipelineState(pipeline) }
            encoder.setVertexBuffer(vertices, offset: 0, index: 0)
```

- [ ] **Step 5: Run the viewport tests**

Run: `swift test --filter 'FieldRampTests|FieldTintDataTests|FieldTintRenderTests|FieldTintModelTests|OffscreenRenderTests|GuideRenderTests|RendererCacheTests|GPUDataTests|ViewportModelTests' 2>&1 | grep -E "recorded|failed|Test run" | head`
Expected: PASS (the render suites need a Metal device).

- [ ] **Step 6: Lint and run the whole suite**

Run `swiftlint lint --strict` (zero violations) and the full `swift test` (background, to a log), judged by the rule in Global Constraints.
Expected: master + 73 tests (3,546).

- [ ] **Step 7: Commit**

```bash
git add Sources/CreatorViewport Tests/CreatorViewportTests
git commit -m "feat: the viewport can tint a part by a value per vertex (7b-3)"
```
### Task 6: The slice plane in the viewport

**Files:**
- Create: `Sources/CreatorViewport/Model/ViewportSlice.swift`, `Sources/CreatorViewport/Render/SliceUniforms.swift`, `Sources/CreatorViewport/Render/SliceTextures.swift`, `Sources/CreatorViewport/Render/ViewportRenderer+Slice.swift`
- Modify: `Sources/CreatorViewport/Render/FieldShaders.swift`, `ViewportPipelines.swift`, `ViewportFrame.swift`, `ViewportRenderer.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportModel.swift`, `ViewportModel+Frame.swift`, `ViewportRenderKey.swift`
- Test: `Tests/CreatorViewportTests/ViewportSliceTests.swift`, `Tests/CreatorViewportTests/ViewportSliceRenderTests.swift`

**Interfaces:**
- Consumes: `FieldRamp`, `FieldRampUniforms`, `FieldShaders` (Task 5), `RendererCacheTests.Rig`, `TestFrames`.
- Produces (Tasks 8 to 10 rely on these exact names):
  - `public struct ViewportSlice: Hashable, Sendable`: `origin`, `xAxis`, `yAxis` (`Vector3`, unit), `halfWidth`, `halfHeight` (`Double`, mm), `columns`, `rows`, `values: [Float]` (row-major, `columns * rows`, row 0 at the `-yAxis` edge), `ramp: FieldRamp`, `opacity: Float` (0.85), `generation: Int`; `init(origin:xAxis:yAxis:halfWidth:halfHeight:columns:rows:values:ramp:opacity:generation:)`; `var isValid: Bool`; `func samplePoints() -> [Vector3]` (the world position of every grid sample, in `values`' order, for the host to sample the field at). **Equality and hashing ignore `values` and use `generation`** (the host bumps it each time the values change), so a 65,536-value slice is not hashed on every redraw.
  - `ViewportModel.slice: ViewportSlice?` and `ViewportModel.showSlice(_:)`; `ViewportRenderKey.slice`.
  - `ViewportRenderer.sliceTextures.uploads` (textures made so far).

**Spec §6, "Slice plane".** A translucent quad through the part showing the field on a grid (one texture); the quad's pose, its starting plane and the handle that moves it are the host's (Task 8). The viewport draws what it is given: a quad of `halfWidth × halfHeight` about `origin`, coloured per pixel from the grid by the ramp (bilinear between samples, read in the shader so no float-filtering support is assumed), at `opacity` over what is behind it, never in the ID pass (so it picks, hovers and frames nothing) and never in the scene's bounds. It is drawn **over** the part, ignoring depth, because it passes through the part: a depth test would hide the half of it that lies inside the solid, which is the half that shows the field there. **Look: user decision 5.**

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorViewportTests/ViewportSliceTests.swift`:

```swift
import CreatorGeometry
import Testing
@testable import CreatorViewport

/// The slice a host asks the viewport to draw (fields spec §6): a quad and a grid of values, equal by its `generation`.
@MainActor
struct ViewportSliceTests {
    static let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: 0...1)

    func slice(columns: Int = 2, rows: Int = 2, values: [Float]? = nil, generation: Int = 1,
               origin: Vector3 = Vector3(100, 0, 0)) -> ViewportSlice {
        ViewportSlice(origin: origin, xAxis: .unitX, yAxis: .unitZ, halfWidth: 10, halfHeight: 4, columns: columns, rows: rows,
                      values: values ?? [Float](repeating: 0.5, count: columns * rows), ramp: Self.ramp, generation: generation)
    }

    @Test func theGridSamplesAreTheCentresOfTheTexelsRowByRow() {
        let points = slice().samplePoints()
        #expect(points == [Vector3(95, 0, -2), Vector3(105, 0, -2), Vector3(95, 0, 2), Vector3(105, 0, 2)])
        #expect(slice(columns: 4, rows: 1).samplePoints().map(\.x) == [92.5, 97.5, 102.5, 107.5])
    }

    @Test func aSliceIsValidWhenItHoldsOneValuePerSample() {
        #expect(slice().isValid)
        #expect(!slice(values: [1, 2, 3]).isValid)
        #expect(!slice(columns: 0, rows: 0, values: []).isValid)
        #expect(slice().opacity == 0.85)
    }

    @Test func equalityAndHashingUseTheGenerationNotTheValues() {
        let a = slice(values: [0, 0, 0, 0], generation: 7)
        let b = slice(values: [1, 1, 1, 1], generation: 7)
        #expect(a == b && a.hashValue == b.hashValue, "same generation: the same slice, whatever the values")
        #expect(a != slice(values: [0, 0, 0, 0], generation: 8))
        #expect(a != slice(generation: 7, origin: Vector3(100, 1, 0)))
        var wider = a
        wider.halfWidth = 11
        #expect(wider != a)
    }
}
```

Create `Tests/CreatorViewportTests/ViewportSliceRenderTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import Metal
import Testing
@testable import CreatorViewport

/// The slice is drawn over the scene as a translucent quad, and the viewport model carries it (fields spec §6). The front view
/// of `OffscreenRenderTests` (orthographic, 5 points per mm, centred on (0, 0, 15)) puts a 20 × 20 mm quad in the XZ plane at
/// view x 50…150, y 50…150.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct ViewportSliceRenderTests {
    /// Red at the quad's left edge, green in the middle, blue at its right edge.
    static let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: -1...1)

    /// A 64 × 64 grid whose value grows from −1 on the left to 1 on the right.
    func slice(generation: Int = 1, flipped: Bool = false) -> ViewportSlice {
        let row = (0..<64).map { Float($0) / 63 * 2 - 1 }
        let values = (0..<64).flatMap { _ in flipped ? row.reversed() : row }
        return ViewportSlice(origin: Vector3(0, 0, 15), xAxis: .unitX, yAxis: .unitZ, halfWidth: 10, halfHeight: 10, columns: 64,
                             rows: 64, values: values, ramp: Self.ramp, generation: generation)
    }

    func frame(_ slice: ViewportSlice?) -> ViewportFrame {
        var frame = ViewportFrame(pose: OffscreenRenderTests.front, size: OffscreenRenderTests.size, sceneBounds: nil, items: [],
                                  shading: .shadedEdges, gridSpacing: 10, handles: [], cube: ViewCubeLayout(),
                                  hoveredCubeRegion: nil, triad: TriadLayout())
        frame.slice = slice
        return frame
    }

    func color(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [Int] {
        let at = (y * 2 * 400 + x * 2) * 4
        return [Int(bytes[at + 2]), Int(bytes[at + 1]), Int(bytes[at])]
    }

    @Test func theQuadShowsTheRampLeftToRightAndLeavesTheRestAlone() throws {
        let rig = try RendererCacheTests.Rig()
        let with = try rig.draw(frame(slice()))
        let without = try rig.draw(frame(nil))
        let left = color(with, 55, 100), middle = color(with, 100, 100), right = color(with, 145, 100)
        #expect(left[0] > 180 && left[1] < 90 && left[2] < 90, "red: \(left)")
        #expect(middle[1] > 180 && middle[0] < 90 && middle[2] < 90, "green: \(middle)")
        #expect(right[2] > 180 && right[0] < 90 && right[1] < 90, "blue: \(right)")
        #expect(color(with, 30, 100) == color(without, 30, 100) && color(with, 100, 30) == color(without, 100, 30), "outside the quad")
        #expect(color(with, 100, 100) != color(without, 100, 100))
    }

    @Test func theQuadIsTranslucentSoWhatIsBehindItShowsThrough() throws {
        let rig = try RendererCacheTests.Rig()
        let without = try rig.draw(frame(nil))
        let with = try rig.draw(frame(slice()))
        // The background is a dark gradient (#3a3d4e to #191a21); at 0.85 opacity a fraction of it remains, so the pure green
        // of the ramp's middle is dimmed in red and blue by the background rather than being exactly 0.
        let behind = color(without, 100, 100), over = color(with, 100, 100)
        #expect(over[0] > 0 && over[0] <= behind[0] / 2, "some of the background's red remains: \(over) over \(behind)")
    }

    @Test func theValuesAreDrawnWhicheverWayTheyRun() throws {
        let rig = try RendererCacheTests.Rig()
        let flipped = try rig.draw(frame(slice(generation: 2, flipped: true)))
        let left = color(flipped, 55, 100), right = color(flipped, 145, 100)
        #expect(left[2] > 180 && right[0] > 180, "blue on the left now, red on the right: \(left) \(right)")
    }

    @Test func theTextureIsKeptWhileTheGenerationDoesNotChange() throws {
        let rig = try RendererCacheTests.Rig()
        _ = try rig.draw(frame(slice(generation: 1)))
        _ = try rig.draw(frame(slice(generation: 1)))
        #expect(rig.renderer.sliceTextures.uploads == 1)
        _ = try rig.draw(frame(slice(generation: 2)))
        #expect(rig.renderer.sliceTextures.uploads == 2)
    }

    @Test func anInvalidSliceDrawsNothing() throws {
        let rig = try RendererCacheTests.Rig()
        var broken = slice()
        broken.values = [0, 1]
        #expect(try rig.draw(frame(broken)) == rig.draw(frame(nil)))
    }

    @Test func valuesThatAreNotNumbersDrawTheMiddleColour() throws {
        var nothing = slice()
        nothing.values = [Float](repeating: .nan, count: 64 * 64)
        let bytes = try RendererCacheTests.Rig().draw(frame(nothing))
        let middle = color(bytes, 55, 100)
        #expect(middle[1] > 180 && middle[0] < 90, "green everywhere: \(middle)")
    }

    @Test func theModelCarriesTheSliceIntoTheFrameAndTheRenderKey() {
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        #expect(model.slice == nil && model.frame(at: 0).slice == nil)
        let key = model.renderKey
        model.showSlice(slice(generation: 1))
        #expect(model.frame(at: 0).slice?.generation == 1)
        #expect(model.renderKey != key, "a new slice redraws")
        let shown = model.renderKey
        model.showSlice(slice(generation: 1))
        #expect(model.renderKey == shown, "an equal slice changes nothing")
        let before = model.slice?.values
        model.showSlice(slice(generation: 1, flipped: true))
        #expect(model.renderKey == shown && model.slice?.values == before, "same generation, same slice: a host bumps it")
        model.showSlice(slice(generation: 2))
        #expect(model.renderKey != shown, "new values redraw")
        model.showSlice(nil)
        #expect(model.slice == nil && model.renderKey == key)
    }

    @Test func aSliceIsNoPartOfTheScene() async throws {
        let model = ViewportModel(kernel: StubMeshKernel(), clock: ManualClock())
        model.viewSize = ViewportSize(width: 400, height: 300)
        model.showSlice(slice())
        #expect(model.sceneBounds == nil && model.items.isEmpty)
        #expect(MemoryLayout<SliceUniforms>.stride == 64)
        let uniforms = SliceUniforms(slice())
        #expect(uniforms.across == SIMD4<Float>(10, 0, 0, 0) && uniforms.up == SIMD4<Float>(0, 0, 10, 0))
        #expect(uniforms.origin == SIMD4<Float>(0, 0, 15, 1) && uniforms.style.x == 0.85)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: FAIL to compile, "cannot find 'ViewportSlice' in scope", "value of type 'ViewportFrame' has no member 'slice'".

- [ ] **Step 3: The slice value, the model and the frame**

Create `Sources/CreatorViewport/Model/ViewportSlice.swift`:

```swift
import CreatorGeometry

/// A translucent quad through the scene showing a field on a grid (fields spec §6, "Slice plane"). The host makes one and the
/// viewport draws it: a quad of `halfWidth × halfHeight` millimetres about `origin` spanned by the unit vectors `xAxis` and
/// `yAxis`, coloured from `values` by `ramp`. `values` is one number per grid sample, row-major, `columns` to a row, row 0 at
/// the `-yAxis` edge and column 0 at the `-xAxis` edge; a sample stands for the centre of its texel (`samplePoints()`).
///
/// A grid can be 65,536 numbers, so a slice is equal to another when everything but `values` is and their `generation`s are:
/// the host bumps `generation` each time it changes `values`, and neither `ViewportModel` nor the render key ever compares or
/// hashes the numbers themselves.
public struct ViewportSlice: Hashable, Sendable {
    public var origin: Vector3
    public var xAxis: Vector3
    public var yAxis: Vector3
    public var halfWidth: Double
    public var halfHeight: Double
    public var columns: Int
    public var rows: Int
    public var values: [Float]
    public var ramp: FieldRamp
    /// How much of the quad's colour replaces what is behind it, 0…1.
    public var opacity: Float
    public var generation: Int

    public init(origin: Vector3, xAxis: Vector3, yAxis: Vector3, halfWidth: Double, halfHeight: Double, columns: Int, rows: Int,
                values: [Float], ramp: FieldRamp, opacity: Float = 0.85, generation: Int = 0) {
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
        self.columns = columns
        self.rows = rows
        self.values = values
        self.ramp = ramp
        self.opacity = opacity
        self.generation = generation
    }

    /// True when the grid has a sample to draw and `values` is one per sample.
    public var isValid: Bool { columns > 0 && rows > 0 && values.count == columns * rows }

    /// The world position of every grid sample, in `values`' order: the centre of each texel, so the field sampled there and
    /// drawn with a bilinear lookup lines up with the quad's corners.
    public func samplePoints() -> [Vector3] {
        guard columns > 0, rows > 0 else { return [] }
        return (0..<rows).flatMap { row -> [Vector3] in
            let up = (2 * (Double(row) + 0.5) / Double(rows) - 1) * halfHeight
            return (0..<columns).map { column in
                let across = (2 * (Double(column) + 0.5) / Double(columns) - 1) * halfWidth
                return origin + xAxis * across + yAxis * up
            }
        }
    }

    public static func == (lhs: ViewportSlice, rhs: ViewportSlice) -> Bool {
        lhs.generation == rhs.generation && lhs.origin == rhs.origin && lhs.xAxis == rhs.xAxis && lhs.yAxis == rhs.yAxis
            && lhs.halfWidth == rhs.halfWidth && lhs.halfHeight == rhs.halfHeight && lhs.columns == rhs.columns
            && lhs.rows == rhs.rows && lhs.ramp == rhs.ramp && lhs.opacity == rhs.opacity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(generation)
        hasher.combine(origin)
        hasher.combine(xAxis)
        hasher.combine(yAxis)
        hasher.combine(halfWidth)
        hasher.combine(halfHeight)
        hasher.combine(columns)
        hasher.combine(rows)
        hasher.combine(ramp)
        hasher.combine(opacity)
    }
}
```

Edit `Sources/CreatorViewport/Model/ViewportModel.swift`:

```swift-old
    public private(set) var overlay = ViewportOverlay()
    public internal(set) var hovered: PickTarget?
```

```swift-new
    public private(set) var overlay = ViewportOverlay()
    /// The field slice drawn through the scene (`showSlice(_:)`), or `nil`. It is no part of the scene: it never picks, frames
    /// or widens `sceneBounds`.
    public private(set) var slice: ViewportSlice?
    public internal(set) var hovered: PickTarget?
```

Edit `Sources/CreatorViewport/Model/ViewportModel.swift`:

```swift-old
                          cube: cubeLayout, triad: triadLayout, palette: palette, overlay: overlay,
                          showsViewCube: showsViewCube)
```

```swift-new
                          cube: cubeLayout, triad: triadLayout, palette: palette, overlay: overlay,
                          showsViewCube: showsViewCube, slice: slice)
```

Edit `Sources/CreatorViewport/Model/ViewportModel.swift`:

```swift-old
    /// Returns once the most recent `show(_:)` has finished loading.
```

```swift-new
    /// The slice to draw through the scene, or `nil` for none. An equal slice (the same `generation`) changes nothing.
    public func showSlice(_ newSlice: ViewportSlice?) {
        if slice != newSlice { slice = newSlice }
    }

    /// Returns once the most recent `show(_:)` has finished loading.
```

Edit `Sources/CreatorViewport/Model/ViewportRenderKey.swift`:

```swift-old
    /// Whether the view cube is drawn: entering or leaving planar navigation redraws.
    var showsViewCube: Bool
}
```

```swift-new
    /// Whether the view cube is drawn: entering or leaving planar navigation redraws.
    var showsViewCube: Bool
    /// The field slice: moving it or changing its values redraws (equal by `generation`, so the numbers are not hashed).
    var slice: ViewportSlice?
}
```

Edit `Sources/CreatorViewport/Render/ViewportFrame.swift`:

```swift-old
    var showsViewCube = true
```

```swift-new
    var showsViewCube = true
    /// The field slice (`ViewportModel.slice`).
    var slice: ViewportSlice?
```

Edit `Sources/CreatorViewport/Model/ViewportModel+Frame.swift`:

```swift-old
                             showsViewCube: showsViewCube)
```

```swift-new
                             showsViewCube: showsViewCube, slice: slice)
```

- [ ] **Step 4: The GPU side**

Create `Sources/CreatorViewport/Render/SliceUniforms.swift`:

```swift
import CreatorGeometry

/// The slice quad for its shaders: the centre, the half-extents as vectors (`across` is `xAxis × halfWidth`, `up` is
/// `yAxis × halfHeight`) and, in `style.x`, the opacity. Mirrors `SliceUniforms` in `FieldShaders` (stride pinned by
/// `ViewportSliceRenderTests`).
struct SliceUniforms {
    var origin: SIMD4<Float>
    var across: SIMD4<Float>
    var up: SIMD4<Float>
    var style: SIMD4<Float>

    init(_ slice: ViewportSlice) {
        let across = GPUGeometry.float3(slice.xAxis * slice.halfWidth)
        let up = GPUGeometry.float3(slice.yAxis * slice.halfHeight)
        origin = SIMD4(GPUGeometry.float3(slice.origin), 1)
        self.across = SIMD4(across, 0)
        self.up = SIMD4(up, 0)
        style = SIMD4(slice.opacity, 0, 0, 0)
    }
}
```

Edit `Sources/CreatorViewport/Render/FieldShaders.swift`:

```swift-old
    return float4(saturate(color), 1.0);
}
"""
}
```

```swift-new
    return float4(saturate(color), 1.0);
}

// MARK: Slice: a translucent quad showing a grid of values (fields spec section 6)

struct SliceUniforms { float4 origin; float4 across; float4 up; float4 style; };

struct SliceOut {
    float4 position [[position]];
    float2 uv;
};

vertex SliceOut slice_vertex(uint vid [[vertex_id]],
                             constant FrameUniforms &uniforms [[buffer(1)]],
                             constant SliceUniforms &slice [[buffer(2)]]) {
    float2 corner = float2((vid & 1u) != 0u ? 1.0 : 0.0, (vid & 2u) != 0u ? 1.0 : 0.0);
    float3 world = slice.origin.xyz + slice.across.xyz * (2.0 * corner.x - 1.0) + slice.up.xyz * (2.0 * corner.y - 1.0);
    SliceOut out;
    out.position = uniforms.viewProjection * float4(world, 1.0);
    out.uv = corner;
    return out;
}

// The grid read at `uv` (0...1 over the quad) with a bilinear blend of the four texels round it, texel centres at (i + 0.5) / size,
// edges held. Read with `read` and blended here, so no support for filtering a float texture is assumed.
float slice_value(texture2d<float> grid, float2 uv) {
    float2 size = float2(grid.get_width(), grid.get_height());
    float2 p = uv * size - 0.5;
    float2 f = p - floor(p);
    int2 low = int2(floor(p));
    int2 last = int2(size) - 1;
    uint2 a = uint2(clamp(low, int2(0), last));
    uint2 b = uint2(clamp(low + 1, int2(0), last));
    float bottom = mix(grid.read(uint2(a.x, a.y)).r, grid.read(uint2(b.x, a.y)).r, f.x);
    float top = mix(grid.read(uint2(a.x, b.y)).r, grid.read(uint2(b.x, b.y)).r, f.x);
    return mix(bottom, top, f.y);
}

fragment float4 slice_fragment(SliceOut in [[stage_in]],
                               constant SliceUniforms &slice [[buffer(0)]],
                               constant FieldRampUniforms &ramp [[buffer(1)]],
                               texture2d<float> grid [[texture(0)]]) {
    float3 color = field_ramp(ramp, slice_value(grid, in.uv));
    float alpha = slice.style.x;
    return float4(color * alpha, alpha);
}
"""
}
```

Edit `Sources/CreatorViewport/Render/ViewportPipelines.swift`:

```swift-old
    /// The surface coloured by a field's values (`field_mesh_*`).
    let fieldMesh: any MTLRenderPipelineState
```

```swift-new
    /// The surface coloured by a field's values (`field_mesh_*`).
    let fieldMesh: any MTLRenderPipelineState
    /// The field slice's translucent quad: blended.
    let slice: any MTLRenderPipelineState
```

Edit `Sources/CreatorViewport/Render/ViewportPipelines.swift`:

```swift-old
        fieldMesh = try pipeline("field_mesh_vertex", "field_mesh_fragment", blended: false)
```

```swift-new
        fieldMesh = try pipeline("field_mesh_vertex", "field_mesh_fragment", blended: false)
        slice = try pipeline("slice_vertex", "slice_fragment", blended: true)
```

Edit `Sources/CreatorViewport/Render/ViewportPipelines.swift` (the initialiser is at SwiftLint's length limit, so the shader lookup moves out of it):

```swift-old
    init(device: any MTLDevice) throws {
```

```swift-new
    /// The shader function called `name` in `library`.
    private static func function(_ name: String, in library: any MTLLibrary) throws -> any MTLFunction {
        guard let function = library.makeFunction(name: name) else { throw ViewportRenderError.missingShader(name) }
        return function
    }

    init(device: any MTLDevice) throws {
```

Edit `Sources/CreatorViewport/Render/ViewportPipelines.swift`:

```swift-old
        func function(_ name: String) throws -> any MTLFunction {
            guard let function = library.makeFunction(name: name) else { throw ViewportRenderError.missingShader(name) }
            return function
        }
        func pipeline(_ vertex: String, _ fragment: String, color: MTLPixelFormat = Self.colorFormat,
```

```swift-new
        func pipeline(_ vertex: String, _ fragment: String, color: MTLPixelFormat = Self.colorFormat,
```

Edit `Sources/CreatorViewport/Render/ViewportPipelines.swift`:

```swift-old
            descriptor.vertexFunction = try function(vertex)
            descriptor.fragmentFunction = try function(fragment)
```

```swift-new
            descriptor.vertexFunction = try Self.function(vertex, in: library)
            descriptor.fragmentFunction = try Self.function(fragment, in: library)
```

Edit `Sources/CreatorViewport/Render/ViewportRenderer.swift`:

```swift-old
    /// The triad's instances, which depend only on the pixel scale and the palette: an orbit turns the widget's camera.
```

```swift-new
    /// The field slice's grid as a texture, kept until the slice's generation or size changes.
    let sliceTextures = SliceTextures()
    /// The triad's instances, which depend only on the pixel scale and the palette: an orbit turns the widget's camera.
```

Edit `Sources/CreatorViewport/Render/ViewportRenderer.swift`:

```swift-old
        drawGuides(frame, uniforms, scale: pixelScale, encoder)
        drawOverlay(frame, uniforms, scale: pixelScale, encoder)
```

```swift-new
        drawGuides(frame, uniforms, scale: pixelScale, encoder)
        drawSlice(frame, uniforms, encoder)
        drawOverlay(frame, uniforms, scale: pixelScale, encoder)
```

Create `Sources/CreatorViewport/Render/SliceTextures.swift`:

```swift
import Metal

/// The field slice's grid as an `r32Float` texture, kept until the slice's generation or size changes, so a redraw of an
/// unchanged slice (an orbit) uploads nothing. A value that is not a number becomes the ramp's middle.
@MainActor
final class SliceTextures {
    private var cached: (generation: Int, columns: Int, rows: Int, texture: any MTLTexture)?
    /// Textures made so far. Tests use it to tell "kept" from "rebuilt".
    private(set) var uploads = 0

    func texture(for slice: ViewportSlice, device: any MTLDevice) -> (any MTLTexture)? {
        if let cached, cached.generation == slice.generation, cached.columns == slice.columns, cached.rows == slice.rows {
            return cached.texture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: slice.columns,
                                                                  height: slice.rows, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        let values = slice.values.map { $0.isFinite ? $0 : slice.ramp.midValue }
        values.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(region: MTLRegionMake2D(0, 0, slice.columns, slice.rows), mipmapLevel: 0, withBytes: base,
                            bytesPerRow: slice.columns * MemoryLayout<Float>.stride)
        }
        cached = (slice.generation, slice.columns, slice.rows, texture)
        uploads += 1
        return texture
    }
}
```

Create `Sources/CreatorViewport/Render/ViewportRenderer+Slice.swift`:

```swift
import Metal

extension ViewportRenderer {
    /// The field slice (fields spec §6): a translucent quad over the scene, ignoring depth because it passes through the part
    /// (a depth test would hide the half of it that lies inside the solid). It draws nothing for a slice with no valid grid.
    func drawSlice(_ frame: ViewportFrame, _ uniforms: FrameUniforms, _ encoder: any MTLRenderCommandEncoder) {
        guard let slice = frame.slice, slice.isValid, let texture = sliceTextures.texture(for: slice, device: device) else { return }
        var frameUniforms = uniforms
        var geometry = SliceUniforms(slice)
        var ramp = FieldRampUniforms(slice.ramp)
        encoder.setRenderPipelineState(pipelines.slice)
        encoder.setDepthStencilState(pipelines.depthAlways)
        encoder.setVertexBytes(&frameUniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.setVertexBytes(&geometry, length: MemoryLayout<SliceUniforms>.stride, index: 2)
        encoder.setFragmentBytes(&geometry, length: MemoryLayout<SliceUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&ramp, length: MemoryLayout<FieldRampUniforms>.stride, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}
```

- [ ] **Step 5: Run the viewport tests**

Run: `swift test --filter 'ViewportSliceTests|ViewportSliceRenderTests|FieldTint|OffscreenRenderTests|GuideRenderTests|RendererCacheTests|ViewportModelTests|GPUDataTests' 2>&1 | grep -E "recorded|failed|Test run" | head`
Expected: PASS.

- [ ] **Step 6: Lint and run the whole suite**

Run `swiftlint lint --strict` (zero violations) and the full `swift test` (background, to a log), judged by the rule in Global Constraints.
Expected: master + 84 tests (3,557).

- [ ] **Step 7: Commit**

```bash
git add Sources/CreatorViewport Tests/CreatorViewportTests
git commit -m "feat: the viewport draws a translucent field slice through the scene (7b-3)"
```
### Task 7: What a field preview is made of (the pure parts)

**Files:**
- Modify: `Sources/CreatorGraph/Field/Field.swift`
- Create: `Sources/CreatorGraph/Field/Field+DistanceSource.swift`, `Sources/CreatorGraph/Field/Field+Preview.swift`, `Sources/CreatorGraph/Field/FieldUnit.swift`
- Create: `Sources/CreatorApp/FieldPreview/FieldPreviewSelection.swift`, `FieldPreviewRange.swift`, `CoarseSampling.swift`, `FieldTint.swift`, `FieldPreviewSampler.swift`, `SliceAxis.swift`, `SliceChoice.swift`, `SlicePose.swift`
- Test: `Tests/CreatorGraphTests/Fields/FieldPreviewPropertiesTests.swift`, `Tests/CreatorAppTests/FieldPreview/FieldPreviewSelectionTests.swift`, `FieldPreviewRangeTests.swift`, `CoarseSamplingTests.swift`, `FieldPreviewSamplerTests.swift`, `SlicePoseTests.swift`

**Interfaces:**
- Consumes: `Field` and `FieldSampler.sample(_:at:kernel:cache:)`, `FieldDistanceCache`, `NodeRegistry`, `Graph`, `NodeResult`, `ViewportSlice` and `FieldRamp` (Tasks 5 and 6), `ThemeColors` (Task 1), `CameraPose.toEye`, `BoundingBox`.
- Produces (Tasks 8 to 10 rely on these exact names):
  - `Field: Hashable` (equal when it would sample alike: a distance to the same solid, faces or edges is equal by `DistanceTarget.identity`), `Field.ownPlane: Plane?`, `Field.measuresWithKernel: Bool`, `Field.isSignedDistance: Bool`, `Field.unit: FieldUnit` (`.none` or `.millimetres`).
  - `FieldPreviewSelection.previews(_ node: Node, registry:) -> Bool` and `FieldPreviewSelection.field(of:graph:results:registry:) -> Field?`.
  - `FieldPreviewRange` (`low`, `mid`, `high`: `Double`; `static let unit`; `static func make(extent: ClosedRange<Double>?, centredOnZero: Bool, fixedToUnit: Bool) -> FieldPreviewRange?`; `func ramp(colors: ThemeColors) -> FieldRamp`).
  - `CoarseSampling.vertexLimit` (200,000), `sampledIndices(count:limit:)`, `expand(positions:sampled:values:) throws -> [Float]`.
  - `FieldTint` (`values: [Float]`, `extent: ClosedRange<Double>?`, `isCoarse: Bool`) and `FieldPreviewSampler.tint(of:at:limit:kernel:cache:) async throws -> FieldTint` and `FieldPreviewSampler.gridValues(of:in:kernel:cache:) async throws -> (values: [Float], extent: ClosedRange<Double>?)`.
  - `SliceAxis` (`.xy`, `.yz`, `.xz`), `SliceChoice` (`.own`, `.axis(SliceAxis)`, `.hidden`) and `SlicePose` (`choice`, `plane`, `offset`, `halfWidth`, `halfHeight`, `offsetLimit`, `worldPlane`; `static func startingChoice(for:toEye:) -> SliceChoice` (needs no box), `static func starting(for:bounds:toEye:)`, `static func pose(for:field:bounds:) -> SlicePose?`, `static func through(_:bounds:)`, `static func fitted(_:choice:bounds:)`, `func moved(to:) -> SlicePose`, `static func resolution(for field: Field) -> Int`).

**The rules, from the spec (§6).**
- *Which selections preview:* a selected node of the Fields category (the sources and the maths make a field; Sample Field, Cull by Field and Field Scatter take one) whose field exists: the field a node makes, from its result; the field it takes, from the first wired field input's upstream result. An unwired input (a typed number is a constant field) has nothing to show; a node that failed makes no field, and a node whose upstream failed has none to take.
- *Range:* automatic (the sampled minimum to maximum, `mid` halfway) by default; a signed distance centres `mid` on 0 (the range is symmetric about 0, `-m…m` with `m` the larger magnitude); "0…1" fixes it to 0, 0.5, 1; a field that is the same everywhere gets `v - 0.5 … v + 0.5`; no finite value gives no range.
- *Coarse:* over 200,000 vertices a deterministic subset of 200,000 (evenly spaced in mesh order) is sampled and every other vertex takes its nearest sampled vertex's value (nearest by position, ties to the lower sampled index).
- *Slice pose:* it starts on the field's own plane when it has one (a gradient's; Image Field's in 7b-2), else through the part's bounding-box centre on the axis plane nearest the camera's view direction (the axis whose normal is most nearly along `toEye`; ties XY, YZ, XZ). The quad covers the part's box with 10% to spare; the offset along the normal is limited to what reaches every corner of the box.
- *Slice grid:* 256 × 256, or 64 × 64 when the field measures a solid, faces or edges with the kernel (65,536 kernel distances would take seconds on OCCT): **user decision 6**, a deliberate change to the spec's 256 × 256.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorGraphTests/Fields/FieldPreviewPropertiesTests.swift`:

```swift
import CreatorGeometry
import CreatorKernel
import Testing
@testable import CreatorGraph

/// What a preview asks of a field: equality (is it the same field as before?), its own plane, whether it needs the kernel,
/// whether it is a signed distance and its unit.
struct FieldPreviewPropertiesTests {
    func solid() async throws -> Solid {
        try await FakeKernel().extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided,
                                       tag: NodeTag(node: NodeID(), item: 0))
    }

    // MARK: equality

    @Test func theSameRecipeOverTheSameSolidIsEqualAndAnotherSolidIsNot() async throws {
        let one = try await solid(), other = try await solid()
        let a = Field.multiply(.distance(.kernel(.solid(one)), signed: true), .noise(seed: 4, scale: 5, octaves: 2))
        let b = Field.multiply(.distance(.kernel(.solid(one)), signed: true), .noise(seed: 4, scale: 5, octaves: 2))
        let c = Field.multiply(.distance(.kernel(.solid(other)), signed: true), .noise(seed: 4, scale: 5, octaves: 2))
        #expect(a == b && a.hashValue == b.hashValue)
        #expect(a != c)
        #expect(a != .multiply(.distance(.kernel(.solid(one)), signed: false), .noise(seed: 4, scale: 5, octaves: 2)))
        #expect(a != .multiply(.distance(.kernel(.solid(one)), signed: true), .noise(seed: 5, scale: 5, octaves: 2)))
    }

    @Test func edgeSetsAreEqualByTheirSolidAndEdges() async throws {
        let part = try await solid()
        let a = Field.distance(.kernel(.edges(EdgeSet(solid: part, edges: [EdgeID(0), EdgeID(1)]))), signed: false)
        let b = Field.distance(.kernel(.edges(EdgeSet(solid: part, edges: [EdgeID(1), EdgeID(0)]))), signed: false)
        #expect(a == b)
        #expect(a != .distance(.kernel(.edges(EdgeSet(solid: part, edges: [EdgeID(0)]))), signed: false))
        #expect(Field.distance(.point(.zero), signed: false) == .distance(.point(.zero), signed: false))
        #expect(Field.distance(.point(.zero), signed: false) != .distance(.point(.unitX), signed: false))
        #expect(Field.constant(1) != .constant(2) && Field.constant(1) != .radialGradient(center: .zero, radius: 1))
    }

    // MARK: own plane

    @Test func aGradientsPlaneIsTheFieldsOwnAndMathsKeepTheFirstOne() {
        let plane = Plane(origin: Vector3(1, 2, 3), normal: .unitX, xAxis: .unitY)
        let gradient = Field.linearGradient(plane: plane, length: 10)
        #expect(gradient.ownPlane == plane)
        #expect(Field.remap(gradient, fromLow: 0, fromHigh: 1, toLow: 0, toHigh: 5, clamped: true).ownPlane == plane)
        #expect(Field.add(.noise(seed: 1, scale: 5, octaves: 1), gradient).ownPlane == plane)
        let second = Plane(origin: .zero, normal: .unitZ, xAxis: .unitX)
        #expect(Field.add(gradient, .linearGradient(plane: second, length: 1)).ownPlane == plane, "the first")
        #expect(Field.radialGradient(center: .zero, radius: 5).ownPlane == nil)
        #expect(Field.constant(3).ownPlane == nil && Field.noise(seed: 1, scale: 5, octaves: 1).ownPlane == nil)
    }

    // MARK: kernel

    @Test func onlyADistanceToTheKernelNeedsTheKernel() async throws {
        let part = try await solid()
        let kernel = Field.distance(.kernel(.solid(part)), signed: true)
        #expect(kernel.measuresWithKernel)
        #expect(Field.clamp(.multiply(.constant(2), kernel), low: 0, high: 1).measuresWithKernel)
        #expect(!Field.distance(.point(.zero), signed: false).measuresWithKernel)
        #expect(!Field.distance(.profile(.rectangle(width: 4, height: 4, plane: .xy)), signed: false).measuresWithKernel)
        #expect(!Field.add(.noise(seed: 1, scale: 5, octaves: 1), .radialGradient(center: .zero, radius: 5)).measuresWithKernel)
    }

    // MARK: signed distance and unit

    @Test func aSignedDistanceToASolidCentresOnZeroAndSoDoesTheMinimumOfTwo() async throws {
        let part = try await solid()
        let signed = Field.distance(.kernel(.solid(part)), signed: true)
        let unsigned = Field.distance(.kernel(.solid(part)), signed: false)
        #expect(signed.isSignedDistance && !unsigned.isSignedDistance)
        #expect(!Field.distance(.kernel(.faces(FaceSet(solid: part, faces: [FaceID(0)]))), signed: true).isSignedDistance)
        #expect(Field.minimum(signed, signed).isSignedDistance && Field.clamp(signed, low: -2, high: 2).isSignedDistance)
        #expect(!Field.minimum(signed, unsigned).isSignedDistance && !Field.add(signed, signed).isSignedDistance)
        #expect(!Field.constant(0).isSignedDistance && !Field.noise(seed: 1, scale: 5, octaves: 1).isSignedDistance)
    }

    @Test func aDistanceIsInMillimetresAndSoIsWhatKeepsItsUnit() async throws {
        let distance = Field.distance(.point(.zero), signed: false)
        #expect(distance.unit == .millimetres)
        #expect(Field.clamp(distance, low: 0, high: 20).unit == .millimetres)
        #expect(Field.add(distance, .constant(5)).unit == .millimetres && Field.add(.constant(5), distance).unit == .millimetres)
        #expect(Field.minimum(distance, .distance(.point(.unitX), signed: false)).unit == .millimetres)
        #expect(Field.smoothMinimum(distance, distance, width: 2).unit == .millimetres)
        #expect(Field.add(distance, .noise(seed: 1, scale: 5, octaves: 1)).unit == .none, "a mixture has no unit")
        #expect(Field.multiply(distance, distance).unit == .none)
        #expect(Field.remap(distance, fromLow: 0, fromHigh: 20, toLow: 0, toHigh: 1, clamped: true).unit == .none)
        #expect(Field.radialGradient(center: .zero, radius: 5).unit == .none && Field.constant(1).unit == .none)
    }
}
```

Create `Tests/CreatorAppTests/FieldPreview/FieldPreviewSelectionTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// Which selections preview, and the field they show (fields spec §6).
@MainActor
struct FieldPreviewSelectionTests {
    let registry = BuiltInNodes.registry

    func evaluate(_ builder: GraphBuilder, demanding nodes: [Node]) async throws -> [NodeID: NodeResult] {
        try await Evaluator(registry: registry, kernel: FakeKernel()).evaluate(builder.graph, demand: Set(nodes.map(\.id))).results
    }

    func field(_ node: Node, _ builder: GraphBuilder, _ results: [NodeID: NodeResult]) -> Field? {
        FieldPreviewSelection.field(of: node, graph: builder.graph, results: results, registry: registry)
    }

    @Test func aSourceAndAMathsNodeShowTheFieldTheyMake() async throws {
        var builder = GraphBuilder()
        let radial = builder.add(RadialGradientNode.self, ["radius": .number(20)])
        let remap = builder.add(FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(1), "toLow": .number(1), "toHigh": .number(0),
        ])
        builder.wire(radial, "field", to: remap, "field")
        let results = try await evaluate(builder, demanding: [remap])
        #expect(field(radial, builder, results)?.description == "radial(radius 20)")
        #expect(field(remap, builder, results)?.description == "remap(radial(radius 20), 0…1 → 1…0)")
    }

    @Test func theNodesThatTakeAFieldShowTheWiredOne() async throws {
        var builder = GraphBuilder()
        let radial = builder.add(RadialGradientNode.self, ["radius": .number(20)])
        let sample = builder.add(SampleFieldNode.self)
        let cull = builder.add(CullByFieldNode.self)
        let scatter = builder.add(FieldScatterNode.self)
        for node in [sample, cull, scatter] { builder.wire(radial, "field", to: node, "field") }
        let results = try await evaluate(builder, demanding: [radial])
        for node in [sample, cull, scatter] {
            #expect(field(node, builder, results)?.description == "radial(radius 20)", "\(node.name)")
        }
    }

    @Test func anUnwiredFieldInputHasNothingToShow() async throws {
        var builder = GraphBuilder()
        let sample = builder.add(SampleFieldNode.self)
        let scatter = builder.add(FieldScatterNode.self)
        let results = try await evaluate(builder, demanding: [sample])
        #expect(field(sample, builder, results) == nil && field(scatter, builder, results) == nil, "a typed number is a constant")
    }

    @Test func aNodeThatFailedMakesNoFieldAndOneWhoseUpstreamFailedTakesNone() async throws {
        var builder = GraphBuilder()
        let radial = builder.add(RadialGradientNode.self, ["radius": .number(0)])
        let sample = builder.add(SampleFieldNode.self)
        builder.wire(radial, "field", to: sample, "field")
        let results = try await evaluate(builder, demanding: [radial])
        #expect(!(results[radial.id]?.state.isSuccess ?? true))
        #expect(field(radial, builder, results) == nil && field(sample, builder, results) == nil)
    }

    @Test func onlyFieldsNodesPreview() {
        var builder = GraphBuilder()
        let number = builder.add(NumberNode.self)
        let noise = builder.add(NoiseFieldNode.self)
        let scatter = builder.add(FieldScatterNode.self)
        let cull = builder.add(CullByRegionNode.self)
        #expect(!FieldPreviewSelection.previews(number, registry: registry) && !FieldPreviewSelection.previews(cull, registry: registry))
        #expect(FieldPreviewSelection.previews(noise, registry: registry) && FieldPreviewSelection.previews(scatter, registry: registry))
    }

    @Test func aNodeTheRegistryDoesNotKnowIsNotPreviewed() {
        let stranger = Node(typeID: "creator.nothing", name: "Nothing")
        #expect(!FieldPreviewSelection.previews(stranger, registry: registry))
        #expect(FieldPreviewSelection.field(of: stranger, graph: Graph(), results: [:], registry: registry) == nil)
    }
}
```

Create `Tests/CreatorAppTests/FieldPreview/FieldPreviewRangeTests.swift`:

```swift
import CreatorStyle
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The ramp's range rules (fields spec §6, "Ramp and legend").
struct FieldPreviewRangeTests {
    func make(_ low: Double, _ high: Double, signed: Bool = false, unit: Bool = false) -> FieldPreviewRange? {
        FieldPreviewRange.make(extent: low...high, centredOnZero: signed, fixedToUnit: unit)
    }

    @Test func automaticIsTheSampledMinimumToMaximumWithTheMiddleHalfway() {
        #expect(make(2, 10) == FieldPreviewRange(low: 2, mid: 6, high: 10))
        #expect(make(-3, 1) == FieldPreviewRange(low: -3, mid: -1, high: 1))
    }

    @Test func aSignedDistanceCentresTheMiddleOnZeroAndIsSymmetric() {
        #expect(make(-4, 10, signed: true) == FieldPreviewRange(low: -10, mid: 0, high: 10))
        #expect(make(-12, 3, signed: true) == FieldPreviewRange(low: -12, mid: 0, high: 12))
        #expect(make(2, 6, signed: true) == FieldPreviewRange(low: -6, mid: 0, high: 6), "all outside the part: still centred")
        #expect(make(0, 0, signed: true) == FieldPreviewRange(low: -1, mid: 0, high: 1))
    }

    @Test func theUnitToggleFixesTheRangeWhateverWasSampled() {
        #expect(make(-50, 50, unit: true) == .unit && make(-50, 50, signed: true, unit: true) == .unit)
        #expect(FieldPreviewRange.make(extent: nil, centredOnZero: false, fixedToUnit: true) == .unit, "even with nothing sampled")
        #expect(FieldPreviewRange.unit == FieldPreviewRange(low: 0, mid: 0.5, high: 1))
    }

    @Test func aFieldThatIsTheSameEverywhereGetsAUnitWideRange() {
        #expect(make(3, 3) == FieldPreviewRange(low: 2.5, mid: 3, high: 3.5))
    }

    @Test func noFiniteValueGivesNoRangeUnlessItIsFixed() {
        #expect(FieldPreviewRange.make(extent: nil, centredOnZero: false, fixedToUnit: false) == nil)
    }

    @Test func theRampTakesTheThemesThreeRolesAndTheRange() {
        let range = FieldPreviewRange(low: -2, mid: 0, high: 6)
        let ramp = range.ramp(colors: ColorTheme.dracula.colors)
        #expect(ramp.low == ColorTheme.dracula.colors.fieldLow.rgba && ramp.mid == ColorTheme.dracula.colors.fieldMid.rgba)
        #expect(ramp.high == ColorTheme.dracula.colors.fieldHigh.rgba)
        #expect(ramp.lowValue == -2 && ramp.midValue == 0 && ramp.highValue == 6)
    }
}
```

Create `Tests/CreatorAppTests/FieldPreview/CoarseSamplingTests.swift`:

```swift
import CreatorGeometry
import Testing
@testable import CreatorApp

/// Over 200,000 vertices a deterministic subset is sampled and the rest take their nearest sampled vertex's value (D14).
struct CoarseSamplingTests {
    @Test func theLimitIsTwoHundredThousand() {
        #expect(CoarseSampling.vertexLimit == 200_000)
    }

    @Test func aMeshWithinTheLimitIsSampledWholeInOrder() {
        #expect(CoarseSampling.sampledIndices(count: 5, limit: 5) == [0, 1, 2, 3, 4])
        #expect(CoarseSampling.sampledIndices(count: 0, limit: 5).isEmpty)
        #expect(CoarseSampling.sampledIndices(count: 3, limit: 5) == [0, 1, 2])
    }

    @Test func aBiggerOneGetsExactlyTheLimitEvenlySpacedAndNeverTwice() {
        #expect(CoarseSampling.sampledIndices(count: 10, limit: 4) == [0, 2, 5, 7])
        let many = CoarseSampling.sampledIndices(count: 200_001)
        #expect(many.count == 200_000 && Set(many).count == 200_000 && many.first == 0 && (many.last ?? 0) < 200_001)
        #expect(many == CoarseSampling.sampledIndices(count: 200_001), "deterministic")
    }

    @Test func everyVertexTakesItsNearestSampledVerticesValueTiesToTheLowerOne() throws {
        let positions = (0..<10).map { Vector3(Double($0), 0, 0) }
        let indices = [0, 2, 5, 7]
        let values = try CoarseSampling.expand(positions: positions, sampled: indices, values: [0, 20, 50, 70])
        #expect(values == [0, 0, 20, 20, 50, 50, 50, 70, 70, 70], "1 → 0 (tie with 2), 3 → 2, 4 → 5, 6 → 5 (tie with 7), 8 and 9 → 7")
    }

    @Test func theGridAgreesWithABruteForceSearchOnAScatterOfPoints() throws {
        var random = SplitMix(seed: 11)
        let positions = (0..<4_000).map { _ in Vector3(random.next() * 100, random.next() * 60, random.next() * 8) }
        let indices = CoarseSampling.sampledIndices(count: positions.count, limit: 500)
        let values = indices.map { Double($0) }
        let expanded = try CoarseSampling.expand(positions: positions, sampled: indices, values: values)
        #expect(expanded.count == positions.count)
        for vertex in stride(from: 0, to: positions.count, by: 37) {
            func distance(_ slot: Int) -> Double { (positions[indices[slot]] - positions[vertex]).length }
            var best = 0
            for slot in indices.indices where distance(slot) < distance(best) { best = slot }
            #expect(expanded[vertex] == Float(values[best]), "vertex \(vertex)")
        }
        #expect(indices.allSatisfy { expanded[$0] == Float($0) }, "a sampled vertex keeps its own value")
    }

    @Test func nothingSampledOrAWrongCountIsRefusedOrEmpty() throws {
        #expect(try CoarseSampling.expand(positions: [], sampled: [], values: []).isEmpty)
        #expect(try CoarseSampling.expand(positions: [.zero, .unitX], sampled: [1], values: [4]) == [4, 4])
        let whole = try CoarseSampling.expand(positions: [.zero, .unitX], sampled: [0, 1], values: [1, 2])
        #expect(whole == [1, 2])
    }

    @Test func aCancelledExpansionStops() async {
        let positions = (0..<30_000).map { Vector3(Double($0), 0, 0) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try CoarseSampling.expand(positions: positions, sampled: [0, 29_999], values: [1, 2])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

/// A small deterministic generator for the scatter test (not the app's `SeededRandom`, which is internal to CreatorNodes).
struct SplitMix {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    /// The next number in 0 ..< 1.
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) * 0x1p-53
    }
}
```

Create `Tests/CreatorAppTests/FieldPreview/FieldPreviewSamplerTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Testing
@testable import CreatorApp

/// Sampling a field over a mesh's vertices and a slice's grid (fields spec §6): one call to the sampler each.
struct FieldPreviewSamplerTests {
    let ramp = FieldRamp(low: SIMD4(1, 0, 0, 1), mid: SIMD4(0, 1, 0, 1), high: SIMD4(0, 0, 1, 1), range: 0...1)

    @Test func theTintIsTheFieldAtEachVertexWithItsExtent() async throws {
        let points = (0..<5).map { Vector3(Double($0) * 10, 0, 0) }
        let tint = try await FieldPreviewSampler.tint(of: .radialGradient(center: .zero, radius: 20), at: points, kernel: FakeKernel())
        #expect(tint.values == [0, 0.5, 1, 1.5, 2] && tint.extent == 0...2 && !tint.isCoarse)
    }

    @Test func aBigMeshIsSampledCoarselyAndSaysSo() async throws {
        let points = (0..<100).map { Vector3(Double($0), 0, 0) }
        let tint = try await FieldPreviewSampler.tint(of: .radialGradient(center: .zero, radius: 10), at: points, limit: 25,
                                                      kernel: FakeKernel())
        #expect(tint.isCoarse && tint.values.count == 100)
        #expect(tint.values[0] == 0 && tint.values[4] == tint.values[3] || tint.values[4] != 0, "neighbours share a value")
        #expect(tint.extent?.lowerBound == 0 && (tint.extent?.upperBound ?? 0) > 9)
        let whole = try await FieldPreviewSampler.tint(of: .radialGradient(center: .zero, radius: 10), at: points, limit: 100,
                                                       kernel: FakeKernel())
        #expect(!whole.isCoarse)
    }

    @Test func valuesThatAreNotNumbersAreNotInTheExtent() async throws {
        let nothing = try await FieldPreviewSampler.tint(of: .constant(.nan), at: [.zero, .unitX], kernel: FakeKernel())
        #expect(nothing.extent == nil)
        let some = try await FieldPreviewSampler.tint(of: .remap(.radialGradient(center: .zero, radius: 1), fromLow: 0, fromHigh: 0,
                                                                 toLow: 0, toHigh: 1, clamped: false),
                                                      at: [.zero], kernel: FakeKernel())
        #expect(some.values.count == 1)
    }

    @Test func noVerticesGiveNoValues() async throws {
        let tint = try await FieldPreviewSampler.tint(of: .constant(1), at: [], kernel: FakeKernel())
        #expect(tint.values.isEmpty && tint.extent == nil && !tint.isCoarse)
    }

    @Test func aCancelledSamplingStops() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FieldPreviewSampler.tint(of: .constant(1), at: [.zero], kernel: FakeKernel())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func theGridIsTheFieldAtTheSlicesSamplePoints() async throws {
        let slice = ViewportSlice(origin: Vector3(0, 0, 15), xAxis: .unitX, yAxis: .unitZ, halfWidth: 10, halfHeight: 4, columns: 2,
                                  rows: 2, values: [], ramp: ramp)
        let grid = try await FieldPreviewSampler.gridValues(of: .linearGradient(plane: .yz, length: 10), in: slice, kernel: FakeKernel())
        #expect(grid.values == [-0.5, 0.5, -0.5, 0.5], "x runs -5, 5 along each row; the gradient is x / 10")
        #expect(grid.extent == -0.5...0.5)
    }
}
```

Create `Tests/CreatorAppTests/FieldPreview/SlicePoseTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorApp

/// Where the slice starts and what it covers (fields spec §6, "Slice plane").
struct SlicePoseTests {
    /// A 60 × 40 × 6 plate, top on z = 0.
    let bounds = BoundingBox(min: Vector3(-30, -20, -6), max: Vector3(30, 20, 0))
    let noise = Field.noise(seed: 1, scale: 5, octaves: 1)

    func eye(yaw: Double, pitch: Double) -> Vector3 { CameraPose(target: .zero, distance: 1, yaw: yaw, pitch: pitch).toEye }

    @Test func aFieldWithAPlaneStartsOnIt() {
        let plane = Plane(origin: Vector3(-30, 0, 0), normal: .unitX, xAxis: .unitY)
        let pose = SlicePose.starting(for: .linearGradient(plane: plane, length: 60), bounds: bounds, toEye: eye(yaw: 0, pitch: 1))
        #expect(pose.choice == .own && pose.offset == 0)
        #expect(pose.worldPlane.normal == .unitX && pose.worldPlane.origin.x == -30, "on the gradient's plane, 0 at the edge")
        #expect(abs(pose.worldPlane.origin.y) < 1e-9 && abs(pose.worldPlane.origin.z + 3) < 1e-9, "centred on the part in the plane")
        #expect(abs(pose.halfWidth - 22) < 1e-9 && abs(pose.halfHeight - 3.3) < 1e-9, "the box seen along x, 10% to spare")
        #expect(abs(pose.offsetLimit - 60) < 1e-9, "far enough to reach the other end of the part")
    }

    @Test func withoutOneItGoesThroughTheBoxCentreOnTheAxisPlaneNearestTheCamera() {
        let above = SlicePose.starting(for: noise, bounds: bounds, toEye: eye(yaw: 0.3, pitch: 1.4))
        #expect(above.choice == .axis(.xy) && above.worldPlane.normal == .unitZ && above.worldPlane.origin == Vector3(0, 0, -3))
        #expect(abs(above.halfWidth - 33) < 1e-9 && abs(above.halfHeight - 22) < 1e-9)
        let front = SlicePose.starting(for: noise, bounds: bounds, toEye: eye(yaw: 0, pitch: 0))
        #expect(front.choice == .axis(.xz) && abs(front.worldPlane.normal.y) == 1)
        let right = SlicePose.starting(for: noise, bounds: bounds, toEye: eye(yaw: .pi / 2, pitch: 0))
        #expect(right.choice == .axis(.yz) && abs(right.worldPlane.normal.x) == 1)
    }

    @Test func aTieGoesToXYThenYZThenXZ() {
        let tie = Vector3(1, 1, 1).normalized ?? .unitZ
        #expect(SlicePose.starting(for: noise, bounds: bounds, toEye: tie).choice == .axis(.xy))
        let yz = Vector3(1, 0, 0), xz = Vector3(0, 1, 0)
        #expect(SlicePose.starting(for: noise, bounds: bounds, toEye: yz).choice == .axis(.yz))
        #expect(SlicePose.starting(for: noise, bounds: bounds, toEye: xz).choice == .axis(.xz))
    }

    @Test func theStartingChoiceNeedsNoBox() {
        let plane = Plane(origin: .zero, normal: .unitX, xAxis: .unitY)
        #expect(SlicePose.startingChoice(for: .linearGradient(plane: plane, length: 5), toEye: eye(yaw: 0, pitch: 0)) == .own)
        #expect(SlicePose.startingChoice(for: noise, toEye: eye(yaw: 0, pitch: 0)) == .axis(.xz))
        let degenerate = Plane(origin: .zero, normal: .zero, xAxis: .unitX)
        #expect(SlicePose.startingChoice(for: .linearGradient(plane: degenerate, length: 5), toEye: eye(yaw: 0, pitch: 1.5)) == .axis(.xy))
    }

    @Test func aPoseForAChoiceIsTheStartingOneOrNothing() {
        let plane = Plane(origin: Vector3(-30, 0, 0), normal: .unitX, xAxis: .unitY)
        let gradient = Field.linearGradient(plane: plane, length: 60)
        #expect(SlicePose.pose(for: .own, field: gradient, bounds: bounds)?.choice == .own)
        #expect(SlicePose.pose(for: .own, field: noise, bounds: bounds) == nil, "no plane of its own")
        #expect(SlicePose.pose(for: .axis(.yz), field: noise, bounds: bounds) == SlicePose.through(.yz, bounds: bounds))
        #expect(SlicePose.pose(for: .hidden, field: noise, bounds: bounds) == nil)
    }

    @Test func theLegendsAxisButtonsGoThroughTheCentreToo() {
        for axis in SliceAxis.allCases {
            let pose = SlicePose.through(axis, bounds: bounds)
            #expect(pose.choice == .axis(axis) && pose.offset == 0)
            #expect(isOnCentre(pose.worldPlane.origin), "\(axis)")
        }
    }

    func isOnCentre(_ point: Vector3) -> Bool { (point - bounds.center).length < 1e-9 }

    @Test func movingAddsTheOffsetAlongTheNormalAndHoldsItToTheLimit() {
        let pose = SlicePose.through(.xy, bounds: bounds)
        let moved = pose.moved(to: 2)
        #expect(moved.offset == 2 && moved.worldPlane.origin == Vector3(0, 0, -1) && moved.halfWidth == pose.halfWidth)
        #expect(pose.moved(to: 1_000).offset == pose.offsetLimit && pose.moved(to: -1_000).offset == -pose.offsetLimit)
        #expect(pose.moved(to: .nan).offset == 0, "not a number: stays put")
    }

    @Test func aFlatBoxStillMakesAUsableQuad() {
        let flat = BoundingBox(min: Vector3(-5, -5, 0), max: Vector3(5, 5, 0))
        let pose = SlicePose.through(.xz, bounds: flat)
        #expect(pose.halfHeight >= 0.5 && pose.offsetLimit >= 1)
    }

    @Test func theGridIsFinerWhereNoKernelIsNeeded() async throws {
        #expect(SlicePose.resolution(for: noise) == 256)
        let solid = try await FakeKernelBox.solid()
        #expect(SlicePose.resolution(for: .distance(.kernel(.solid(solid)), signed: true)) == 64)
        #expect(SlicePose.resolution(for: .distance(.point(.zero), signed: false)) == 256)
    }
}

import CreatorKernel

/// A solid to measure to.
enum FakeKernelBox {
    static func solid() async throws -> Solid {
        try await FakeKernel().extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: 10, mode: .oneSided,
                                       tag: NodeTag(node: NodeID(), item: 0))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: FAIL to compile, "cannot find 'FieldPreviewSelection' in scope", "value of type 'Field' has no member 'ownPlane'".

- [ ] **Step 3: Field's equality and the properties a preview asks**

Edit `Sources/CreatorGraph/Field/Field.swift`:

```swift-old
public indirect enum Field: Sendable {
```

```swift-new
public indirect enum Field: Hashable, Sendable {
```

Create `Sources/CreatorGraph/Field/Field+DistanceSource.swift`:

```swift
import CreatorKernel

/// Equality for fields (the previews ask "is this the field I last sampled?"): a distance to a solid, faces or edges is the
/// same distance when its target is, by `DistanceTarget.identity` (the solid object and the selected IDs), since a `Solid`
/// has no value equality. Everything else a field holds is plain values.
extension Field.DistanceSource: Hashable {
    public static func == (lhs: Field.DistanceSource, rhs: Field.DistanceSource) -> Bool {
        switch (lhs, rhs) {
        case (.point(let a), .point(let b)): a == b
        case (.profile(let a), .profile(let b)): a == b
        case (.kernel(let a), .kernel(let b)): a.identity == b.identity
        case (.point, _), (.profile, _), (.kernel, _): false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .point(let point):
            hasher.combine(0)
            hasher.combine(point)
        case .profile(let profile):
            hasher.combine(1)
            hasher.combine(profile)
        case .kernel(let target):
            hasher.combine(2)
            hasher.combine(target.identity)
        }
    }
}
```

Create `Sources/CreatorGraph/Field/FieldUnit.swift`:

```swift
/// What a field's numbers are measured in, for the preview's legend (fields spec §6: "units where the field has them (mm for
/// distances)"). Most fields are plain numbers.
public enum FieldUnit: Sendable, Equatable {
    case none
    case millimetres
}
```

Create `Sources/CreatorGraph/Field/Field+Preview.swift`:

```swift
import CreatorGeometry

/// What the field previews ask of a field (fields spec §6). Each is an exhaustive `switch` with no `default`, so a case added
/// later (Image Field in 7b-2, which has a plane of its own) is a compile error here until it says what it is.
extension Field {
    /// The plane the field is itself about, for the slice to start on: a linear gradient's, or the first one found in the
    /// fields this one is made from.
    public var ownPlane: Plane? {
        switch self {
        case .linearGradient(let plane, _):
            plane
        case .constant, .distance, .radialGradient, .noise, .add, .multiply, .minimum, .maximum, .remap, .clamp, .smoothMinimum:
            children.lazy.compactMap(\.ownPlane).first
        }
    }

    /// Whether sampling needs the kernel: a distance to a solid, faces or edges, anywhere in the expression.
    public var measuresWithKernel: Bool {
        switch self {
        case .distance(.kernel, _):
            true
        case .distance, .constant, .linearGradient, .radialGradient, .noise:
            false
        case .add, .multiply, .minimum, .maximum, .remap, .clamp, .smoothMinimum:
            children.contains { $0.measuresWithKernel }
        }
    }

    /// Whether the ramp centres its middle colour on 0 (fields spec §6): a signed distance to a solid, the smaller or larger of
    /// two such, or one held to a range.
    public var isSignedDistance: Bool {
        switch self {
        case .distance(.kernel(.solid), signed: true):
            true
        case .minimum(let a, let b), .maximum(let a, let b), .smoothMinimum(let a, let b, _):
            a.isSignedDistance && b.isSignedDistance
        case .clamp(let inner, _, _):
            inner.isSignedDistance
        case .constant, .distance, .linearGradient, .radialGradient, .noise, .add, .multiply, .remap:
            false
        }
    }

    /// What the field's numbers are measured in: a distance is in millimetres, and so is a distance held to a range or combined
    /// with a plain number or another distance by Add, Min / Max or Smooth Blend. A product, a remap and everything else are
    /// plain numbers.
    public var unit: FieldUnit {
        switch self {
        case .distance:
            .millimetres
        case .add(let a, let b), .minimum(let a, let b), .maximum(let a, let b), .smoothMinimum(let a, let b, _):
            Self.combinedUnit(a, b)
        case .clamp(let inner, _, _):
            inner.unit
        case .constant, .linearGradient, .radialGradient, .noise, .multiply, .remap:
            .none
        }
    }

    /// The unit of a sum or extremum of two fields: a plain constant takes the other's, equal units stay, a mixture has none.
    private static func combinedUnit(_ a: Field, _ b: Field) -> FieldUnit {
        if case .constant = a { return b.unit }
        if case .constant = b { return a.unit }
        return a.unit == b.unit ? a.unit : .none
    }
}
```

- [ ] **Step 4: The preview's pure parts in the app**

Create `Sources/CreatorApp/FieldPreview/FieldPreviewSelection.swift`:

```swift
import CreatorGraph
import CreatorKernel

/// Which selections show a field preview, and which field (fields spec §6): a selected node of the Fields category whose
/// field exists. A node that makes a field shows the one in its result; a node that takes one (Sample Field, Cull by Field,
/// Field Scatter) shows the first field wired into it, even before anything downstream is wired. A typed number is a constant
/// field with nothing to show, a node that failed makes no field, and a node whose upstream failed has none to take.
enum FieldPreviewSelection {
    /// True for a node a field preview follows: any node in the Fields library category.
    static func previews(_ node: Node, registry: NodeRegistry) -> Bool {
        registry[node.typeID]?.category == .fields
    }

    static func field(of node: Node, graph: Graph, results: [NodeID: NodeResult], registry: NodeRegistry) -> Field? {
        guard previews(node, registry: registry) else { return nil }
        if let output = registry.outputs(for: node).first(where: { $0.type == .field }) {
            guard let result = results[node.id], result.state.isSuccess else { return nil }
            return firstField(result.outputs?[output.name])
        }
        for input in registry.inputs(for: node) where input.type == .field {
            guard let link = graph.incomingLink(to: Endpoint(node: node.id, socket: input.name)),
                  let upstream = results[link.from.node], upstream.state.isSuccess,
                  let field = firstField(upstream.outputs?[link.from.socket]) else { continue }
            return field
        }
        return nil
    }

    private static func firstField(_ value: Value?) -> Field? {
        value?.items.lazy.compactMap { scalar -> Field? in
            if case .field(let field) = scalar { field } else { nil }
        }.first
    }
}
```

Create `Sources/CreatorApp/FieldPreview/FieldPreviewRange.swift`:

```swift
import CreatorStyle
import CreatorViewport

/// The values the ramp's three colours stand at (fields spec §6, "Ramp and legend"). Automatic is the sampled minimum to
/// maximum with the middle halfway; a signed distance centres the middle on 0 (symmetric, so 0 is the neutral colour); "0…1"
/// fixes it to 0, 0.5, 1.
struct FieldPreviewRange: Equatable, Sendable {
    var low: Double
    var mid: Double
    var high: Double

    static let unit = FieldPreviewRange(low: 0, mid: 0.5, high: 1)

    /// The range for what was sampled: `extent` is the smallest and largest finite value (`nil` when none was finite).
    /// `nil` when there is no range to show; the fixed 0…1 range needs no values.
    static func make(extent: ClosedRange<Double>?, centredOnZero: Bool, fixedToUnit: Bool) -> FieldPreviewRange? {
        if fixedToUnit { return .unit }
        guard let extent else { return nil }
        if centredOnZero {
            let reach = max(abs(extent.lowerBound), abs(extent.upperBound))
            return reach > 0 ? FieldPreviewRange(low: -reach, mid: 0, high: reach) : FieldPreviewRange(low: -1, mid: 0, high: 1)
        }
        if extent.lowerBound == extent.upperBound {
            return FieldPreviewRange(low: extent.lowerBound - 0.5, mid: extent.lowerBound, high: extent.lowerBound + 0.5)
        }
        return FieldPreviewRange(low: extent.lowerBound, mid: (extent.lowerBound + extent.upperBound) / 2, high: extent.upperBound)
    }

    /// The viewport's ramp: the theme's three field roles at this range's three values.
    func ramp(colors: ThemeColors) -> FieldRamp {
        FieldRamp(low: colors.fieldLow.rgba, mid: colors.fieldMid.rgba, high: colors.fieldHigh.rgba, lowValue: Float(low),
                  midValue: Float(mid), highValue: Float(high))
    }
}
```

Create `Sources/CreatorApp/FieldPreview/CoarseSampling.swift`:

```swift
import CreatorGeometry

/// A big mesh's coarse sampling (fields spec §6 and D14): over `vertexLimit` vertices a deterministic subset of exactly that many
/// is sampled, evenly spaced in mesh order, and every other vertex takes the value of the nearest sampled vertex (ties to the
/// lower one), found with a grid, so the legend can say "Preview sampled coarsely" and the tint stays interactive.
enum CoarseSampling {
    /// The spec's number (D14).
    static let vertexLimit = 200_000

    /// The vertices to sample: all of them when there are at most `limit`, else `limit` indices `i × count / limit`.
    static func sampledIndices(count: Int, limit: Int = vertexLimit) -> [Int] {
        guard count > limit, limit > 0 else { return Array(0..<max(count, 0)) }
        return (0..<limit).map { $0 * count / limit }
    }

    /// One value per vertex: each sampled vertex keeps its own (`values[n]` for `positions[indices[n]]`), every other takes the
    /// nearest sampled vertex's. Checks for cancellation as it goes.
    static func expand(positions: [Vector3], sampled indices: [Int], values: [Double]) throws -> [Float] {
        precondition(indices.count == values.count, "one value per sampled vertex")
        guard !indices.isEmpty else { return [Float](repeating: .nan, count: positions.count) }
        if indices.count == positions.count { return values.map { Float($0) } }
        // The grid covers every vertex, not only the sampled ones: a vertex outside the sampled points' box still finds its nearest.
        guard let box = BoundingBox(points: positions) else { return [] }
        let grid = Grid(points: indices.map { positions[$0] }, box: box)
        var result = [Float](repeating: .nan, count: positions.count)
        for (slot, index) in indices.enumerated() { result[index] = Float(values[slot]) }
        let isSampled = Set(indices)
        for (vertex, position) in positions.enumerated() where !isSampled.contains(vertex) {
            if vertex % 4_096 == 0 { try Task.checkCancellation() }
            if let slot = grid.nearest(to: position) { result[vertex] = Float(values[slot]) }
        }
        return result
    }

    private struct Cell: Hashable {
        var x: Int32
        var y: Int32
        var z: Int32
    }

    /// The sampled points in a grid of cubes about one point to a cube on average (a surface: about the square root of their
    /// number across the widest side), for nearest-point searches.
    private struct Grid {
        let points: [Vector3]
        let origin: Vector3
        let width: Double
        /// The ring of cubes beyond which nothing can be.
        let widest: Int32
        private var cells: [Cell: [Int]] = [:]

        init(points: [Vector3], box: BoundingBox) {
            self.points = points
            origin = box.min
            let size = box.size
            let longest = max(size.x, size.y, size.z)
            width = max(longest / max(Double(points.count).squareRoot(), 1), 1e-9)
            widest = Int32(clamping: Int((longest / width).rounded(.up)) + 1)
            for (slot, point) in points.enumerated() { cells[cell(of: point), default: []].append(slot) }
        }

        private func cell(of point: Vector3) -> Cell {
            func index(_ value: Double, from start: Double) -> Int32 { Int32(clamping: Int(((value - start) / width).rounded(.down))) }
            return Cell(x: index(point.x, from: origin.x), y: index(point.y, from: origin.y), z: index(point.z, from: origin.z))
        }

        /// The slot of the sampled point nearest `position`, the lowest slot among equals; `nil` with no points.
        func nearest(to position: Vector3) -> Int? {
            let home = cell(of: position)
            var best: (slot: Int, distance: Double)?
            for ring in 0...widest {
                for dx in -ring...ring {
                    for dy in -ring...ring {
                        for dz in -ring...ring where max(abs(dx), abs(dy), abs(dz)) == ring {
                            consider(Cell(x: home.x &+ dx, y: home.y &+ dy, z: home.z &+ dz), from: position, best: &best)
                        }
                    }
                }
                // Anything in a ring further out is at least `ring × width` away.
                if let found = best, found.distance <= Double(ring) * width { break }
            }
            return best?.slot
        }

        private func consider(_ cell: Cell, from position: Vector3, best: inout (slot: Int, distance: Double)?) {
            for slot in cells[cell] ?? [] {
                let distance = (points[slot] - position).length
                guard let current = best else {
                    best = (slot, distance)
                    continue
                }
                if distance < current.distance || (distance == current.distance && slot < current.slot) { best = (slot, distance) }
            }
        }
    }
}
```

Create `Sources/CreatorApp/FieldPreview/FieldTint.swift`:

```swift
/// A field sampled at a mesh's vertices (fields spec §6): one value per vertex, in the mesh's order, the smallest and largest
/// finite value sampled (the ramp's automatic range; `nil` when none was finite) and whether the sampling was coarse (D14).
struct FieldTint: Sendable, Equatable {
    var values: [Float]
    var extent: ClosedRange<Double>?
    var isCoarse: Bool
}
```

Create `Sources/CreatorApp/FieldPreview/FieldPreviewSampler.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport

/// Samples a field for the previews with the one entry point (`FieldSampler.sample`), off the main actor's way: the tint over a
/// mesh's vertices, coarsely over `limit` vertices (D14), and the slice's grid.
enum FieldPreviewSampler {
    static func tint(of field: Field, at positions: [Vector3], limit: Int = CoarseSampling.vertexLimit, kernel: any Kernel,
                     cache: FieldDistanceCache? = nil) async throws -> FieldTint {
        let indices = CoarseSampling.sampledIndices(count: positions.count, limit: limit)
        let isCoarse = indices.count < positions.count
        let points = isCoarse ? indices.map { positions[$0] } : positions
        let sampled = try await FieldSampler.sample(field, at: points, kernel: kernel, cache: cache)
        let values = isCoarse ? try CoarseSampling.expand(positions: positions, sampled: indices, values: sampled)
                              : sampled.map { Float($0) }
        return FieldTint(values: values, extent: extent(of: sampled), isCoarse: isCoarse)
    }

    /// The field at the slice's grid samples (`ViewportSlice.samplePoints()`), in `values`' order, and their extent.
    static func gridValues(of field: Field, in slice: ViewportSlice, kernel: any Kernel,
                           cache: FieldDistanceCache? = nil) async throws -> (values: [Float], extent: ClosedRange<Double>?) {
        let sampled = try await FieldSampler.sample(field, at: slice.samplePoints(), kernel: kernel, cache: cache)
        return (sampled.map { Float($0) }, extent(of: sampled))
    }

    /// The smallest to the largest finite value, or `nil` when there is none.
    static func extent(of values: [Double]) -> ClosedRange<Double>? {
        var low = Double.infinity
        var high = -Double.infinity
        for value in values where value.isFinite {
            low = min(low, value)
            high = max(high, value)
        }
        return low <= high ? low...high : nil
    }
}
```

Create `Sources/CreatorApp/FieldPreview/SliceAxis.swift`:

```swift
import CreatorGeometry

/// One of the three axis planes the slice can lie in (fields spec §6): the legend's XY, YZ and XZ buttons.
enum SliceAxis: CaseIterable, Equatable, Sendable {
    case xy
    case yz
    case xz

    var title: String {
        switch self {
        case .xy: "XY"
        case .yz: "YZ"
        case .xz: "XZ"
        }
    }

    /// The plane through the origin.
    var plane: Plane {
        switch self {
        case .xy: .xy
        case .yz: .yz
        case .xz: .xz
        }
    }
}
```

Create `Sources/CreatorApp/FieldPreview/SliceChoice.swift`:

```swift
/// Where the legend says the slice is: on the field's own plane (the start, when it has one), on an axis plane through the
/// part, or hidden.
enum SliceChoice: Equatable, Sendable {
    case own
    case axis(SliceAxis)
    case hidden
}
```

Create `Sources/CreatorApp/FieldPreview/SlicePose.swift`:

```swift
import CreatorGeometry
import CreatorGraph

/// Where the slice quad lies and how far it covers (fields spec §6, "Slice plane"): a plane with the quad centred on the part's
/// box in it, an offset along the plane's normal that the viewport handle moves, and the limit of that offset. View state in
/// memory, never saved.
struct SlicePose: Equatable, Sendable {
    /// `.own` or `.axis` (a hidden slice has no pose).
    var choice: SliceChoice
    /// The plane at offset 0, its origin the part box's centre projected into it.
    var plane: Plane
    var offset: Double
    var halfWidth: Double
    var halfHeight: Double
    /// The most the offset may be in either direction: far enough to reach every corner of the box.
    var offsetLimit: Double

    /// The plane the quad lies in now.
    var worldPlane: Plane { plane.offset(by: offset) }

    /// How much of the box's size the quad covers beyond it.
    static let margin = 1.1

    /// How a preview of `field` starts: on the field's own plane when it has one, else on the axis plane nearest the view
    /// direction `toEye` (the axis whose normal is most nearly along it; ties XY, YZ, XZ).
    static func startingChoice(for field: Field, toEye: Vector3) -> SliceChoice {
        if let own = field.ownPlane, own.normal.normalized != nil { return .own }
        return .axis(SliceAxis.allCases.max { abs(toEye.dot($0.plane.normal)) < abs(toEye.dot($1.plane.normal)) } ?? .xy)
    }

    /// Where a preview of `field` starts for a part inside `bounds` seen from the direction `toEye`.
    static func starting(for field: Field, bounds: BoundingBox, toEye: Vector3) -> SlicePose {
        pose(for: startingChoice(for: field, toEye: toEye), field: field, bounds: bounds) ?? through(.xy, bounds: bounds)
    }

    /// The pose for a choice of place: on the field's own plane (`nil` if it has none), through the box's centre on an axis
    /// plane, or `nil` when hidden. Its offset is 0.
    static func pose(for choice: SliceChoice, field: Field, bounds: BoundingBox) -> SlicePose? {
        switch choice {
        case .own: field.ownPlane.map { fitted($0, choice: .own, bounds: bounds) }
        case .axis(let axis): through(axis, bounds: bounds)
        case .hidden: nil
        }
    }

    /// The axis plane through the box's centre.
    static func through(_ axis: SliceAxis, bounds: BoundingBox) -> SlicePose {
        var plane = axis.plane
        plane.origin = bounds.center
        return fitted(plane, choice: .axis(axis), bounds: bounds)
    }

    /// `plane` with the quad centred on the box in it and sized to cover the box's corners, with a margin.
    static func fitted(_ plane: Plane, choice: SliceChoice, bounds: BoundingBox) -> SlicePose {
        let (x, y, normal) = (plane.xAxis, plane.yAxis, plane.normal.normalized ?? plane.normal)
        let centre = bounds.center - plane.origin
        let origin = plane.origin + x * centre.dot(x) + y * centre.dot(y)
        let corners = [bounds.min.x, bounds.max.x].flatMap { cx in
            [bounds.min.y, bounds.max.y].flatMap { cy in [bounds.min.z, bounds.max.z].map { Vector3(cx, cy, $0) } }
        }
        func reach(_ axis: Vector3, from start: Vector3) -> Double { corners.map { abs(($0 - start).dot(axis)) }.max() ?? 0 }
        return SlicePose(choice: choice, plane: Plane(origin: origin, normal: normal, xAxis: x), offset: 0,
                         halfWidth: max(reach(x, from: origin) * margin, 0.5), halfHeight: max(reach(y, from: origin) * margin, 0.5),
                         offsetLimit: max(reach(normal, from: origin), 1))
    }

    /// The same pose at `offset` along the normal, held to the limit; a number that is not one leaves it where it is.
    func moved(to offset: Double) -> SlicePose {
        guard offset.isFinite else { return self }
        var moved = self
        moved.offset = min(max(offset, -offsetLimit), offsetLimit)
        return moved
    }

    /// The grid size (columns and rows) for `field`: 256, or 64 when sampling needs the kernel, since 65,536 kernel distances
    /// take seconds on OCCT (user decision 6; the spec says 256 throughout).
    static func resolution(for field: Field) -> Int {
        field.measuresWithKernel ? 64 : 256
    }
}
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter 'FieldPreviewPropertiesTests|FieldPreviewSelectionTests|FieldPreviewRangeTests|CoarseSamplingTests|FieldPreviewSamplerTests|SlicePoseTests' 2>&1 | grep -E "recorded|failed|Test run" | head -20`
Expected: PASS.

- [ ] **Step 6: Lint and run the whole suite**

Run `swiftlint lint --strict` (zero violations) and the full `swift test` (background, to a log), judged by the rule in Global Constraints.
Expected: master + 124 tests (3,597).

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat: the pure parts of the field preview: selection, range, coarse sampling, slice pose (7b-3)"
```
### Task 8: The field preview in the app

**Files:**
- Create: `Sources/CreatorApp/FieldPreview/FieldPreviewRequest.swift`, `SolidTint.swift`, `SliceGrid.swift`, `FieldLegend.swift`, `FieldPreviewModel.swift`, `FieldPreviewModel+Scene.swift`
- Create: `Sources/CreatorApp/AppModel+FieldPreview.swift`
- Modify: `Sources/CreatorApp/AppModel.swift`, `AppModel+Scene.swift`, `AppModel+Viewport.swift`, `ViewportItem+Comparison.swift`
- Modify: `Sources/CreatorGraph/DocumentModel.swift` (`fieldDistances`)
- Test: `Tests/CreatorAppTests/FieldPreview/FieldPreviewModelTests.swift`, `FieldPreviewSliceTests.swift`, `Tests/CreatorAppTests/AppFieldPreviewTests.swift`

**Interfaces:**
- Consumes: everything Tasks 5 to 7 produce (`FieldRamp`, `ViewportItem.fieldValues`, `ViewportSlice`, `ViewportModel.displayMesh(of:)`, `showSlice(_:)`, `FieldPreviewSelection`, `FieldPreviewRange`, `FieldPreviewSampler`, `FieldTint`, `SlicePose`, `SliceChoice`, `SliceAxis`), `ThemeColors`, `AppModel.refreshScene()`, `ViewportHandle`.
- Produces (Tasks 9 and 10 rely on these exact names):
  - `FieldPreviewModel` (`@MainActor @Observable`): `init(kernel:distances:vertexLimit:meshes:)`; `follow(_ request: FieldPreviewRequest?)`; `chooseSlice(_:)`, `moveSlice(to:)`, `setUnitRange(_:)`, `stop()`, `waitForSampling() async`; state `revision`, `node`, `field`, `choice`, `offset`, `usesUnitRange`, `isSampling`, `failure`, `tints`, `grid`, `bounds`; derived `pose`, `range`, `legend: FieldLegend?`, `hasOwnPlane`, `sliceHandle: ViewportHandle?`, `tinted(_:colors:)`, `viewportSlice(colors:)`; `FieldPreviewModel.sliceHandleID` (`"field-slice"`).
  - `FieldLegend` (`range: FieldPreviewRange?`, `unit: FieldUnit`, `isCoarse`, `usesUnitRange`, `choice: SliceChoice`, `hasOwnPlane`, `failure: String?`).
  - `AppModel.fieldPreview: FieldPreviewModel` (replaced with the document), `AppModel.fieldPreviewRequest(for:)`, `DocumentModel.fieldDistances: FieldDistanceCache`.

**How it fits (spec §6).** `AppModel.refreshScene()` already builds the scene and the handles each time the document, the selection or the theme changes. It now also asks `FieldPreviewModel.follow(_:)` to follow the one selected node's field (`fieldPreviewRequest(for:)`: a selected Fields node whose field exists, while not picking or sketching), tints the opaque items the model has a tint for (`tinted(_:colors:)`), shows the slice (`viewportSlice(colors:)`) and appends the slice's handle. The model samples off the main actor in two tasks, the tint (every shown solid's mesh vertices, one `FieldSampler` call each, through the evaluator's distance cache so an orbit or a toggle resamples nothing) and the slice grid; a newer request cancels the older, and **the old tint and slice stay until the new ones are ready** (no grey flash). A change of node, of field, of the shown parts or of their box starts a sampling; nothing else does (a camera settling, a canvas pan or a panel resize calls `follow` with the same request and changes nothing). The toggles (0…1 range, slice axis, hide) and the slice offset are view state in the model, never saved and never an undo step; the "0…1" toggle changes the ramp, not the values, so it samples nothing. When the sampling fails (a kernel error), the legend says so in the kernel's words and the tint and slice go: never a silent zero. A new node starts with the slice shown, on the field's own plane when it has one, else through the part's box on the axis plane nearest the camera (**user decision 8**: shown at the start).

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorAppTests/FieldPreview/FieldPreviewModelTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorStyle
import CreatorViewport
import Testing
@testable import CreatorApp

/// Holds the preview's mesh lookup back until a test opens the gate, so a test can look at the model while it samples.
actor SamplingGate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}

/// The gate a test's meshes wait at, and how many meshes were asked for.
@MainActor
final class PreviewHarness {
    var gate: SamplingGate?
    private(set) var asked = 0
    var meshes: [ObjectIdentifier: DisplayMesh] = [:]

    @discardableResult
    func part(width: Double = 20, depth: Double = 10, height: Double = 6) async throws -> Solid {
        let kernel = FakeKernel()
        let solid = try await kernel.extrude(.rectangle(width: width, height: depth, plane: .xy), distance: height, mode: .oneSided,
                                             tag: NodeTag(node: NodeID(), item: 0))
        meshes[ObjectIdentifier(solid)] = try await kernel.tessellate(solid, tolerance: 0.05)
        return solid
    }

    func model(limit: Int = CoarseSampling.vertexLimit) -> FieldPreviewModel {
        FieldPreviewModel(kernel: FakeKernel(), distances: FieldDistanceCache(), vertexLimit: limit) { [self] solid in
            asked += 1
            if let gate { await gate.wait() }
            return meshes[ObjectIdentifier(solid)]
        }
    }

    func request(_ node: NodeID, _ field: Field, _ solids: [Solid], toEye: Vector3 = .unitZ) -> FieldPreviewRequest {
        FieldPreviewRequest(node: node, field: field, solids: solids, toEye: toEye)
    }
}

/// Following a field, sampling it for the tint and the slice, and what the model hands the scene (fields spec §6).
@MainActor
struct FieldPreviewModelTests {
    let radial = Field.radialGradient(center: .zero, radius: 10)
    let node = NodeID()

    @Test func aRequestSamplesEachSolidAtItsVerticesAndPublishesTheTint() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        model.follow(harness.request(node, radial, [part]))
        #expect(model.node == node && model.field == radial)
        await model.waitForSampling()
        let mesh = try #require(harness.meshes[ObjectIdentifier(part)])
        let tint = try #require(model.tints[ObjectIdentifier(part)]?.tint)
        #expect(tint.values.count == mesh.positions.count && !tint.isCoarse && !model.isSampling)
        #expect(tint.values[0] == Float(mesh.positions[0].length / 10))
        #expect(model.range == FieldPreviewRange.make(extent: model.extent, centredOnZero: false, fixedToUnit: false))
        #expect(model.legend?.unit == FieldUnit.none && model.legend?.failure == nil && model.legend?.isCoarse == false)
    }

    @Test func aRepeatedRequestChangesNothingAndSamplesNothing() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        model.follow(harness.request(node, radial, [part]))
        await model.waitForSampling()
        let (revision, asked) = (model.revision, harness.asked)
        model.follow(harness.request(node, radial, [part], toEye: .unitX))
        await model.waitForSampling()
        #expect(model.revision == revision && harness.asked == asked, "the camera moving is not a new request")
    }

    @Test func anEditedFieldKeepsTheOldTintUntilTheNewOneIsReady() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        model.follow(harness.request(node, radial, [part]))
        await model.waitForSampling()
        let before = try #require(model.tints[ObjectIdentifier(part)]?.tint.values)

        let gate = SamplingGate()
        harness.gate = gate
        model.follow(harness.request(node, .radialGradient(center: .zero, radius: 20), [part]))
        #expect(model.isSampling)
        #expect(model.tints[ObjectIdentifier(part)]?.tint.values == before, "the old tint stays: no grey flash")
        await gate.open()
        await model.waitForSampling()
        let after = try #require(model.tints[ObjectIdentifier(part)]?.tint.values)
        #expect(after != before && after[1] == before[1] / 2, "the new tint: twice the radius, half the value")
    }

    @Test func aNewerRequestSupersedesAnOlderOneWhichPublishesNothing() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        let gate = SamplingGate()
        harness.gate = gate
        model.follow(harness.request(node, radial, [part]))
        model.follow(harness.request(node, .radialGradient(center: .zero, radius: 40), [part]))
        await gate.open()
        await model.waitForSampling()
        let mesh = try #require(harness.meshes[ObjectIdentifier(part)])
        let values = try #require(model.tints[ObjectIdentifier(part)]?.tint.values)
        #expect(values[0] == Float(mesh.positions[0].length / 40), "the second request's field, never the first's")
    }

    @Test func noRequestStopsEverythingAndIsQuietWhenThereWasNothing() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        let idle = model.revision
        model.follow(nil)
        #expect(model.revision == idle, "nothing shown, nothing changed")
        model.follow(harness.request(node, radial, [part]))
        await model.waitForSampling()
        model.follow(nil)
        #expect(model.node == nil && model.tints.isEmpty && model.grid == nil && model.legend == nil && model.choice == .hidden)
        #expect(model.sliceHandle == nil && !model.isSampling && model.revision > idle)
    }

    @Test func aBigMeshIsSampledCoarselyAndTheLegendSaysSo() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model(limit: 4)
        model.follow(harness.request(node, radial, [part]))
        await model.waitForSampling()
        #expect(model.tints[ObjectIdentifier(part)]?.tint.isCoarse == true && model.legend?.isCoarse == true)
    }

    @Test func aFailedSamplingSaysSoInTheKernelsWordsAndKeepsNoTint() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        let bad = Field.distance(.kernel(.faces(FaceSet(solid: part, faces: [FaceID(99)]))), signed: false)
        model.follow(harness.request(node, bad, [part]))
        await model.waitForSampling()
        #expect(model.failure == "A selected face doesn't exist on the solid." && model.tints.isEmpty && model.grid == nil)
        #expect(model.legend?.failure == model.failure && model.legend?.range == nil)
        model.follow(harness.request(node, radial, [part]))
        await model.waitForSampling()
        #expect(model.failure == nil && model.tints.count == 1, "and the next field samples again")
    }

    @Test func aDistanceFieldIsSampledThroughTheEvaluatorsCacheInMillimetres() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let cache = FieldDistanceCache()
        let model = FieldPreviewModel(kernel: FakeKernel(), distances: cache) { solid in harness.meshes[ObjectIdentifier(solid)] }
        model.follow(harness.request(node, .distance(.kernel(.solid(part)), signed: true), [part]))
        await model.waitForSampling()
        #expect(await cache.misses >= 1)
        #expect(model.legend?.unit == .millimetres)
        let range = try #require(model.range)
        #expect(range.mid == 0 && range.low == -range.high, "a signed distance centres the middle on 0")
        let misses = await cache.misses
        model.setUnitRange(true)
        #expect(model.range == .unit && model.tints.count == 1, "the toggle changes the ramp, not the values")
        #expect(await cache.misses == misses)
    }

    // MARK: what the scene gets

    @Test func tintedGivesTheRampToTheSolidsItHasAndLeavesTheRestAlone() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let other = try await harness.part(width: 30)
        let model = harness.model()
        model.follow(harness.request(node, radial, [part]))
        await model.waitForSampling()
        let colors = ColorTheme.dracula.colors
        let items = [
            ViewportItem(solid: part), ViewportItem(solid: part, isGhost: true), ViewportItem(solid: part, isGuide: true),
            ViewportItem(solid: other),
        ]
        let tinted = model.tinted(items, colors: colors)
        #expect(tinted[0].fieldValues == model.tints[ObjectIdentifier(part)]?.tint.values)
        #expect(tinted[0].fieldRamp?.low == colors.fieldLow.rgba && tinted[0].fieldRamp?.high == colors.fieldHigh.rgba)
        #expect(tinted[1].fieldValues == nil && tinted[2].fieldValues == nil && tinted[3].fieldValues == nil)
        let unit = { () -> FieldRamp? in
            model.setUnitRange(true)
            return model.tinted(items, colors: colors)[0].fieldRamp
        }()
        #expect(unit?.lowValue == 0 && unit?.midValue == 0.5 && unit?.highValue == 1)
    }

    @Test func withNothingSampledTheItemsAreHandedBackAsTheyAre() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        #expect(model.tinted([ViewportItem(solid: part)], colors: ColorTheme.dracula.colors)[0].fieldValues == nil)
        #expect(model.viewportSlice(colors: ColorTheme.dracula.colors) == nil)
    }
}
```

Create `Tests/CreatorAppTests/FieldPreview/FieldPreviewSliceTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorStyle
import CreatorViewport
import Testing
@testable import CreatorApp

/// The slice plane's state in the preview model (fields spec §6, "Slice plane"): its start, its toggles and its handle.
@MainActor
struct FieldPreviewSliceTests {
    let node = NodeID()
    let noise = Field.noise(seed: 3, scale: 6, octaves: 1)
    let colors = ColorTheme.dracula.colors

    func following(_ field: Field, toEye: Vector3 = .unitZ) async throws -> (FieldPreviewModel, PreviewHarness, Solid) {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        model.follow(harness.request(node, field, [part], toEye: toEye))
        await model.waitForSampling()
        return (model, harness, part)
    }

    @Test func aNewNodeStartsWithTheSliceShownThroughThePartOnTheAxisPlaneNearestTheCamera() async throws {
        let (model, _, part) = try await following(noise)
        #expect(model.choice == .axis(.xy) && model.offset == 0)
        let slice = try #require(model.viewportSlice(colors: colors))
        #expect(slice.columns == 256 && slice.rows == 256 && slice.isValid)
        #expect(slice.origin == part.bounds.center && slice.opacity == 0.85)
        #expect(model.legend?.choice == .axis(.xy) && !(model.legend?.hasOwnPlane ?? true))
        let side = try await following(noise, toEye: .unitX).0
        #expect(side.choice == .axis(.yz))
    }

    @Test func aFieldThatMeasuresWithTheKernelGetsTheCoarserGrid() async throws {
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        model.follow(harness.request(node, .distance(.kernel(.solid(part)), signed: false), [part]))
        await model.waitForSampling()
        let slice = try #require(model.viewportSlice(colors: colors))
        #expect(slice.columns == 64 && slice.rows == 64 && slice.values.count == 4_096)
    }

    @Test func aGradientsPlaneIsWhereItStartsAndTheLegendCanGoBackToIt() async throws {
        let plane = Plane(origin: Vector3(-10, 0, 0), normal: .unitX, xAxis: .unitY)
        let (model, _, _) = try await following(.linearGradient(plane: plane, length: 20))
        #expect(model.choice == .own && model.hasOwnPlane)
        #expect(model.viewportSlice(colors: colors)?.origin.x == -10, "on the gradient's own plane")
        model.chooseSlice(.axis(.yz))
        await model.waitForSampling()
        #expect(model.choice == .axis(.yz) && model.viewportSlice(colors: colors)?.origin.x == 0)
        model.chooseSlice(.own)
        await model.waitForSampling()
        #expect(model.viewportSlice(colors: colors)?.origin.x == -10)
    }

    @Test func theAxisButtonsResampleOnThePlaneAndHidingTakesTheSliceAndItsHandleAway() async throws {
        let (model, _, part) = try await following(noise)
        let first = try #require(model.viewportSlice(colors: colors))
        model.chooseSlice(.axis(.xz))
        #expect(model.viewportSlice(colors: colors) == nil, "the old quad is for another plane: gone until the new one is ready")
        await model.waitForSampling()
        let second = try #require(model.viewportSlice(colors: colors))
        #expect(abs(second.yAxis.z) == 1 && second.generation != first.generation && second.origin == part.bounds.center)
        model.chooseSlice(.hidden)
        #expect(model.viewportSlice(colors: colors) == nil && model.sliceHandle == nil && model.pose == nil)
        #expect(model.legend?.choice == .hidden)
        await model.waitForSampling()
        #expect(model.viewportSlice(colors: colors) == nil, "and it stays hidden when a sampling finishes")
    }

    @Test func theHandleSitsOnThePlaneAndMovingItMovesAndResamplesTheSlice() async throws {
        let (model, _, _) = try await following(noise)
        let handle = try #require(model.sliceHandle)
        #expect(handle.id == FieldPreviewModel.sliceHandleID && handle.value == 0 && handle.direction == .unitZ)
        #expect(handle.anchor == model.pose?.plane.origin && handle.style == .linear)
        let generation = model.viewportSlice(colors: colors)?.generation
        model.moveSlice(to: 2)
        #expect(model.offset == 2 && model.sliceHandle?.value == 2)
        #expect(model.viewportSlice(colors: colors)?.generation == generation, "the old grid stays until the new one is ready")
        await model.waitForSampling()
        let moved = try #require(model.viewportSlice(colors: colors))
        #expect(moved.generation != generation && abs(moved.origin.z - (model.bounds?.center.z ?? 0) - 2) < 1e-9)
    }

    @Test func movingIsHeldToTheLimitAndIgnoresWhatIsNotANumber() async throws {
        let (model, _, _) = try await following(noise)
        let limit = try #require(model.pose?.offsetLimit)
        model.moveSlice(to: 1_000)
        #expect(model.offset == limit)
        model.moveSlice(to: .nan)
        #expect(model.offset == limit)
        model.moveSlice(to: -1_000)
        #expect(model.offset == -limit)
        await model.waitForSampling()
    }

    @Test func choosingAnAxisPutsTheOffsetBackToZero() async throws {
        let (model, _, _) = try await following(noise)
        model.moveSlice(to: 2)
        model.chooseSlice(.axis(.yz))
        #expect(model.offset == 0)
        model.chooseSlice(.axis(.yz))
        await model.waitForSampling()
    }

    @Test func aBiggerPartRefitsTheSliceKeepingItsChoiceAndOffset() async throws {
        let harness = PreviewHarness()
        let small = try await harness.part()
        let big = try await harness.part(width: 60, depth: 40)
        let model = harness.model()
        model.follow(harness.request(node, noise, [small]))
        await model.waitForSampling()
        model.chooseSlice(.axis(.yz))
        model.moveSlice(to: 1)
        await model.waitForSampling()
        let before = try #require(model.pose)
        model.follow(harness.request(node, noise, [big]))
        await model.waitForSampling()
        let after = try #require(model.pose)
        #expect(after.choice == .axis(.yz) && after.offset == 1 && after.halfWidth > before.halfWidth)
    }

    @Test func aFieldThatLosesItsPlaneLeavesTheOwnChoice() async throws {
        let plane = Plane(origin: .zero, normal: .unitX, xAxis: .unitY)
        let harness = PreviewHarness()
        let part = try await harness.part()
        let model = harness.model()
        model.follow(harness.request(node, .linearGradient(plane: plane, length: 20), [part]))
        await model.waitForSampling()
        #expect(model.choice == .own)
        model.follow(harness.request(node, noise, [part], toEye: .unitZ))
        await model.waitForSampling()
        #expect(model.choice == .axis(.xy), "the same node, but its field has no plane now")
    }

    @Test func aHiddenSliceStaysHiddenWhileTheFieldIsEdited() async throws {
        let (model, harness, part) = try await following(noise)
        model.chooseSlice(.hidden)
        model.follow(harness.request(node, .noise(seed: 4, scale: 6, octaves: 1), [part]))
        await model.waitForSampling()
        #expect(model.choice == .hidden && model.viewportSlice(colors: colors) == nil)
    }

    @Test func anotherNodeStartsOverShownAgain() async throws {
        let (model, harness, part) = try await following(noise)
        model.chooseSlice(.hidden)
        model.follow(harness.request(NodeID(), noise, [part]))
        await model.waitForSampling()
        #expect(model.choice == .axis(.xy))
    }

    @Test func thePartsSliceIsAbsentWithNoPart() async throws {
        let harness = PreviewHarness()
        let model = harness.model()
        model.follow(harness.request(node, noise, []))
        await model.waitForSampling()
        #expect(model.pose == nil && model.sliceHandle == nil && model.viewportSlice(colors: colors) == nil && model.legend == nil)
    }
}
```

Create `Tests/CreatorAppTests/AppFieldPreviewTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorStyle
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// The preview in the window (fields spec §6): a selected field node tints the part and shows the slice and its handle; the
/// legend's state is the model's. What it looks like is a human check (group FI).
@MainActor
struct AppFieldPreviewTests {
    /// A 20 × 10 × 10 box into an Output, a Radial Gradient (radius 10) and a Sample Field wired to the gradient.
    struct Scene {
        var builder = GraphBuilder()
        let box: (rectangle: Node, extrude: Node, output: Node)
        let radial: Node
        let sample: Node

        init() {
            let rectangle = builder.add(RectangleNode.self, ["width": .number(20)])
            let extrude = builder.add(ExtrudeNode.self, ["distance": .number(10)])
            let output = builder.add(OutputNode.self)
            builder.wire(rectangle, "profile", to: extrude, "profile")
            builder.wire(extrude, "solid", to: output, "solid")
            box = (rectangle, extrude, output)
            radial = builder.add(RadialGradientNode.self, ["radius": .number(10)])
            sample = builder.add(SampleFieldNode.self)
            builder.wire(radial, "field", to: sample, "field")
        }
    }

    func open() async -> (AppModel, Scene) {
        let scene = Scene()
        let app = await makeApp(scene.builder.graph)
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        return (app, scene)
    }

    @Test func aSelectedFieldNodeTintsThePartAndShowsTheSliceAndItsHandle() async throws {
        let (app, scene) = await open()
        #expect(app.viewport.items.count == 1 && app.viewport.items[0].fieldValues == nil && app.viewport.slice == nil)
        app.editor.selection = [scene.radial.id]
        await app.settle()
        let item = try #require(app.viewport.items.first)
        let mesh = try #require(app.viewport.displayMesh(of: item.solid))
        #expect(item.fieldValues?.count == mesh.positions.count)
        let colors = app.themes.current.colors
        #expect(item.fieldRamp?.low == colors.fieldLow.rgba && item.fieldRamp?.high == colors.fieldHigh.rgba)
        #expect(app.viewport.slice != nil && app.viewport.slice?.isValid == true)
        #expect(app.viewport.handles.map(\.id) == [FieldPreviewModel.sliceHandleID])
        #expect(app.fieldPreview.legend?.range != nil)
        #expect(app.document.previewNode == scene.radial.id, "the field node is evaluated though nothing downstream is wired")
    }

    @Test func aNodeThatTakesAFieldPreviewsTheOneWiredIntoIt() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.sample.id]
        await app.settle()
        #expect(app.viewport.items.first?.fieldValues != nil && app.viewport.slice != nil)
    }

    @Test func selectingSomethingElseOrNothingTakesThePreviewAway() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.radial.id]
        await app.settle()
        app.editor.selection = [scene.box.extrude.id]
        await app.settle()
        #expect(app.viewport.items.first?.fieldValues == nil && app.viewport.slice == nil)
        #expect(!app.viewport.handles.contains { $0.id == FieldPreviewModel.sliceHandleID }, "the Extrude's own handle remains")
        #expect(app.fieldPreview.legend == nil)
        app.editor.selection = [scene.radial.id]
        await app.settle()
        app.editor.selection = []
        await app.settle()
        #expect(app.viewport.items.first?.fieldValues == nil && app.viewport.slice == nil && app.fieldPreview.node == nil)
    }

    @Test func anEditToTheFieldRetintsThePart() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.radial.id]
        await app.settle()
        let before = try #require(app.viewport.items.first?.fieldValues)
        try app.document.perform(.setInput(scene.radial.id, "radius", .number(20)))
        await app.settle()
        let after = try #require(app.viewport.items.first?.fieldValues)
        #expect(after != before && after.count == before.count)
    }

    @Test func aThemeChangeRecoloursTheTintWithoutSamplingAgain() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.radial.id]
        await app.settle()
        let values = app.viewport.items.first?.fieldValues
        app.themes.select("nord")
        await app.settle()
        #expect(app.viewport.items.first?.fieldRamp?.low == ColorTheme.nord.colors.fieldLow.rgba)
        #expect(app.viewport.items.first?.fieldValues == values)
    }

    @Test func theLegendsToggleChangesTheRampAndTheSliceHandleEditsNoDocument() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.radial.id]
        await app.settle()
        let revision = app.document.undoName
        app.fieldPreview.setUnitRange(true)
        await app.settle()
        #expect(app.viewport.items.first?.fieldRamp?.lowValue == 0 && app.viewport.items.first?.fieldRamp?.highValue == 1)
        app.handleChanged(FieldPreviewModel.sliceHandleID, 2, .changed)
        await app.settle()
        #expect(app.fieldPreview.offset == 2 && app.viewport.handles.first?.value == 2)
        #expect(app.viewport.slice?.origin.z == (app.fieldPreview.bounds?.center.z ?? 0) + 2)
        app.handleChanged(FieldPreviewModel.sliceHandleID, 3, .ended)
        #expect(app.document.undoName == revision && !app.isEdited, "view state: not an edit, not an undo step")
    }

    @Test func theHandleAndTheSliceGoWithTheLegendsHideButton() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.radial.id]
        await app.settle()
        app.fieldPreview.chooseSlice(.hidden)
        await app.settle()
        #expect(app.viewport.slice == nil && app.viewport.handles.isEmpty)
        #expect(app.viewport.items.first?.fieldValues != nil, "the tint stays")
    }

    @Test func aPickInProgressTakesThePreviewAwayAndEndingItBringsItBack() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.radial.id]
        await app.settle()
        let solid = try #require(app.viewport.items.first?.solid)
        let source = try #require(app.producer(of: solid))
        app.pick = PickSession(solid: solid, source: source, rule: nil, consumer: nil, picked: [])
        await app.settle()
        #expect(app.fieldPreview.node == nil && app.viewport.slice == nil)
        #expect(app.viewport.items.allSatisfy { $0.fieldValues == nil })
        app.pick = nil
        await app.settle()
        #expect(app.viewport.items.first?.fieldValues != nil && app.viewport.slice != nil)
    }

    @Test func openingAnotherDocumentStartsThePreviewOver() async throws {
        let (app, scene) = await open()
        app.editor.selection = [scene.radial.id]
        await app.settle()
        app.load(GraphFile(), from: nil)
        await app.settle()
        #expect(app.fieldPreview.node == nil && app.viewport.slice == nil && app.viewport.items.isEmpty)
    }

    @Test func aFieldNodeInSelectedNodeModeWithNoPartHasNothingToTint() async throws {
        let (app, scene) = await open()
        app.previewMode = .selectedNode
        app.editor.selection = [scene.radial.id]
        await app.settle()
        #expect(app.viewport.items.isEmpty && app.viewport.slice == nil && app.fieldPreview.legend == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: FAIL to compile, "cannot find 'FieldPreviewModel' in scope", "value of type 'AppModel' has no member 'fieldPreview'".

- [ ] **Step 3: The model's values**

Create `Sources/CreatorApp/FieldPreview/FieldPreviewRequest.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// What the preview should follow now (`AppModel.fieldPreviewRequest(for:)`): the selected node, the field it shows, the opaque
/// parts the scene holds and the direction the camera looks from (used only to pick the slice's first axis plane).
struct FieldPreviewRequest {
    var node: NodeID
    var field: Field
    var solids: [Solid]
    var toEye: Vector3
}
```

Create `Sources/CreatorApp/FieldPreview/SolidTint.swift`:

```swift
import CreatorKernel

/// A tint and the solid it was sampled on. The solid is held so that its identity (the key the scene looks it up by) can't be
/// taken over by another object while the tint is kept.
struct SolidTint {
    let solid: Solid
    let tint: FieldTint
}
```

Create `Sources/CreatorApp/FieldPreview/SliceGrid.swift`:

```swift
import CreatorViewport

/// A sampled slice: the viewport's quad with its values (its ramp is a placeholder, set when it is shown) and the smallest and
/// largest finite value in it.
struct SliceGrid {
    var slice: ViewportSlice
    var extent: ClosedRange<Double>?
}
```

Create `Sources/CreatorApp/FieldPreview/FieldLegend.swift`:

```swift
import CreatorGraph

/// What the legend draws (fields spec §6): the ramp's range (`nil` before anything is sampled or when no value was a number),
/// the unit of the numbers, the toggles' state, whether the sampling was coarse, and the kernel's words if it failed.
struct FieldLegend: Equatable {
    var range: FieldPreviewRange?
    var unit: FieldUnit
    var isCoarse: Bool
    var usesUnitRange: Bool
    var choice: SliceChoice
    var hasOwnPlane: Bool
    var failure: String?
}
```

- [ ] **Step 4: The model**

Create `Sources/CreatorApp/FieldPreview/FieldPreviewModel.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport
import Observation

/// The field preview (fields spec §6): the tint on the shown parts and the slice plane through them. It follows one field at a
/// time (`follow(_:)`), samples it off the main actor, and keeps the old tint and slice until the new ones are ready. Its
/// toggles and the slice's offset are view state in memory, never saved, never an undo step. `AppModel` feeds it from
/// `refreshScene()` and reads it back into the scene (`FieldPreviewModel+Scene`).
@MainActor
@Observable
final class FieldPreviewModel {
    static let sliceHandleID = "field-slice"

    /// Bumped by every change a view or the scene might draw; `AppModel` observes only this.
    private(set) var revision = 0
    private(set) var node: NodeID?
    private(set) var field: Field?
    private(set) var bounds: BoundingBox?
    /// The legend's "0…1" toggle.
    private(set) var usesUnitRange = false
    /// Where the slice is, and how far along its normal it has been moved.
    private(set) var choice = SliceChoice.hidden
    private(set) var offset = 0.0
    private(set) var tints: [ObjectIdentifier: SolidTint] = [:]
    private(set) var grid: SliceGrid?
    /// The kernel's words when the last sampling failed.
    private(set) var failure: String?
    private var tintRunning = false
    private var sliceRunning = false

    @ObservationIgnored private let kernel: any Kernel
    @ObservationIgnored private let distances: FieldDistanceCache?
    @ObservationIgnored private let vertexLimit: Int
    @ObservationIgnored private let meshes: @MainActor (Solid) async -> DisplayMesh?
    @ObservationIgnored private var solids: [Solid] = []
    @ObservationIgnored private var tintTask: Task<Void, Never>?
    @ObservationIgnored private var sliceTask: Task<Void, Never>?
    @ObservationIgnored private var tintGeneration = 0
    @ObservationIgnored private var sliceGeneration = 0

    /// `meshes` gives a shown solid's display mesh once the viewport has it (its vertices are what the field is sampled at).
    init(kernel: any Kernel, distances: FieldDistanceCache?, vertexLimit: Int = CoarseSampling.vertexLimit,
         meshes: @escaping @MainActor (Solid) async -> DisplayMesh?) {
        self.kernel = kernel
        self.distances = distances
        self.vertexLimit = vertexLimit
        self.meshes = meshes
    }

    /// True while a tint or a slice is being sampled.
    var isSampling: Bool { tintRunning || sliceRunning }

    /// The slice's pose now, or `nil` when it is hidden or there is no part to size it by.
    var pose: SlicePose? {
        guard let field, let bounds else { return nil }
        return SlicePose.pose(for: choice, field: field, bounds: bounds)?.moved(to: offset)
    }

    // MARK: Following

    /// Follows `request`, or stops for `nil`. A request that is the same as the last (the same node and field, the same parts
    /// in the same box) changes nothing; a different one starts a sampling that replaces any under way, and the tint and slice
    /// already shown stay until it publishes. A new node starts its slice over: shown, on the field's own plane or the axis plane
    /// nearest the camera, offset 0.
    func follow(_ request: FieldPreviewRequest?) {
        guard let request else {
            stop()
            return
        }
        let box = Self.bounds(of: request.solids)
        let sameNode = request.node == node
        if sameNode, request.field == field, box == bounds,
           request.solids.map(ObjectIdentifier.init) == solids.map(ObjectIdentifier.init) { return }
        let restartsSlice = !sameNode || (choice == .own && request.field.ownPlane == nil)
        (node, field, solids, bounds, failure) = (request.node, request.field, request.solids, box, nil)
        if restartsSlice {
            choice = SlicePose.startingChoice(for: request.field, toEye: request.toEye)
            offset = 0
            grid = nil
        }
        sampleTints()
        sampleSlice()
        revision += 1
    }

    /// Stops following: cancels any sampling and forgets the field, the tint and the slice. Quiet when there was nothing.
    func stop() {
        guard node != nil || !tints.isEmpty || grid != nil else { return }
        tintTask?.cancel()
        sliceTask?.cancel()
        (tintRunning, sliceRunning) = (false, false)
        (node, field, bounds, solids, failure) = (nil, nil, nil, [], nil)
        (tints, grid, choice, offset) = ([:], nil, .hidden, 0)
        revision += 1
    }

    /// Returns once the sampling under way has finished (or been replaced).
    func waitForSampling() async {
        await tintTask?.value
        await sliceTask?.value
    }

    // MARK: The legend's toggles and the handle

    func setUnitRange(_ on: Bool) {
        guard on != usesUnitRange else { return }
        usesUnitRange = on
        revision += 1
    }

    /// Moves the slice to another plane (or hides it): back to offset 0, the old quad gone until the new grid is ready.
    func chooseSlice(_ new: SliceChoice) {
        guard new != choice, field != nil else { return }
        if new == .own, !hasOwnPlane { return }
        choice = new
        offset = 0
        grid = nil
        sampleSlice()
        revision += 1
    }

    /// Moves the slice along its normal (held to the pose's limit); the old grid stays until the new one is ready.
    func moveSlice(to value: Double) {
        guard let pose else { return }
        let moved = pose.moved(to: value).offset
        guard moved != offset else { return }
        offset = moved
        sampleSlice()
        revision += 1
    }

    // MARK: Sampling

    private func sampleTints() {
        tintTask?.cancel()
        tintGeneration += 1
        let generation = tintGeneration
        guard let field, !solids.isEmpty else {
            tintRunning = false
            tints = [:]
            return
        }
        tintRunning = true
        let (solids, kernel, distances, limit, meshes) = (self.solids, kernel, distances, vertexLimit, meshes)
        tintTask = Task { [weak self] in
            var found: [ObjectIdentifier: SolidTint] = [:]
            do {
                for solid in solids {
                    guard let mesh = await meshes(solid) else { continue }
                    let tint = try await FieldPreviewSampler.tint(of: field, at: mesh.positions, limit: limit, kernel: kernel,
                                                                  cache: distances)
                    found[ObjectIdentifier(solid)] = SolidTint(solid: solid, tint: tint)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.finishTints(generation, found: [:], problem: Self.message(for: error))
                return
            }
            self?.finishTints(generation, found: found, problem: nil)
        }
    }

    private func finishTints(_ generation: Int, found: [ObjectIdentifier: SolidTint], problem: String?) {
        guard generation == tintGeneration else { return }
        tintRunning = false
        tints = found
        if let problem { failure = problem } else if !sliceRunning { failure = nil }
        revision += 1
    }

    private func sampleSlice() {
        sliceTask?.cancel()
        sliceGeneration += 1
        let generation = sliceGeneration
        guard let field, let pose else {
            sliceRunning = false
            grid = nil
            return
        }
        sliceRunning = true
        let plane = pose.worldPlane
        let size = SlicePose.resolution(for: field)
        let geometry = ViewportSlice(origin: plane.origin, xAxis: plane.xAxis, yAxis: plane.yAxis, halfWidth: pose.halfWidth,
                                     halfHeight: pose.halfHeight, columns: size, rows: size, values: [],
                                     ramp: FieldRamp(low: .zero, mid: .zero, high: .zero, range: 0...1), generation: generation)
        let (kernel, distances) = (kernel, distances)
        sliceTask = Task { [weak self] in
            do {
                let sampled = try await FieldPreviewSampler.gridValues(of: field, in: geometry, kernel: kernel, cache: distances)
                var slice = geometry
                slice.values = sampled.values
                self?.finishSlice(generation, grid: SliceGrid(slice: slice, extent: sampled.extent), problem: nil)
            } catch is CancellationError {
                return
            } catch {
                self?.finishSlice(generation, grid: nil, problem: Self.message(for: error))
            }
        }
    }

    private func finishSlice(_ generation: Int, grid: SliceGrid?, problem: String?) {
        guard generation == sliceGeneration else { return }
        sliceRunning = false
        self.grid = grid
        if let problem { failure = problem } else if !tintRunning { failure = nil }
        revision += 1
    }

    /// The box round the solids, or `nil` for none.
    static func bounds(of solids: [Solid]) -> BoundingBox? {
        solids.dropFirst().reduce(solids.first?.bounds) { $0?.union($1.bounds) }
    }

    /// A sampling failure in words: the kernel's own, a node error's, or a plain sentence.
    private static func message(for error: any Error) -> String {
        if let kernel = error as? KernelError { return kernel.userMessage }
        if let node = error as? NodeError { return node.message }
        return "The field couldn't be sampled."
    }
}
```

Create `Sources/CreatorApp/FieldPreview/FieldPreviewModel+Scene.swift`:

```swift
import CreatorGraph
import CreatorStyle
import CreatorViewport

extension FieldPreviewModel {
    /// Whether the followed field has a plane of its own for the slice to lie on.
    var hasOwnPlane: Bool { field?.ownPlane != nil }

    /// The smallest to the largest finite value sampled on the parts and, while it is shown, on the slice.
    var extent: ClosedRange<Double>? {
        var extents = tints.values.compactMap(\.tint.extent)
        if choice != .hidden, let slice = grid?.extent { extents.append(slice) }
        guard let low = extents.map(\.lowerBound).min(), let high = extents.map(\.upperBound).max() else { return nil }
        return low...high
    }

    /// The ramp's range for what is sampled: automatic, centred on 0 for a signed distance, or fixed to 0…1.
    var range: FieldPreviewRange? {
        guard let field else { return nil }
        return FieldPreviewRange.make(extent: extent, centredOnZero: field.isSignedDistance, fixedToUnit: usesUnitRange)
    }

    /// What the legend draws, or `nil` while there is nothing to show (nothing followed, or nothing sampled yet).
    var legend: FieldLegend? {
        guard node != nil, let field, range != nil || failure != nil else { return nil }
        return FieldLegend(range: range, unit: field.unit, isCoarse: tints.values.contains { $0.tint.isCoarse },
                           usesUnitRange: usesUnitRange, choice: choice, hasOwnPlane: hasOwnPlane, failure: failure)
    }

    /// `items` with the tint on each opaque, non-guide item the model has sampled; the others as they are.
    func tinted(_ items: [ViewportItem], colors: ThemeColors) -> [ViewportItem] {
        guard !tints.isEmpty, let ramp = range?.ramp(colors: colors) else { return items }
        return items.map { item in
            guard !item.isGhost, !item.isGuide, let entry = tints[ObjectIdentifier(item.solid)] else { return item }
            var tinted = item
            tinted.fieldValues = entry.tint.values
            tinted.fieldRamp = ramp
            return tinted
        }
    }

    /// The slice for the viewport in the theme's ramp, or `nil` while it is hidden or not yet sampled.
    func viewportSlice(colors: ThemeColors) -> ViewportSlice? {
        guard choice != .hidden, var slice = grid?.slice, let ramp = range?.ramp(colors: colors) else { return nil }
        slice.ramp = ramp
        return slice
    }

    /// The handle that moves the slice along its normal, from the plane at offset 0.
    var sliceHandle: ViewportHandle? {
        guard let pose else { return nil }
        return ViewportHandle(id: Self.sliceHandleID, anchor: pose.plane.origin, direction: pose.plane.normal, value: offset,
                              range: -pose.offsetLimit...pose.offsetLimit, style: .linear, tint: .solid)
    }
}
```

- [ ] **Step 5: Wire it into the app**

Edit `Sources/CreatorGraph/DocumentModel.swift`:

```swift-old
    /// The registry carrying this document's definitions, so group nodes have their sockets.
    public var registry: NodeRegistry { baseRegistry.withGroups(content.definitions) }
```

```swift-new
    /// The registry carrying this document's definitions, so group nodes have their sockets.
    public var registry: NodeRegistry { baseRegistry.withGroups(content.definitions) }
    /// The evaluator's cache of kernel distances for fields (fields spec §2.2), shared with the field preview so a tint reuses
    /// the distances a node measured.
    public var fieldDistances: FieldDistanceCache { evaluator.fieldDistances }
```

Create `Sources/CreatorApp/AppModel+FieldPreview.swift`:

```swift
import CreatorGraph
import CreatorKernel
import CreatorViewport

extension AppModel {
    /// A preview of the field of the one node selected in the level shown, over the opaque parts of `scene`, or `nil`: while
    /// picking or sketching, with no node or several selected, or when the node has no field to show
    /// (`FieldPreviewSelection`). The slice starts from the camera's view direction at the moment a new node is selected.
    func fieldPreviewRequest(for scene: [SceneItem]) -> FieldPreviewRequest? {
        guard pick == nil, sketch == nil, editor.selection.count == 1, let id = editor.selection.first,
              let node = editor.graph.nodes[id],
              let field = FieldPreviewSelection.field(of: node, graph: editor.graph, results: editor.levelResults,
                                                      registry: registry) else { return nil }
        var seen = Set<ObjectIdentifier>()
        let solids = scene.map(\.item).filter { !$0.isGhost && !$0.isGuide }.map(\.solid)
            .filter { seen.insert(ObjectIdentifier($0)).inserted }
        return FieldPreviewRequest(node: id, field: field, solids: solids, toEye: viewport.pose.toEye)
    }

    /// A preview model for a document's parts: it samples through the evaluator's distance cache and reads a solid's vertices
    /// from the viewport once it has meshed the scene.
    static func makeFieldPreview(kernel: any Kernel, parts: DocumentParts) -> FieldPreviewModel {
        let viewport = parts.viewport
        return FieldPreviewModel(kernel: kernel, distances: parts.document.fieldDistances) { solid in
            await viewport.waitForMeshes()
            return viewport.displayMesh(of: solid)
        }
    }
}
```

Edit `Sources/CreatorApp/AppModel.swift`:

```swift-old
    public private(set) var viewport: ViewportModel
    /// Where the document was last opened from or saved to; `nil` for a new one.
```

```swift-new
    public private(set) var viewport: ViewportModel
    /// The field preview of the selected node (fields spec §6): the tint on the shown parts and the slice through them. It
    /// belongs to the open document and is replaced with it; its toggles are view state, never saved.
    private(set) var fieldPreview: FieldPreviewModel
    /// Where the document was last opened from or saved to; `nil` for a new one.
```

Edit `Sources/CreatorApp/AppModel.swift`:

```swift-old
        graphInput = parts.input
        viewport = parts.viewport
        self.fileURL = fileURL
```

```swift-new
        graphInput = parts.input
        viewport = parts.viewport
        fieldPreview = Self.makeFieldPreview(kernel: kernel, parts: parts)
        self.fileURL = fileURL
```

Edit `Sources/CreatorApp/AppModel.swift`:

```swift-old
        previewMode = .final
        document = parts.document
        editor = parts.editor
        graphInput = parts.input
        viewport = parts.viewport
        fileURL = url
```

```swift-new
        previewMode = .final
        fieldPreview.stop()
        document = parts.document
        editor = parts.editor
        graphInput = parts.input
        viewport = parts.viewport
        fieldPreview = Self.makeFieldPreview(kernel: kernel, parts: parts)
        fileURL = url
```

Edit `Sources/CreatorApp/AppModel.swift`:

```swift-old
            await document.waitForEvaluation()
            if let sceneTask { await sceneTask.value }
        } while document.isEvaluating || sceneTask != nil
```

```swift-new
            await document.waitForEvaluation()
            if let sceneTask { await sceneTask.value }
            await fieldPreview.waitForSampling()
        } while document.isEvaluating || sceneTask != nil || fieldPreview.isSampling
```

Edit `Sources/CreatorApp/AppModel+Scene.swift`:

```swift-old
    /// "Selected node" previews the one selected node of the level shown; Final, or anything but one selected node, previews none,
    /// except that a selected layout node is always evaluated (Final preview shows its placements as an overlay,
    /// `layoutOverlay`, even before anything is wired to it).
```

```swift-new
    /// "Selected node" previews the one selected node of the level shown; Final, or anything but one selected node, previews none,
    /// except that a selected layout node is always evaluated (Final preview shows its placements as an overlay,
    /// `layoutOverlay`, even before anything is wired to it), and so is a selected Fields node (its field tints the part and
    /// lights the slice, `fieldPreview`).
```

Edit `Sources/CreatorApp/AppModel+Scene.swift`:

```swift-old
            wanted = previewMode == .selectedNode || isLayout ? selected : nil
```

```swift-new
            let isField = editor.graph.nodes[selected].map { FieldPreviewSelection.previews($0, registry: registry) } ?? false
            wanted = previewMode == .selectedNode || isLayout || isField ? selected : nil
```

Edit `Sources/CreatorApp/AppModel+Scene.swift`:

```swift-old
        let items = scene.map(\.item)
        if !ViewportItem.sameScene(items, requestedScene) {
```

```swift-new
        fieldPreview.follow(fieldPreviewRequest(for: scene))
        let items = fieldPreview.tinted(scene.map(\.item), colors: themes.current.colors)
        if !ViewportItem.sameScene(items, requestedScene) {
```

Edit `Sources/CreatorApp/AppModel+Scene.swift`:

```swift-old
        if sketch == nil { viewport.showOverlay(pick == nil ? layoutOverlay : ViewportOverlay()) }
```

```swift-new
        if sketch == nil { viewport.showOverlay(pick == nil ? layoutOverlay : ViewportOverlay()) }
        viewport.showSlice(fieldPreview.viewportSlice(colors: themes.current.colors))
```

Edit `Sources/CreatorApp/AppModel+Scene.swift`:

```swift-old
        let shownHandles = handles.map(\.handle)
```

```swift-new
        let shownHandles = handles.map(\.handle) + (fieldPreview.sliceHandle.map { [$0] } ?? [])
```

Edit `Sources/CreatorApp/AppModel+Scene.swift`:

```swift-old
            _ = document.previewNode
            _ = editor.selection
```

```swift-new
            _ = document.previewNode
            _ = fieldPreview.revision
            _ = editor.selection
```

Edit `Sources/CreatorApp/AppModel+Viewport.swift`:

```swift-old
    func handleChanged(_ id: String, _ value: Double, _ phase: HandleDragPhase) {
        guard let target = handleTargets[id] else { return }
```

```swift-new
    func handleChanged(_ id: String, _ value: Double, _ phase: HandleDragPhase) {
        // The field slice's handle moves view state, not the document: no command, no undo step, nothing to save.
        if id == FieldPreviewModel.sliceHandleID {
            fieldPreview.moveSlice(to: value)
            return
        }
        guard let target = handleTargets[id] else { return }
```

Edit `Sources/CreatorApp/ViewportItem+Comparison.swift`:

```swift-old
    /// True when `other` draws the same thing: the very same solid, ghosted alike, a guide alike, with the same faces and edges
    /// selected. `AppModel` re-shows the scene only when an item differs, so a canvas pan, a settled camera or a
    /// panel resize doesn't restart the viewport's mesh load (M4 carry-over: nothing rebuilds at 60 Hz).
    func drawsTheSame(as other: ViewportItem) -> Bool {
        solid === other.solid && isGhost == other.isGhost && isGuide == other.isGuide && selectedFaces == other.selectedFaces
            && selectedEdges == other.selectedEdges
    }
```

```swift-new
    /// True when `other` draws the same thing: the very same solid, ghosted alike, a guide alike, with the same faces and edges
    /// selected and the same field tint (arrays sharing storage compare in no time). `AppModel` re-shows the scene only when an
    /// item differs, so a canvas pan, a settled camera or a panel resize doesn't restart the viewport's mesh load (M4 carry-over:
    /// nothing rebuilds at 60 Hz).
    func drawsTheSame(as other: ViewportItem) -> Bool {
        solid === other.solid && isGhost == other.isGhost && isGuide == other.isGuide && selectedFaces == other.selectedFaces
            && selectedEdges == other.selectedEdges && fieldValues == other.fieldValues && fieldRamp == other.fieldRamp
    }
```

- [ ] **Step 6: Run the tests**

Run: `swift test --filter 'FieldPreviewModelTests|FieldPreviewSliceTests|AppFieldPreviewTests|LayoutPreviewTests|SceneTests|HandleTests|PickingTests|AppModelFileTests' 2>&1 | grep -E "recorded|failed|Test run" | head -20`
Expected: PASS.

- [ ] **Step 7: Lint and run the whole suite**

Run `swiftlint lint --strict` (zero violations) and the full `swift test` (background, to a log), judged by the rule in Global Constraints.
Expected: master + 156 tests (3,629).

- [ ] **Step 8: Commit**

```bash
git add Sources Tests
git commit -m "feat: a selected field node tints the part and lights the slice plane (7b-3)"
```
### Task 9: The legend

**Files:**
- Modify: `Sources/CreatorStyle/GlassSurface.swift`, `Tests/CreatorStyleTests/GlassStyleTests.swift`
- Create: `Sources/CreatorApp/FieldPreview/FieldLegend+Labels.swift`, `Sources/CreatorApp/FieldLegendView.swift`, `Sources/CreatorApp/FieldLegendDock.swift`
- Modify: `Sources/CreatorApp/AppLayout.swift`, `Sources/CreatorApp/AppRoot.swift`
- Test: `Tests/CreatorAppTests/FieldPreview/FieldLegendLabelsTests.swift`, `Tests/CreatorAppTests/FieldLegendWindowTests.swift`, `Tests/CreatorAppTests/FieldLegendLayoutTests.swift`

**Interfaces:**
- Consumes: `FieldLegend`, `FieldPreviewModel.legend`, `chooseSlice(_:)`, `setUnitRange(_:)` (Task 8), `GlassPanel`, `Palette`, `ThemeStore`, `Locale.messages`.
- Produces: `GlassSurface.fieldLegend` (`ultraThin`, like the other persistent panels); `FieldLegend.Labels` / `.labels`, `.sliceOptions`, `.selectedOption`, `.notes`; `FieldLegendView`, `FieldLegendDock`; `AppLayout.legendInsets(dock:panelWidth:panelHeight:)`.

**Spec §6, "Ramp and legend".** The legend is a small glass card at the viewport's lower left: the ramp, min, mid and max with units where the field has them (mm for distances), the toggles, and "Preview sampled coarsely" when D14 applies. The axis triad already lives at the viewport's lower left (`TriadLayout`: 16 pt from the model area's left and bottom edges, 64 pt square), so the card sits **above the triad**, clear of the docked graph panel (`AppLayout.legendInsets`: the model area's leading and bottom insets plus the triad's room). **Look: user decision 3.** The card shows nothing until a field has been sampled (`FieldPreviewModel.legend` is `nil`), and goes with the selection. Its three numbers are written with three significant digits at most and `Locale.messages` ("1,230", "0.5", "-12.3 mm"; never "-0"). Its controls are MetalUI's `Toggle` for "0…1" and a segmented `Picker` for the slice: Plane (only when the field has a plane of its own), XY, YZ, XZ and Off. The ramp bar is a MetalUI `LinearGradient` of the theme's three field roles (`fieldLow`, `fieldMid`, `fieldHigh`). A failed sampling replaces the numbers with the kernel's words. If MetalUI can't draw any of this, that is a gap for `docs/metalui-gaps.md`, never a workaround; this task found none (the plan was checked by building it).

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorAppTests/FieldPreview/FieldLegendLabelsTests.swift`:

```swift
import CreatorGraph
import Testing
@testable import CreatorApp

/// The words and options on the legend (fields spec §6).
struct FieldLegendLabelsTests {
    func legend(_ range: FieldPreviewRange? = FieldPreviewRange(low: 0, mid: 0.5, high: 1), unit: FieldUnit = .none,
                choice: SliceChoice = .axis(.xy), hasOwnPlane: Bool = false, isCoarse: Bool = false,
                failure: String? = nil) -> FieldLegend {
        FieldLegend(range: range, unit: unit, isCoarse: isCoarse, usesUnitRange: false, choice: choice, hasOwnPlane: hasOwnPlane,
                    failure: failure)
    }

    @Test func numbersHaveAtMostThreeSignificantDigitsAndTheMessageLocale() {
        #expect(FieldLegend.text(0.5, unit: .none) == "0.5")
        #expect(FieldLegend.text(1234.5678, unit: .none) == "1,230")
        #expect(FieldLegend.text(12.3456, unit: .none) == "12.3")
        #expect(FieldLegend.text(0.000_123_4, unit: .none) == "0.000123")
        #expect(FieldLegend.text(10, unit: .none) == "10")
    }

    @Test func zeroIsNeverMinusZeroAndMillimetresAreSaid() {
        #expect(FieldLegend.text(-0.0, unit: .none) == "0" && FieldLegend.text(0, unit: .millimetres) == "0 mm")
        #expect(FieldLegend.text(-12.34, unit: .millimetres) == "-12.3 mm")
    }

    @Test func theThreeLabelsAreTheRangesEndsAndMiddle() {
        let labels = legend(FieldPreviewRange(low: -14.5, mid: 0, high: 14.5), unit: .millimetres).labels
        #expect(labels == FieldLegend.Labels(low: "-14.5 mm", mid: "0 mm", high: "14.5 mm"))
        #expect(legend(nil).labels == nil)
    }

    @Test func theSliceButtonsAreThePlaneWhenTheFieldHasOneThenTheAxesThenOff() {
        #expect(legend().sliceOptions.map(\.title) == ["XY", "YZ", "XZ", "Off"])
        #expect(legend(hasOwnPlane: true).sliceOptions.map(\.title) == ["Plane", "XY", "YZ", "XZ", "Off"])
        #expect(legend(hasOwnPlane: true).sliceOptions.map(\.choice) == [.own, .axis(.xy), .axis(.yz), .axis(.xz), .hidden])
    }

    @Test func theSelectedButtonIsTheOneTheChoiceNames() {
        #expect(legend(choice: .axis(.yz)).selectedOption == 1)
        #expect(legend(choice: .axis(.yz), hasOwnPlane: true).selectedOption == 2)
        #expect(legend(choice: .hidden).selectedOption == 3)
        #expect(legend(choice: .own, hasOwnPlane: true).selectedOption == 0)
        #expect(legend(choice: .own).selectedOption == nil, "no plane of its own: nothing to select")
    }

    @Test func theNotesAreTheCoarseWarningAndTheKernelsWords() {
        #expect(legend().notes.isEmpty)
        #expect(legend(isCoarse: true).notes == ["Preview sampled coarsely"])
        #expect(legend(failure: "A selected face doesn't exist on the solid.").notes == ["A selected face doesn't exist on the solid."])
        #expect(legend(isCoarse: true, failure: "No.").notes == ["No.", "Preview sampled coarsely"])
    }
}
```

Create `Tests/CreatorAppTests/FieldLegendLayoutTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorApp
@testable import CreatorViewport

/// Where the legend stands (fields spec §6): above the axis triad, clear of the docked graph panel.
@MainActor
struct FieldLegendLayoutTests {
    let aboveTheTriad = 16 + TriadLayout().side + 12

    @Test func leftDockedItStandsRightOfThePanelAboveTheTriad() {
        let area = AppLayout.modelArea(dock: .left, panelWidth: 460, panelHeight: 300)
        let insets = AppLayout.legendInsets(dock: .left, panelWidth: 460, panelHeight: 300)
        #expect(insets.leading == area.leading + 16 && insets.bottom == area.bottom + aboveTheTriad)
        #expect(insets.top == 0 && insets.trailing == 0)
    }

    @Test func bottomDockedItStandsAboveThePanel() {
        let area = AppLayout.modelArea(dock: .bottom, panelWidth: 460, panelHeight: 300)
        let insets = AppLayout.legendInsets(dock: .bottom, panelWidth: 460, panelHeight: 300)
        #expect(insets.leading == 16 && insets.bottom == area.bottom + aboveTheTriad)
        #expect(insets.bottom > 300 + aboveTheTriad)
    }

    @Test func withThePanelHiddenItClearsTheShowButton() {
        let area = AppLayout.modelArea(dock: .hidden, panelWidth: 460, panelHeight: 300)
        #expect(AppLayout.legendInsets(dock: .hidden, panelWidth: 460, panelHeight: 300).bottom == area.bottom + aboveTheTriad)
    }

    @Test func theTriadIsWhereTheLegendThinksItIs() async throws {
        let app = await makeApp()
        app.viewport.recordViewSize(ViewportSize(width: 1400, height: 900))
        app.viewport.setModelArea(AppLayout.modelArea(dock: .left, panelWidth: 460, panelHeight: 300))
        let triad = app.viewport.triadLayout
        let insets = AppLayout.legendInsets(dock: .left, panelWidth: 460, panelHeight: 300)
        #expect(triad.leading == insets.leading && triad.bottom + triad.side + 12 == insets.bottom)
    }
}
```

Create `Tests/CreatorAppTests/FieldLegendWindowTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorNodes
import MetalUI
import MetalUITesting
import Testing
@testable import CreatorApp

/// The legend in the app's real window (fields spec §6): it appears with a sampled field, its buttons reach the model, and it
/// goes with the selection. How it looks is a human check (group FI).
@MainActor
struct FieldLegendWindowTests {
    /// A 20 × 10 × 10 box into an Output beside a Radial Gradient (radius 10).
    func open() async throws -> (AppWindow, Node) {
        var builder = GraphBuilder()
        let rectangle = builder.add(RectangleNode.self, ["width": .number(20)])
        let extrude = builder.add(ExtrudeNode.self, ["distance": .number(10)])
        let output = builder.add(OutputNode.self)
        let radial = builder.add(RadialGradientNode.self, ["radius": .number(10)])
        builder.wire(rectangle, "profile", to: extrude, "profile")
        builder.wire(extrude, "solid", to: output, "solid")
        return (try await AppWindow.open(builder.graph), radial)
    }

    func select(_ node: Node?, in app: AppWindow) async throws {
        app.model.editor.selection = node.map { [$0.id] } ?? []
        await app.model.settle()
        try await app.window.runUntilIdle()
    }

    /// The one control (not its text) the window labels `label`.
    func control(_ label: String, in app: AppWindow) throws -> TestElement {
        let found = try app.window.elements { $0.label == label && $0.role != .staticText }
        return try #require(found.count == 1 ? found.first : nil, "\(found.count) controls are labelled \(label)")
    }

    func controls(_ label: String, in app: AppWindow) throws -> Int {
        try app.window.elements { $0.label == label && $0.role != .staticText }.count
    }

    @Test func noLegendWithoutAFieldPreview() async throws {
        let (app, _) = try await open()
        #expect(app.model.fieldPreview.legend == nil)
        #expect(try controls("XZ", in: app) == 0 && controls("0…1", in: app) == 0)
    }

    @Test func aSelectedFieldNodeShowsTheLegendWithItsNumbersAndButtons() async throws {
        let (app, radial) = try await open()
        try await select(radial, in: app)
        let legend = try #require(app.model.fieldPreview.legend)
        let labels = try #require(legend.labels)
        for text in [labels.low, labels.high] {
            #expect(try app.window.elements { $0.label == text || $0.value == text }.count >= 1, "the number \(text)")
        }
        for title in ["XY", "YZ", "XZ", "Off", "0…1"] {
            _ = try control(title, in: app)
        }
        #expect(try controls("Plane", in: app) == 0, "a radial gradient has no plane of its own")
        #expect(try control("XY", in: app).isSelected, "the slice starts on the axis plane nearest the camera")
    }

    @Test func thePicksReachTheModel() async throws {
        let (app, radial) = try await open()
        try await select(radial, in: app)
        try app.window.click(try control("YZ", in: app))
        await app.model.settle()
        #expect(app.model.fieldPreview.choice == .axis(.yz))
        try app.window.click(try control("Off", in: app))
        await app.model.settle()
        #expect(app.model.fieldPreview.choice == .hidden && app.model.viewport.slice == nil)
        try app.window.click(try control("0…1", in: app))
        await app.model.settle()
        #expect(app.model.fieldPreview.usesUnitRange && app.model.fieldPreview.legend?.labels?.mid == "0.5")
    }

    @Test func theLegendGoesWhenTheSelectionDoes() async throws {
        let (app, radial) = try await open()
        try await select(radial, in: app)
        _ = try control("YZ", in: app)
        try await select(nil, in: app)
        #expect(try controls("YZ", in: app) == 0)
    }

    @Test func theCardStandsAboveTheTriadAndRightOfTheLeftDockedPanel() async throws {
        var builder = GraphBuilder()
        let radial = builder.add(RadialGradientNode.self)
        let box = builder.box()
        _ = box
        let app = try await AppWindow.open(builder.graph, dock: .left)
        try await select(radial, in: app)
        let slice = try #require(try app.window.elements(role: .radioGroup).first { $0.label == "Slice" })
        let insets = AppLayout.legendInsets(dock: .left, panelWidth: app.model.panelWidth, panelHeight: app.model.panelHeight)
        let (left, bottom) = (Double(slice.frame.origin.x.value), Double(slice.frame.origin.y.value + slice.frame.size.height.value))
        #expect(left >= insets.leading, "right of the panel: \(left) against \(insets.leading)")
        #expect(bottom <= app.size.y - insets.bottom, "above the triad: \(bottom) against \(app.size.y - insets.bottom)")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: FAIL to compile, "type 'FieldLegend' has no member 'text'", "cannot find 'FieldLegendView'" is not yet referenced; "type 'AppLayout' has no member 'legendInsets'".

- [ ] **Step 3: The legend's words and options**

Edit `Sources/CreatorStyle/GlassSurface.swift`:

```swift-old
    /// The sketch editor's small readout and inference chips.
    case chip
```

```swift-new
    /// The sketch editor's small readout and inference chips.
    case chip
    /// The field preview's legend (fields spec §6): a small persistent card at the viewport's lower left.
    case fieldLegend
```

Edit `Sources/CreatorStyle/GlassSurface.swift`:

```swift-old
        case .graphPanel, .inspector, .topBar, .pickBanner, .showButton, .themeEditor, .chip: .ultraThin
```

```swift-new
        case .graphPanel, .inspector, .topBar, .pickBanner, .showButton, .themeEditor, .chip, .fieldLegend: .ultraThin
```

Edit `Tests/CreatorStyleTests/GlassStyleTests.swift`:

```swift-old
            .showButton: .ultraThin, .palette: .thin, .themeEditor: .ultraThin, .chip: .ultraThin,
```

```swift-new
            .showButton: .ultraThin, .palette: .thin, .themeEditor: .ultraThin, .chip: .ultraThin, .fieldLegend: .ultraThin,
```

Create `Sources/CreatorApp/FieldPreview/FieldLegend+Labels.swift`:

```swift
import CreatorGraph
import CreatorKernel
import Foundation

extension FieldLegend {
    /// The numbers under the ramp: its low end, its middle and its high end.
    struct Labels: Equatable {
        var low: String
        var mid: String
        var high: String
    }

    /// One of the slice buttons.
    struct SliceOption: Equatable {
        var title: String
        var choice: SliceChoice
    }

    /// The ramp's three numbers, or `nil` before there is a range.
    var labels: Labels? {
        range.map { Labels(low: Self.text($0.low, unit: unit), mid: Self.text($0.mid, unit: unit), high: Self.text($0.high, unit: unit)) }
    }

    /// The slice buttons: Plane when the field has a plane of its own, the three axis planes, and Off.
    var sliceOptions: [SliceOption] {
        (hasOwnPlane ? [SliceOption(title: "Plane", choice: .own)] : [])
            + SliceAxis.allCases.map { SliceOption(title: $0.title, choice: .axis($0)) } + [SliceOption(title: "Off", choice: .hidden)]
    }

    /// The index in `sliceOptions` of the button the slice's choice names, or `nil` for none.
    var selectedOption: Int? { sliceOptions.firstIndex { $0.choice == choice } }

    /// The lines under the numbers: what went wrong, then the coarse-sampling notice (D14).
    var notes: [String] {
        (failure.map { [$0] } ?? []) + (isCoarse ? ["Preview sampled coarsely"] : [])
    }

    /// `value` with at most three significant digits in the message locale, "mm" after it for a distance, and never "-0".
    static func text(_ value: Double, unit: FieldUnit) -> String {
        let number = (value == 0 ? 0 : value).formatted(.number.precision(.significantDigits(1...3)).locale(.messages))
        return unit == .millimetres ? "\(number) mm" : number
    }
}
```

- [ ] **Step 4: The card and where it stands**

Edit `Sources/CreatorApp/AppLayout.swift`:

```swift-old
    /// The part of the viewport the panels leave uncovered, for `ViewportModel.setModelArea(_:)`.
```

```swift-new
    /// The field legend's room (fields spec §6): it stands at the model area's lower left like the axis triad, one gap above it
    /// (the triad is 16 points from the model area's edges and 64 points square), so its left and bottom are the model
    /// area's plus those. The top and trailing insets are 0.
    public static func legendInsets(dock: DockSide, panelWidth: Double, panelHeight: Double) -> ViewportInsets {
        let area = modelArea(dock: dock, panelWidth: panelWidth, panelHeight: panelHeight)
        return ViewportInsets(top: 0, leading: area.leading + 16, bottom: area.bottom + 16 + TriadLayout().side + 12, trailing: 0)
    }

    /// The part of the viewport the panels leave uncovered, for `ViewportModel.setModelArea(_:)`.
```

Create `Sources/CreatorApp/FieldLegendView.swift`:

```swift
import CreatorEditor
import CreatorStyle
import MetalUI

/// The field preview's legend (fields spec §6): the ramp as a bar of the theme's three field roles, its low, middle and high
/// numbers (with "mm" for a distance), a note when the sampling was coarse or failed, the "0…1" toggle and the slice buttons.
/// All behaviour is `FieldPreviewModel`'s; this only draws its `FieldLegend`.
struct FieldLegendView: Component {
    let model: AppModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    /// The card's inner width in points.
    static let width = 220.0

    var content: some ElementGroup {
        if let legend = model.fieldPreview.legend {
            GlassPanel(.fieldLegend) {
                VStack(alignment: .leading, spacing: Pixels(6)) {
                    if let labels = legend.labels {
                        ramp
                        HStack(spacing: Pixels(0)) {
                            Text(labels.low)
                            Spacer()
                            Text(labels.mid)
                            Spacer()
                            Text(labels.high)
                        }
                        .font(.caption)
                        .foregroundStyle(Palette(themes).primaryText.color)
                    }
                    ForEach(legend.notes, id: \.self) { note in
                        Text(note)
                            .font(.caption)
                            .foregroundStyle((legend.failure == nil ? Palette(themes).statusWarning : Palette(themes).statusError).color)
                    }
                    Toggle("0…1", isOn: Binding(get: { legend.usesUnitRange }, set: { model.fieldPreview.setUnitRange($0) }))
                    Picker("Slice", selection: Binding(get: { legend.selectedOption ?? -1 }, set: { index in
                        if legend.sliceOptions.indices.contains(index) { model.fieldPreview.chooseSlice(legend.sliceOptions[index].choice) }
                    })) {
                        ForEach(legend.sliceOptions.indices, id: \.self) { index in
                            Text(legend.sliceOptions[index].title).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(width: Self.width.px)
            }
        }
    }

    /// The ramp: low, middle and high in the theme's field roles, left to right.
    private var ramp: some ElementGroup {
        let colors = (themes?.current ?? .dracula).colors
        return LinearGradient(colors: [colors.fieldLow.color, colors.fieldMid.color, colors.fieldHigh.color],
                              startPoint: .leading, endPoint: .trailing)
            .frame(width: Self.width.px, height: Pixels(10))
            .clipShape(RoundedRectangle(cornerRadius: Pixels(3)))
    }
}
```

Create `Sources/CreatorApp/FieldLegendDock.swift`:

```swift
import MetalUI

/// Puts the legend at the viewport's lower left, above the axis triad and clear of the docked graph panel
/// (`AppLayout.legendInsets`). It fills the window so the card can stand in a corner; only the card itself is drawn.
struct FieldLegendDock: Component {
    let model: AppModel

    var content: some ElementGroup {
        let insets = AppLayout.legendInsets(dock: model.editor.dock, panelWidth: model.panelWidth, panelHeight: model.panelHeight)
        VStack(alignment: .leading, spacing: Pixels(0)) {
            Spacer()
            HStack(spacing: Pixels(0)) {
                FieldLegendView(model: model)
                Spacer()
            }
        }
        .padding(Edges(top: Pixels(0), right: Pixels(0), bottom: insets.bottom.px, left: insets.leading.px))
    }
}
```

Edit `Sources/CreatorApp/AppRoot.swift`:

```swift-old
            if let session = model.sketch { PointerReadoutView(model: session.editor) }
```

```swift-new
            if let session = model.sketch { PointerReadoutView(model: session.editor) }
            FieldLegendDock(model: model)
```

- [ ] **Step 5: Run the tests**

Run: `swift test --filter 'FieldLegend|GlassStyleTests|GlassFillTests|AppRootRenderTests|AppWindowTests' 2>&1 | grep -E "recorded|failed|Test run" | head -20`
Expected: PASS.

- [ ] **Step 6: Lint and run the whole suite**

Run `swiftlint lint --strict` (zero violations) and the full `swift test` (background, to a log), judged by the rule in Global Constraints.
Expected: master + 171 tests (3,644).

- [ ] **Step 7: Commit**

```bash
git add Sources Tests
git commit -m "feat: the field preview's legend: ramp, numbers, toggles and slice buttons (7b-3)"
```
### Task 10: The acceptance test, headless on OCCT

**Files:**
- Test: `Tests/CreatorNodesTests/FieldsAcceptanceTests.swift`

**Interfaces:**
- Consumes: Field Scatter (Task 3) and 7b-1's Distance Field, Remap, Noise Field, Sample Field, Cull by Field, Hole Pattern, `Harness`.
- Produces: nothing a later task uses; this is spec §8's acceptance test, the check that the pieces work as one part.

**The part (fields spec §8).** A vented plate: a 60 × 40 × 6 plate (top on z = 0). Field Scatter fills its top face with points whose spacing follows a distance field (denser near the edges); a second remap of the same distance gives each point a hole size (larger towards the centre), wired the way that wires, field → Remap → Sample Field → Hole Pattern (fields spec Errata (7b-1)); Cull by Field (Probability, a noise field) thins the points first, so the sizes are sampled at the survivors, and Hole Pattern pairs them with the survivors by `InstanceGrid`. The test asserts the instance count (pinned), that every hole's size follows its distance to the plate's edge and so grows towards the centre, that the removed volume is the holes' volume (so the holes were cut at those sizes), that the scatter is denser near the edges than in the middle, and that a second run, from a fresh kernel and fresh node IDs, gives exactly the same points, sizes and volume. The part also exports as STEP.

- [ ] **Step 1: Write the test**

Create `Tests/CreatorNodesTests/FieldsAcceptanceTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorOCCT

/// Fields spec §8, "Acceptance (headless, OCCT)": a vented plate. Field Scatter on its top face with a distance field (denser
/// near the edges), Remap → Sample Field → Hole Pattern sizes (larger towards the centre), Cull by Field (Probability, noise)
/// thinning the points. It asserts the instance count, the sizes increasing towards the centre, and identical results on a
/// second run.
@MainActor
struct FieldsAcceptanceTests {
    /// The 60 × 40 plate's half sizes, and how far from the outline the distance field's ramps end.
    static let halfWidth = 30.0
    static let halfDepth = 20.0
    static let ramp = 14.0

    struct Part {
        var h = Harness()
        let plate: Node, scatter: Node, cull: Node, sample: Node, holes: Node
    }

    /// Plate → Hole Pattern at the surviving scatter points. The scatter's field is the distance to the plate's outline
    /// remapped 0…14 mm → 0…1 (spacing 4.5 mm at the edge, 9 mm from 14 mm in); the hole sizes are the same distance remapped
    /// 0…14 mm → Ø2…Ø4.
    static func makePart(kernel: any Kernel) async throws -> Part {
        var h = Harness()
        let plate = h.box(60, 40, 6, at: Vector3(0, 0, -6))
        let outline = h.add(RectangleNode.self, ["width": .number(60), "height": .number(40), "plane": .plane(.xy)])
        let distance = h.add(DistanceFieldNode.self)
        let density = h.add(FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(ramp), "toLow": .number(0), "toHigh": .number(1),
        ])
        let sizes = h.add(FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(ramp), "toLow": .number(2), "toHigh": .number(4),
        ])
        let scatter = h.add(FieldScatterNode.self, [
            "minSpacing": .number(4.5), "maxSpacing": .number(9), "margin": .number(3), "seed": .integer(5),
        ])
        let noise = h.add(NoiseFieldNode.self, ["seed": .integer(4), "scale": .number(12)])
        let cull = h.add(CullByFieldNode.self, ["mode": .integer(1), "seed": .integer(7)])
        let sample = h.add(SampleFieldNode.self)
        let holes = h.add(HolePatternNode.self, ["depth": .number(6)])
        h.wire(outline, "profile", to: distance, "target")
        h.wire(distance, "field", to: density, "field")
        h.wire(distance, "field", to: sizes, "field")
        h.wire(plate, "solid", to: scatter, "solid")
        h.wire(density, "field", to: scatter, "field")
        h.wire(scatter, "placements", to: cull, "placements")
        h.wire(noise, "field", to: cull, "field")
        h.wire(sizes, "field", to: sample, "field")
        h.wire(cull, "placements", to: sample, "at")
        h.wire(plate, "solid", to: holes, "part")
        h.wire(cull, "placements", to: holes, "placements")
        h.wire(sample, "values", to: holes, "diameter")

        // The face pick, made the way the app makes it: the plate's top face.
        let solid = try onlySolid(try await h.run([plate], kernel: kernel), plate)
        let top = try #require(solid.topology.faces.filter { $0.kind == .plane && $0.normal == .unitZ }
            .max { $0.centroid.z < $1.centroid.z })
        h.set(scatter, NodeSetting.face, .facePick(try #require(solid.topology.facePick(for: top.id))))
        return Part(h: h, plate: plate, scatter: scatter, cull: cull, sample: sample, holes: holes)
    }

    /// Everything one run of the part gives that the assertions look at.
    struct Result: Equatable {
        var scattered: [Vector3]
        var kept: [Vector3]
        var sizes: [Double]
        var volume: Double
    }

    static func run(_ part: Part, kernel: any Kernel) async throws -> (result: Result, solid: Solid) {
        let report = try await part.h.run([part.holes], kernel: kernel)
        for node in [part.scatter, part.cull, part.sample, part.holes] {
            #expect(report.isOK(node), "\(node.name): \(String(describing: report.state(node)))")
        }
        let solid = try onlySolid(report, part.holes)
        let result = Result(
            scattered: try #require(report.value(part.scatter, "placements")?.planes).map(\.origin),
            kept: try #require(report.value(part.cull, "placements")?.planes).map(\.origin),
            sizes: try #require(report.value(part.sample, "values")?.numbers),
            volume: try await volume(solid, kernel))
        return (result, solid)
    }

    /// A point's distance to the plate's outline.
    static func edgeDistance(_ point: Vector3) -> Double { min(halfWidth - abs(point.x), halfDepth - abs(point.y)) }

    @Test func aVentedPlateGetsGradedHolesAtThinnedScatteredPoints() async throws {
        let kernel = OCCTKernel()
        let (result, solid) = try await Self.run(try await Self.makePart(kernel: kernel), kernel: kernel)

        // The instance count: pinned, with the scatter and the thinning visible in it.
        #expect(result.scattered.count == 29, "scattered points: \(result.scattered.count)")
        #expect(result.kept.count == 13, "points kept by the noise: \(result.kept.count)")
        #expect(result.kept.count < result.scattered.count && result.kept.count >= 10)
        #expect(result.sizes.count == result.kept.count)
        #expect(Set(result.kept).isSubset(of: Set(result.scattered)), "Cull by Field only takes points away")

        // Every hole is the size its distance from the plate's edge gives: Ø2 at the edge to Ø4 from 14 mm in, so the holes
        // grow towards the centre.
        for (point, size) in zip(result.kept, result.sizes) {
            let expected = 2 + 2 * min(Self.edgeDistance(point) / Self.ramp, 1)
            #expect(abs(size - expected) < 1e-9, "at \(point): Ø\(size), wanted Ø\(expected)")
        }
        let byDistance = zip(result.kept, result.sizes).sorted { Self.edgeDistance($0.0) < Self.edgeDistance($1.0) }.map(\.1)
        #expect(zip(byDistance, byDistance.dropFirst()).allSatisfy { $0 <= $1 + 1e-12 }, "nearer the centre, never smaller")
        #expect((result.sizes.min() ?? 0) < 3 && (result.sizes.max() ?? 0) > 3, "a real range of sizes: \(result.sizes)")

        // The holes were cut at those sizes.
        let removed = PatternPlate.plateVolume - result.volume
        let wanted = result.sizes.reduce(0) { $0 + PatternPlate.cylinderVolume($1, 6) }
        #expect(abs(removed - wanted) < 1e-3 * wanted, "removed \(removed) mm³, wanted \(wanted)")

        // Denser near the edges: the scatter's points per area in the 7 mm band along the edge (inside the 3 mm margin) against the middle.
        let band = result.scattered.filter { Self.edgeDistance($0) < 7 }.count
        let middle = result.scattered.count - band
        let bandArea = 54.0 * 34 - 46 * 26, middleArea = 46.0 * 26
        #expect(Double(band) / bandArea > 1.3 * Double(middle) / middleArea, "band \(band), middle \(middle)")

        // Exact B-rep: the part exports.
        let url = temporaryURL("vented-plate.step")
        defer { try? FileManager.default.removeItem(at: url) }
        try await kernel.export([solid], format: .step, to: url)
        #expect(((try? Data(contentsOf: url))?.count ?? 0) > 1_000)
    }

    @Test func aSecondRunFromAFreshKernelAndFreshNodesGivesTheSamePointsSizesAndVolume() async throws {
        let first = try await Self.run(try await Self.makePart(kernel: OCCTKernel()), kernel: OCCTKernel()).result
        let second = try await Self.run(try await Self.makePart(kernel: OCCTKernel()), kernel: OCCTKernel()).result
        #expect(first == second)
        #expect(!first.kept.isEmpty)
    }
}

/// A fresh path in the temporary directory.
private func temporaryURL(_ name: String) -> URL {
    URL.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
}
```

- [ ] **Step 2: Run the test**

Run: `swift test --filter FieldsAcceptanceTests 2>&1 | grep -E "recorded|failed|Test run|Expectation" | head`
Expected: PASS. (When this plan was checked, the scatter made 29 points and the noise kept 13. These counts, the pinned `SeededRandom` values and field-3's "about 1,900" hold on the platform they were taken on; if libm's `cos`/`sin` change (another architecture or OS), a point on a region's edge can flip, and the pins are re-taken rather than loosened.)

- [ ] **Step 3: Lint and run the whole suite**

Run `swiftlint lint --strict` (zero violations) and the full `swift test` (background, to a log), judged by the rule in Global Constraints.
Expected: master + 173 tests (3,646).

- [ ] **Step 4: Commit**

```bash
git add Tests/CreatorNodesTests/FieldsAcceptanceTests.swift
git commit -m "test: the fields acceptance test, a vented plate with graded holes (7b-3)"
```
### Task 11: `FieldBench` row 3 (Field Scatter) and row 4 (the tinted preview), and the performance record

**Files:**
- Modify: `Tests/CreatorAppTests/Bench/FieldBench.swift`, `Tests/CreatorAppTests/Bench/FieldBenchFixtures.swift`, `Tests/CreatorAppTests/Bench/FieldBenchFixturesTests.swift`
- Create: `Tests/CreatorAppTests/Bench/FieldBenchApp.swift`, `Tests/CreatorAppTests/Bench/FieldBenchPreview.swift`, `Tests/CreatorAppTests/Bench/FieldBenchAppTests.swift`
- Modify: `docs/verification/performance.md`

**Interfaces:**
- Consumes: `FieldScatterNode`, `FieldPreviewModel` and `AppModel.fieldPreview` (Tasks 3 and 8), `makeBracketBenchApp()`, `AppBracket`, `BenchRenderer`, `BenchSamples`, `Bench`.
- Produces: the benchmark rows `field-3` (Field Scatter, ≈2,000 points on a face, under 50 ms), `field-3b` (7b-1's Sample Field + Cull by Field row under its old number's budget), `field-4` and `field-4b` (the edit to a tinted preview on the bracket, under 150 ms, with and without a kernel distance) and `field-4c` (the first tint, recorded).

**Rows (fields spec §7).** Row 3 is "Field Scatter, 2,000 points on a face, under 50 ms": 7b-1 measured Sample Field and Cull by Field in its place, so that row keeps its numbers as `field-3b` and `field-3` is now the node itself, on a 120 × 120 mm face with a radial-gradient field (spacing 1.4 to 2.4 mm, a 3 mm margin; about 1,900 points). Row 4 is "Edit to tinted preview on the bracket, under 150 ms (parent §7.3's budget)": the §7.2 bracket on OCCT with a field node selected, an edit to that field node, then everything up to the frame: `AppModel.settle()` (evaluation, the scene, the meshes, the tint's sampling and the slice's) and the window's frame drawn headless with both GPU passes, as `FilletDragBench` measures a drag. `field-4` edits a Remap of the signed distance to the bracket (the distances are cached after the first tint, so an edit costs the maths and the redraw, not the kernel), `field-4b` a Radial Gradient (no kernel at all), and `field-4c` is the first tint after selecting the Remap, when the kernel measures the bracket's mesh and the slice's grid, recorded with no budget.

**These are not gates on the loaded Mac.** A `FieldBench` timing taken while other sessions load the machine is not a valid result: it is recorded as saturated, with the load it was taken under, and no row is called met or missed from it. The run that verified this plan was on such a machine; its lines are in `docs/verification/performance.md` marked saturated. Rows 3 and 4 get their verdicts from an idle run (`scripts/bench.sh FieldBench`, all three load averages under 3). **That idle run is required before 7b-3 merges (or before the human sign-off, whichever is first)**: it is the point at which rows 3 and 4 become gates, as spec §7 gives them targets (50 ms and 150 ms). If `field-3` or `field-4` misses on an idle Mac, stop and ask: pull the levers below in order, re-measure, and never edit a budget or call a miss met. `field-3b`, `field-4b` and `field-4c` are recorded, not gated. (Row 2 is 7b-1's gate.)

- [ ] **Step 1: Write the fixture checks**

Edit `Tests/CreatorAppTests/Bench/FieldBenchFixturesTests.swift`:

```swift-old
    @Test func rowThreeIsTwoThousandPlacementsInFortyBranches() {
```

```swift-new
    @Test func rowThreeIsAFaceThatFieldScatterFillsWithAboutTwoThousandPoints() async throws {
        let (solid, pick) = try await FieldBenchFixtures.scatterPlate(OCCTKernel())
        let placed = try await FieldScatterNode.evaluate(FieldBenchFixtures.scatterInputs(solid), kernel: FakeKernel(),
                                                         context: FieldBenchFixtures.scatterContext(pick: pick))
        let planes = (placed.trees["placements"]?.items ?? []).compactMap { scalar -> Plane? in
            if case .plane(let plane) = scalar { plane } else { nil }
        }
        #expect(planes.count > 1_500 && planes.count <= 2_000, "\(planes.count) points")
        #expect(planes.allSatisfy { abs($0.origin.z) < 1e-9 && abs($0.origin.x) <= 57 + 1e-6 && abs($0.origin.y) <= 57 + 1e-6 })
        let denser = planes.filter { $0.origin.length < 20 }.count
        #expect(Double(denser) / (Double.pi * 400) > Double(planes.count - denser) / (114 * 114 - Double.pi * 400),
                "closer together near the middle, where the field is low")
    }

    @Test func rowThreeBIsTwoThousandPlacementsInFortyBranches() {
```

Create `Tests/CreatorAppTests/Bench/FieldBenchAppTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorApp

/// Row 4's bracket and field nodes are ready to measure (a plain `swift test` checks them, since `FieldBenchPreview` runs only
/// in a release build when asked): selecting a field node tints the bracket and shows the slice, and an edit to it changes the
/// tint, the Remap's without asking the kernel again.
@MainActor
struct FieldBenchAppTests {
    @Test func theRemapTintsTheBracketAndAnEditNeedsNoNewKernelDistances() async throws {
        let bench = try await FieldBenchApp()
        let app = bench.app
        bench.select(bench.remap)
        await app.settle()
        #expect(app.document.results[bench.remap.id]?.state.isSuccess == true)
        let first = try #require(app.viewport.items.first?.fieldValues)
        #expect(app.viewport.slice != nil && app.fieldPreview.legend?.range != nil)
        let misses = await app.document.fieldDistances.misses
        #expect(misses >= 1, "the first tint asked the kernel")
        try bench.setFromHigh(30)
        await app.settle()
        let second = try #require(app.viewport.items.first?.fieldValues)
        #expect(second != first && second.count == first.count)
        #expect(await app.document.fieldDistances.misses == misses, "the bracket's vertices and the slice's grid are cached")
    }

    @Test func theRadialGradientNeedsNoKernel() async throws {
        let bench = try await FieldBenchApp()
        bench.select(bench.radial)
        await bench.app.settle()
        let first = try #require(bench.app.viewport.items.first?.fieldValues)
        try bench.setRadius(55)
        await bench.app.settle()
        #expect(try #require(bench.app.viewport.items.first?.fieldValues) != first)
        #expect(await bench.app.document.fieldDistances.misses == 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: FAIL to compile, "cannot find 'FieldBenchApp' in scope", "type 'FieldBenchFixtures' has no member 'scatterPlate'".

- [ ] **Step 3: The fixtures and the benchmarks**

Edit `Tests/CreatorAppTests/Bench/FieldBenchFixtures.swift`:

```swift-old
import CreatorKernel

/// What `FieldBench` measures, built here so a plain `swift test` can check it is what the benchmark says it is.
```

```swift-new
import CreatorKernel
import CreatorNodes

/// What `FieldBench` measures, built here so a plain `swift test` can check it is what the benchmark says it is.
```

Edit `Tests/CreatorAppTests/Bench/FieldBenchFixtures.swift`:

```swift-old
    /// Row 3: `rows` branches of `columns` placements 4 mm apart, as a Grid Pattern makes them.
```

```swift-new
    /// Row 3b: `rows` branches of `columns` placements 4 mm apart, as a Grid Pattern makes them.
```

Edit `Tests/CreatorAppTests/Bench/FieldBenchFixtures.swift`:

```swift-old
    /// Row 3's field: noise plus a radial gradient over the placements' region.
    static let placementField = Field.add(.noise(seed: 9, scale: 12, octaves: 2), .radialGradient(center: Vector3(100, 80, 0), radius: 160))
}
```

```swift-new
    /// Row 3b's field: noise plus a radial gradient over the placements' region.
    static let placementField = Field.add(.noise(seed: 9, scale: 12, octaves: 2), .radialGradient(center: Vector3(100, 80, 0), radius: 160))

    /// Row 3: a 120 × 120 × 6 plate (top on z = 0) and the pick of its top face, which Field Scatter fills.
    static func scatterPlate(_ kernel: any Kernel) async throws -> (solid: Solid, pick: FacePick) {
        let solid = try await kernel.extrude(.rectangle(width: 120, height: 120, plane: Plane.xy.offset(by: -6)), distance: 6,
                                             mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        let tops = solid.topology.faces.filter { $0.kind == .plane && $0.normal == .unitZ }
        guard let top = tops.max(by: { $0.centroid.z < $1.centroid.z }), let pick = solid.topology.facePick(for: top.id) else {
            throw KernelError.operationFailed(operation: "fixture", reason: "the plate has no top face")
        }
        return (solid, pick)
    }

    /// Row 3's field: the distance from the face's middle over 60 mm, so the points are 1.4 mm apart in the middle and 2.4 mm
    /// apart from 60 mm out, with no kernel distance.
    static let scatterField = Field.radialGradient(center: .zero, radius: 60)

    /// Row 3's inputs to Field Scatter: the plate, the field, spacing 1.4 to 2.4 mm, a 3 mm margin, seed 5.
    static func scatterInputs(_ solid: Solid) -> NodeInputs {
        NodeInputs(item: 0, slots: [
            "solid": .item(.solid(solid)), "field": .item(.field(scatterField)), "minSpacing": .item(.number(1.4)),
            "maxSpacing": .item(.number(2.4)), "margin": .item(.number(3)), "seed": .item(.integer(5)),
        ])
    }

    /// The context of a Field Scatter node holding the face pick.
    static func scatterContext(pick: FacePick) -> EvalContext {
        var node = BuiltInNodes.registry.makeNode(FieldScatterNode.typeID)
        node.inputValues[NodeSetting.face] = .facePick(pick)
        return EvalContext(node: node, item: 0, parameters: [:])
    }
}
```

Edit `Tests/CreatorAppTests/Bench/FieldBench.swift`:

```swift-old
/// Fields spec §7, rows 1 to 3 (row 4, the tinted preview, comes with the previews in 7b-3). Release, idle Mac; prints
/// `BENCH field-…` lines, with each row's budget judged on the median:
/// 1. a five-node field (a source, a remap, noise, a multiply, a clamp) over 10,000 points, no kernel distance: under 5 ms;
/// 2. the signed distance from a plate to 10,000 points on OCCT: under 100 ms the first time, about nothing cached (a plate is
///    planes and cylinders; 2b is the same points against a smooth loft, recorded and not gated);
/// 3. the fields spec puts Field Scatter's 2,000 points on a face here; Field Scatter arrives in 7b-3, so this row measures the
///    work it will start with at the same size and budget, Sample Field and then Cull by Field over a tree of 2,000
///    placements (50 ms). 7b-3 adds the Field Scatter row beside it.
```

```swift-new
/// Fields spec §7, rows 1 to 3 (row 4, the tinted preview, is `FieldBenchPreview`). Release, idle Mac; prints
/// `BENCH field-…` lines, with each row's budget judged on the median:
/// 1. a five-node field (a source, a remap, noise, a multiply, a clamp) over 10,000 points, no kernel distance: under 5 ms;
/// 2. the signed distance from a plate to 10,000 points on OCCT: under 100 ms the first time, about nothing cached (a plate is
///    planes and cylinders; 2b is the same points against a smooth loft, recorded and not gated);
/// 3. Field Scatter's about 2,000 points on a face, with a radial-gradient field: under 50 ms; 3b is 7b-1's stand-in for this
///    row, Sample Field and then Cull by Field over a tree of 2,000 placements, kept under the same budget.
```

Edit `Tests/CreatorAppTests/Bench/FieldBench.swift`:

```swift-old
    static let placementsBudget = 50.0
```

```swift-new
    static let placementsBudget = 50.0
    static let scatterBudget = 50.0
```

Edit `Tests/CreatorAppTests/Bench/FieldBench.swift`:

```swift-old
    @Test func sampleFieldAndCullByFieldOverTwoThousandPlacements() async throws {
```

```swift-new
    @Test func fieldScatterOverAFaceOfAboutTwoThousandPoints() async throws {
        guard Bench.requireRelease() else { return }
        let (solid, pick) = try await FieldBenchFixtures.scatterPlate(OCCTKernel())
        let inputs = FieldBenchFixtures.scatterInputs(solid)
        let context = FieldBenchFixtures.scatterContext(pick: pick)
        let kernel = FakeKernel()  // the field is a gradient: the kernel is never asked
        let clock = ContinuousClock()
        var samples = BenchSamples("field-3 Field Scatter × about 2,000 points on a face")
        for round in 0..<25 {
            let start = clock.now
            let placed = try await FieldScatterNode.evaluate(inputs, kernel: kernel, context: context)
            guard round >= 3 else { continue }
            samples.append(from: start, to: clock.now)
            #expect((placed.trees["placements"]?.itemCount ?? 0) > 1_500)
        }
        print(samples.line(budget: Self.scatterBudget))
    }

    @Test func sampleFieldAndCullByFieldOverTwoThousandPlacements() async throws {
```

Edit `Tests/CreatorAppTests/Bench/FieldBench.swift`:

```swift-old
        var samples = BenchSamples("field-3 Sample Field + Cull by Field × 2,000 placements")
```

```swift-new
        var samples = BenchSamples("field-3b Sample Field + Cull by Field × 2,000 placements")
```

Create `Tests/CreatorAppTests/Bench/FieldBenchApp.swift`:

```swift
// Test fixture file: the §7.2 bracket with field nodes beside it, for the field preview's benchmark (fields spec §7, row 4).
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
@testable import CreatorApp

/// The bracket the other benchmarks measure (`makeBracketBenchApp`), and beside it two fields: a Remap of the signed distance
/// from the bracket's finished part (`remap`: 0 to `fromHigh` mm onto 0…1) and a Radial Gradient (`radial`). Neither feeds the
/// Output; selecting one tints the bracket in Final preview.
@MainActor
struct FieldBenchApp {
    let app: AppModel
    let bracket: AppBracket
    let distance: Node
    let remap: Node
    let radial: Node

    init() async throws {
        (app, bracket) = try await makeBracketBenchApp()
        distance = try Self.add(DistanceFieldNode.self, to: app)
        remap = try Self.add(FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(20), "toLow": .number(0), "toHigh": .number(1),
        ], to: app)
        radial = try Self.add(RadialGradientNode.self, ["center": .vector(Vector3(0, 0, 0)), "radius": .number(40)], to: app)
        try Self.wire(bracket.chamfer, "solid", distance, "target", in: app)
        try Self.wire(distance, "field", remap, "field", in: app)
        await app.settle()
    }

    func select(_ node: Node) {
        app.editor.selection = [node.id]
    }

    func setFromHigh(_ millimetres: Double) throws {
        try app.document.perform(.setInput(remap.id, "fromHigh", .number(millimetres)))
    }

    func setRadius(_ millimetres: Double) throws {
        try app.document.perform(.setInput(radial.id, "radius", .number(millimetres)))
    }

    private static func add(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:],
                            to app: AppModel) throws -> Node {
        var node = app.registry.makeNode(definition.typeID, at: Vector2(Double(app.document.graph.nodes.count) * 40, 200))
        node.inputValues.merge(values) { _, given in given }
        try app.document.perform(.addNode(node))
        return node
    }

    private static func wire(_ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName, in app: AppModel) throws {
        try app.document.perform(.connect(Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input))))
    }
}
```

Create `Tests/CreatorAppTests/Bench/FieldBenchPreview.swift`:

```swift
import Testing
@testable import CreatorApp

/// Fields spec §7, row 4: "Edit to tinted preview on the bracket, under 150 ms" (parent §7.3's budget for an edit to a
/// preview). The §7.2 bracket on OCCT with a field node selected; each step edits that field to a value never seen before and
/// waits for the evaluation, the scene, the meshes, the tint's sampling and the slice's, then draws the window's frame (CPU)
/// and both GPU passes, as `FilletDragBench` measures a drag. Release, idle Mac; prints `BENCH field-4…` lines:
/// - `field-4`: a Remap of the signed distance to the bracket (its range edited): the kernel's distances to the bracket's
///   vertices and the slice's grid are cached after the first tint, so an edit costs the maths and the redraw;
/// - `field-4b`: a Radial Gradient (its radius edited), no kernel at all;
/// - `field-4c`: the first tint, selecting the Remap, when the kernel measures the bracket's mesh and the slice's grid
///   (recorded, no budget).
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct FieldBenchPreview {
    static let budget = 150.0
    static let steps = 40

    /// Runs `steps` edits and returns the command-to-frame time of each.
    func measure(_ name: String, in bench: FieldBenchApp, edit: (Int) throws -> Void) async throws -> BenchSamples {
        let input = AppInput(model: bench.app)
        let renderer = try BenchRenderer()
        renderer.place(bench.app)
        var total = BenchSamples(name)
        let clock = ContinuousClock()
        for step in 0..<Self.steps {
            let begin = clock.now
            try edit(step)
            await bench.app.settle()
            let scene = renderer.windowScene(bench.app, input: input)
            try renderer.drawViewport(bench.app.viewport)
            try renderer.composite(scene)
            total.append(from: begin, to: clock.now)
        }
        return total
    }

    @Test func anEditToTheRemapOfTheBracketsDistance() async throws {
        guard Bench.requireRelease() else { return }
        let bench = try await FieldBenchApp()
        let clock = ContinuousClock()
        var first = BenchSamples("field-4c first tint of the bracket by its signed distance (kernel)")
        let begin = clock.now
        bench.select(bench.remap)
        await bench.app.settle()
        first.append(from: begin, to: clock.now)
        let samples = try await measure("field-4 edit to a tinted bracket preview (Remap of the signed distance)", in: bench) {
            try bench.setFromHigh(20 + Double($0 + 1) * 0.1)
        }
        #expect(bench.app.viewport.items.first?.fieldValues != nil && bench.app.viewport.slice != nil)
        #expect(bench.app.document.results[bench.remap.id]?.state.isSuccess == true)
        print(first.line())
        print(samples.line(budget: Self.budget))
    }

    @Test func anEditToARadialGradientOnTheBracket() async throws {
        guard Bench.requireRelease() else { return }
        let bench = try await FieldBenchApp()
        bench.select(bench.radial)
        await bench.app.settle()
        let samples = try await measure("field-4b edit to a tinted bracket preview (Radial Gradient)", in: bench) {
            try bench.setRadius(40 + Double($0 + 1) * 0.5)
        }
        #expect(bench.app.viewport.items.first?.fieldValues != nil && bench.app.viewport.slice != nil)
        #expect(bench.app.document.results[bench.radial.id]?.state.isSuccess == true)
        print(samples.line(budget: Self.budget))
    }
}
```

- [ ] **Step 4: The performance record**

Edit `docs/verification/performance.md`:

```text-old
| `field-3` | Sample Field then Cull by Field (Probability) over 2,000 placements in 40 branches; stands in for Field Scatter's row (7b-3) at its size and budget | under **50 ms** |
| `field-4` | the edit to a tinted preview on the bracket | 7b-3 |
```

```text-new
| `field-3` | Field Scatter on a 120 × 120 mm face with a radial-gradient field (spacing 1.4 to 2.4 mm, 3 mm margin): about 1,900 points (7b-3) | under **50 ms** |
| `field-3b` | Sample Field then Cull by Field (Probability) over 2,000 placements in 40 branches (7b-1's stand-in for row 3, kept) | under **50 ms** |
| `field-4` | the edit to a tinted preview on the bracket: a Remap of the signed distance to it selected and its range edited, to the frame (7b-3) | under **150 ms** (parent §7.3's edit-to-preview budget) |
| `field-4b` | the same with a Radial Gradient (no kernel distance) | under **150 ms** |
| `field-4c` | the first tint of the bracket by its signed distance (the kernel measures its mesh and the slice's grid) | recorded, no budget |
```

Edit `docs/verification/performance.md`:

```text-old
**Fixture checks** run in a plain `swift test` (`FieldBenchFixturesTests`): row 1's field has five nodes and gives varied
numbers in 0…1, the points are the same every time, row 2's plate and row 2b's loft give the right signed distances on OCCT, row
3's tree is 2,000 placements in 40 branches.
```

```text-new
**Fixture checks** run in a plain `swift test` (`FieldBenchFixturesTests`): row 1's field has five nodes and gives varied
numbers in 0…1, the points are the same every time, row 2's plate and row 2b's loft give the right signed distances on OCCT, row
3's face gets about 1,900 points denser in the middle, row 3b's tree is 2,000 placements in 40 branches; `FieldBenchAppTests`
checks row 4's bracket and field nodes (selecting a field tints the bracket and shows the slice, an edit changes the tint, and
the Remap's edit asks the kernel for nothing new).

**Rows 3 and 4 (7b-3).** `field-3` calls `FieldScatterNode.evaluate` on the Fake kernel (the field has no kernel distance) over an
OCCT plate's picked top face. `field-4`, `field-4b` and `field-4c` (`FieldBenchPreview`, fixture `FieldBenchApp`) drive the
§7.2 bracket's app as `FilletDragBench` does: each step edits the selected field node to a value not seen before (the Remap's
`fromHigh` 20.1 … 24 mm, the gradient's radius 40.5 … 60 mm), waits for `AppModel.settle()` (evaluation, scene, meshes, the tint's
sampling over the bracket's vertices and the slice's grid: 64 × 64 for `field-4`, which measures with the kernel, and 256 × 256 for `field-4b`, which has none) and draws the window's frame and both GPU passes. The slice is
a 256 × 256 grid for a field with no kernel distance (`field-4b`) and 64 × 64 for one that measures a solid (`field-4`; 65,536 kernel distances would take
seconds on OCCT); `field-4c` records what the first tint costs.

**Saturated, not measured.** The `FieldBench` lines taken while this plan was verified are in "Fields, 7b-3, saturated lines"
below, with the load they were taken under. They are not results: the Mac was saturated by other sessions, so none of them says a
row is met or missed, and rows 3 and 4 get their verdicts from an idle run (`scripts/bench.sh FieldBench`, all three load
averages under 3), which replaces those lines.
```

Edit `docs/verification/performance.md`:

````text-old
## Raw output

The run the tables above come from (`scripts/bench.sh`, every suite):
````

````text-new
### Fields, 7b-3, saturated lines

The `FieldBench` lines for rows 3 and 4 as taken while this plan was verified, in a release build on a MacBookPro18,2 (10 cores,
macOS 27.0.1) that other sessions had saturated: `scripts/bench.sh FieldBench` ran at load averages 67.81 36.55 28.25 before and
94.28 69.04 47.10 after, the row 4 lines (`scripts/bench.sh FieldPreviewBench`, the suite's name before it became `FieldBenchPreview` so that
`scripts/bench.sh FieldBench` runs it too) at 90.93 73.02 50.43 before and 101.12 76.90 52.48 after. They are **saturated, not measured**: the words "met" and "missed" were struck from the lines below because they are the script's arithmetic on a
machine several times oversubscribed; no row is called met or missed from these lines. An idle run (all three load averages under 3) is
required before 7b-3 merges; it replaces these lines and gives the verdicts.

```text
BENCH field-3 Field Scatter × about 2,000 points on a face: median 118.11 ms, p95 182.25 ms, max 183.27 ms (n 22); budget 50.00 ms (verdict: idle run)
BENCH field-3b Sample Field + Cull by Field × 2,000 placements: median 1.36 ms, p95 16.22 ms, max 25.84 ms (n 40); budget 50.00 ms (verdict: idle run)
BENCH field-4c first tint of the bracket by its signed distance (kernel): median 680.51 ms, p95 680.51 ms, max 680.51 ms (n 1)
BENCH field-4 edit to a tinted bracket preview (Remap of the signed distance): median 113.73 ms, p95 215.44 ms, max 1001.04 ms (n 40); budget 150.00 ms (verdict: idle run)
BENCH field-4b edit to a tinted bracket preview (Radial Gradient): median 123.60 ms, p95 177.06 ms, max 191.11 ms (n 40); budget 150.00 ms (verdict: idle run)
```

If an idle run puts `field-3` over 50 ms, the levers, in the order to pull them and re-measure: (1) key the point grid by one packed
`Int` instead of a hashed two-field struct (`PoissonScatter.Cell`), (2) fewer candidates per point (`candidatesPerPoint` 30 to 20,
which loosens the packing a little and changes every scatter, so `FieldScatterNodeTests` and `FieldsAcceptanceTests` re-pin their
counts), (3) stop and ask. The budget is not edited and a miss is not called met.

## Raw output

The run the tables above come from (`scripts/bench.sh`, every suite):
````

- [ ] **Step 5: Lint and run the whole suite**

Run `swiftlint lint --strict` (zero violations) and the full `swift test` (background, to a log), judged by the rule in Global Constraints. A plain run skips the benchmarks (`Bench.isRequested`); the release run is `scripts/bench.sh FieldBench` on an idle Mac.
Expected: master + 179 tests (3,652).

- [ ] **Step 6: Commit**

```bash
git add Tests/CreatorAppTests/Bench docs/verification/performance.md
git commit -m "test: FieldBench rows 3 (Field Scatter) and 4 (the tinted preview) (7b-3)"
```
### Task 12: Documentation, human checks and the final verification

**Files:**
- Modify: `CLAUDE.md`, `docs/superpowers/roadmap.md`, `docs/verification/human-checks.md`, `docs/superpowers/specs/2026-10-12-fields-design.md`
- `docs/metalui-gaps.md`: **no change.** No MetalUI gap was hit: the legend's ramp is a `LinearGradient`, its toggle and buttons are `Toggle` and a segmented `Picker`, the card is a `GlassPanel`, and the tint and slice are drawn by the viewport's own Metal pipelines; each was built and driven in a window test. If a human check finds one, log it in `docs/metalui-gaps.md` (entry and summary row), send it to the MetalUI session and never work around it.

- [ ] **Step 1: CLAUDE.md**

Edit `CLAUDE.md`:

```markdown-old
§2 to §4, §7 and §9) code is done; its human checks (group FI-core) are pending and its benchmark numbers await an idle run. Images
(7b-2, format 7) and Field Scatter with the previews (7b-3) are planned after it merges.
```

```markdown-new
§2 to §4, §7 and §9) code is done; its human checks (group FI-core) are pending and its benchmark numbers await an idle run. Images
(7b-2, format 7) are planned beside 7b-3.
Fields, sub-project 7b-3 (Field Scatter, the surface tint, the slice plane and the legend, the three theme roles `fieldLow`,
`fieldMid` and `fieldHigh`, the acceptance test and `FieldBench` rows 3 and 4; plan
`docs/superpowers/plans/2026-10-13-7b-3-scatter-previews.md`, spec `docs/superpowers/specs/2026-10-12-fields-design.md` §3.3, §6, §7
and §8 and its Errata (7b-3)) code is done; its human checks (group FI) are pending and its benchmark numbers await an idle run.
```

Edit `CLAUDE.md`:

```markdown-old
- `CreatorNodes`: the 64 built-in node definitions (`BuiltInNodes.registry`: the slice's 26, Plane from Face and Sketch,
the twelve `Fields` nodes below, the seventeen
```

```markdown-new
- `CreatorNodes`: the 65 built-in node definitions (`BuiltInNodes.registry`: the slice's 26, Plane from Face and Sketch,
the thirteen `Fields` nodes below, the seventeen
```

Edit `CLAUDE.md`:

```markdown-old
    `field-2b` records a smooth loft); row 3 measures Sample Field and Cull by Field over 2,000 placements until Field Scatter
    (7b-3) can be measured at the same size.
```

```markdown-new
    `field-2b` records a smooth loft); row 3 is Field Scatter over a face (`field-3b` keeps 7b-1's Sample Field and Cull by Field
    over 2,000 placements); row 4 (`FieldBenchPreview`) is the edit to a tinted preview on the bracket. Timings taken on a loaded
    Mac are recorded as saturated, never as a verdict.
    Field Scatter (7b-3, `Using/FieldScatterNode`) is the layout node for density: `solid` (a picked flat face, the `face` setting, read
    as Face Pattern reads it, holes and margin respected) or `profile` (exactly one), `field` (a number is a constant field),
    `minSpacing`, `maxSpacing`, `margin` and `seed`. `PoissonScatter` is variable-radius Bridson sampling: rounds of candidates in
    the annulus `r`…`2r` round each active point, the field asked once per round for all that survive the cheap tests, each active
    point taking its first candidate at least its own spacing from every placed point, a new seed drawn when nothing is active (islands,
    jumps in spacing), every draw `SeededRandom` under `Purpose.scatter`; the spacing at a point is
    `minSpacing + clamp(field, 0, 1) × (maxSpacing − minSpacing)`, so no two points are closer than `minSpacing`. It makes one flat
    list of placements on the region's plane in generation order, refuses over 2,000 ("Field Scatter would place N points; …", "more
    than 8,000" when it stopped at its ceiling) and renumbers when the field, region or seed changes: a pick on a scattered instance
    then warns "Instance {n} no longer exists". `InspectorControl.note(_:)` carries its help line, and the face menu's Scatter on Face
    (`AppModel.scatterOnFace`, `FaceLayout`) inserts one wired to the part.
```

Edit `CLAUDE.md`:

```markdown-old
  `.mctheme` keys; `ThemeRoleTests` pins them to the stored properties). `@MainActor @Observable ThemeStore` holds
```

```markdown-new
  `.mctheme` keys; `ThemeRoleTests` pins them to the stored properties). The field preview's ramp is three roles, `fieldLow`,
  `fieldMid` and `fieldHigh` (group `ThemeRoleGroup.fieldPreview`, last in `ThemeRole.all`); a `.mctheme` without them reads
  Dracula's. `@MainActor @Observable ThemeStore` holds
```

Edit `CLAUDE.md`:

```markdown-old
    There is no default measure and no fallback estimate. Every scroll or pinch event stops a camera animation started mid-gesture.
```

```markdown-new
    There is no default measure and no fallback estimate. Every scroll or pinch event stops a camera animation started mid-gesture.
    The field preview's half of the viewport knows numbers and colours only. A `ViewportItem` may carry `fieldValues` (one per vertex
    of `ViewportModel.displayMesh(of:)`) and a `FieldRamp` (three colours at three values; `FieldRamp.color(at:)` is the Swift twin of
    the shader's `field_ramp`): the renderer draws it with a second pipeline (`FieldShaders`: `field_mesh_*`, a float per de-indexed
    corner in a buffer `GPUMesh` keeps until the values change, `GPUGeometry.fieldCorners`), lit like the plain surface, never on a
    ghost, and wrong-sized values draw the plain surface. A `ViewportSlice` (`ViewportModel.showSlice`) is a translucent quad over the
    scene showing a grid of values (`r32Float`, read with a bilinear blend in `slice_fragment`, kept by `SliceTextures` until its
    `generation` changes); it is equal and hashed by `generation`, never by its values, is drawn ignoring depth (it passes through the
    part) and is never in the ID pass or `sceneBounds`. The viewport's shader source is `ViewportShaders.source + FieldShaders.source`.
```

Edit `CLAUDE.md`:

```markdown-old
  (`Palette.header(for: .fields)`) until the theme has a role of its own.
```

```markdown-new
  (`Palette.header(for: .fields)`) until the theme has a role of its own. A node's `InspectorControl.note(_:)` is a line of help
  (Field Scatter's note on renumbering), shown as an `InspectorRow.recipe(label: "Note", …)`.
```

Edit `CLAUDE.md`:

```markdown-old
  face's pick, wired from the part. Inside a group `AppModel` reads the level through `editor.graph`/`levelResults`:
```

```markdown-new
  face's pick, wired from the part (Scatter on Face does the same for a Field Scatter; `FaceLayout` is what the two differ by).
  The field preview (`AppModel.fieldPreview`, a `FieldPreviewModel` replaced with the document) follows the one selected Fields node:
  `refreshScene()` hands it `fieldPreviewRequest(for:)` (`FieldPreviewSelection`: the field a node makes, or the first field wired
  into one that takes a field; nothing while picking or sketching), tints the opaque items it has a tint for
  (`tinted(_:colors:)`; `ViewportItem.drawsTheSame` compares tints), shows its slice (`viewportSlice(colors:)`) and appends the
  slice's handle (`FieldPreviewModel.sliceHandleID`; `handleChanged` moves it as view state: no command, no undo step, not an edit).
  Sampling runs off the main actor in two tasks, the tint (every shown solid's mesh vertices from `ViewportModel.displayMesh(of:)`)
  and the slice grid (256² or, for a field that measures with the kernel, 64²: `SlicePose.resolution`), through the evaluator's
  distance cache (`DocumentModel.fieldDistances`) so an orbit, a toggle or an edit downstream of a distance asks the kernel for
  nothing; a newer request cancels the older and the old tint and slice stay until the new are ready; over 200,000 vertices a
  deterministic subset is sampled and the rest take the nearest's value (`CoarseSampling`); a failed sampling is the kernel's own
  words in the legend. The range is automatic, centred on 0 for a signed distance, or fixed 0…1 (`FieldPreviewRange`); the slice
  starts shown, on the field's own plane (`Field.ownPlane`) or the axis plane nearest the camera (`SlicePose`). The legend
  (`FieldLegendView` in `FieldLegendDock`, placed above the axis triad by `AppLayout.legendInsets`) draws the ramp, three numbers
  with "mm" for a distance (`Field.unit`), the "0…1" toggle, the slice buttons and "Preview sampled coarsely". `Field` is `Hashable`
  (a distance to a solid, faces or edges by `DistanceTarget.identity`), which is how the preview tells an edit from a repeat.
  `settle()` also waits for the sampling. Inside a group `AppModel` reads the level through `editor.graph`/`levelResults`:
```

- [ ] **Step 2: The roadmap and the spec's errata**

Edit `docs/superpowers/roadmap.md`:

```markdown-old
| ⏳ plan after 7b-1 merges | Uses `FieldSampler` for preview sampling (no new `Field` case); adds `SeededRandom.Purpose.scatter`, `BuiltInNodes`, `ViewportItem`, `CreatorStyle` roles; shares CLAUDE.md and human-checks.md with 7b-2 |
```

```markdown-new
| ✅ code done (plan `2026-10-13-7b-3-scatter-previews.md`); human checks FI pending; benchmark numbers pending an idle run | Uses `FieldSampler` for preview sampling (no new `Field` case; `Field` becomes `Hashable`); adds `SeededRandom.Purpose.scatter`, `BuiltInNodes` (65 nodes), `ViewportItem`, `ViewportSlice`, `CreatorStyle` roles, `InspectorControl.note`; shares CLAUDE.md and human-checks.md with 7b-2 |
```

Edit `docs/superpowers/specs/2026-10-12-fields-design.md`:

```markdown-old
- **The distance cache (§2.2) counts the solids it keeps alive** (`Solid.estimatedBytes`) with its points and distances, so its
  64 MB bounds what it pins.
```

```markdown-new
- **The distance cache (§2.2) counts the solids it keeps alive** (`Solid.estimatedBytes`) with its points and distances, so its
  64 MB bounds what it pins.

## Errata (7b-3: Field Scatter and the previews)

- **Field Scatter's region and margin (§3.3).** The inputs are `solid` (with the existing `face` setting) or `profile`, exactly one
  of them, then `field`, `minSpacing`, `maxSpacing`, `margin` (default 3 mm, as Face Pattern's) and `seed`; §3.3 says "holes and a
  `margin` respected" but lists no margin input. A profile's holes are respected as a face's are.
- **Field Scatter's sampling (§3.3).** A point is placed only if it is at least its *own* spacing from every point placed before it
  (not the larger of the two spacings), which keeps every pair at least `minSpacing` apart. A new seed is drawn whenever no point is
  active, so islands the margin cuts off, and parts of the region a jump in the spacing puts out of the annuli's reach, are filled.
  The search stops at 8,000 points so that the refusal can name the count: "Field Scatter would place 2,431 points; patterns are
  limited to 2,000 instances." up to that, "… would place more than 8,000 points; …" beyond. An empty result is an error ("found no
  room for a point"), never an empty list.
- **Scatter on Face (§3.3).** A picked face is only ever made by a face-menu item (Face Pattern's "Pattern on Face"), so a Field
  Scatter gets "Scatter on Face": it inserts the node holding the face's pick, wired from the part, as one undo step.
- **The inspector's help (§4)** is a new `InspectorControl.note(_:)`, shown read-only under the node's controls.
- **The slice grid (§6)** is 256 × 256 for a field with no kernel distance and 64 × 64 for one that measures a solid, faces or
  edges: 65,536 kernel distances take seconds on OCCT, and the slice resamples on every step of its handle's drag.
- **The slice is shown when a field node is selected (§6)** and is drawn over the part ignoring depth, because it passes through it
  (a depth test would hide the half that lies inside the solid). Its handle moves view state, not the document: no command, no
  undo step, the document is not edited.
- **The tint is lit (§6):** the ramp colour is shaded by the same light as the plain surface (hover and selection blend in as
  before), so the part's form still reads under it.
- **The legend stands above the axis triad (§6)**, which already occupies the viewport's lower left, clear of the docked graph panel.
  Its slice buttons are Plane (only when the field has a plane of its own), XY, YZ, XZ and Off.
- **The three theme roles (§6)** are in a group of their own, "Field preview", last in the theme editor.
- **`FieldBench` rows (§7).** Row 3 is Field Scatter on a face; 7b-1's Sample Field and Cull by Field row is kept as `field-3b`. Row
  4 is `field-4` (a Remap of the bracket's signed distance), with `field-4b` (a Radial Gradient, no kernel) and `field-4c` (the
  first tint, recorded). A timing taken on a loaded machine is recorded as saturated and is no verdict.
- **A pick on a renumbered scattered instance (§8)** warns by the existing rule, "Instance {n} no longer exists, so the edge picked on
  it isn't selected." (`FieldScatterPickTests`).
```

- [ ] **Step 3: The human checks (group FI)**

Edit `docs/verification/human-checks.md`:

```markdown-old
## Group C23 — MetalUI C23: text measured, not estimated (Adopt C23)
```

```markdown-new
## Group FI — field previews and Field Scatter (7b-3)

**Status: NOT RUN.** Plan `2026-10-13-7b-3-scatter-previews.md`, spec `2026-10-12-fields-design.md` §3.3 and §6. Run
`swift run MetalCreatorApp`. The tests pin the sampling, the range rules, the tint and the slice on a real GPU, the legend's
numbers and buttons and the scatter; these check how it looks and feels. (7b-2's image and relink checks are its own, FI-img.)
Build: a Rectangle (60 × 40) into an Extrude (6) into an Output; beside it a Distance Field whose `target` is the Extrude's solid,
into a Remap (from 0…20, to 0…1); and a Radial Gradient (radius 30) at the origin.

- [ ] **FI-1 The tint.** Select the Radial Gradient: the plate takes colours from the theme's cool end (cyan in Dracula) near the
  middle to the warm end (red) at the corners, through yellow, shaded by the light so its form still reads; its edges are still
  drawn over the tint; hovering a face still lightens it and a selected face still glows. Orbit and zoom: smooth, no flicker, the
  colours do not swim. Select the Extrude: the tint goes at once. Select the Remap: the tint follows the distance (the middle
  colour on the surface where the distance is 0). Pinned: `FieldTintRenderTests`, `AppFieldPreviewTests`. **Observed:**
- [ ] **FI-2 The ramp follows the theme.** View > Theme > Alucard, then Nord: the tint and the legend's bar change to each theme's
  three field colours at once, with no new sampling pause. Open the theme editor: a "Field preview" group is last, with Field low,
  Field middle and Field high; change Field high: the tint and the bar follow. Export the theme and import it: the colours
  survive; an older `.mctheme` file without the three roles reads Dracula's. Pinned: `FieldRampRoleTests`,
  `aThemeChangeRecoloursTheTintWithoutSamplingAgain`. **Observed:**
- [ ] **FI-3 The slice.** With the Radial Gradient selected there is a translucent quad through the plate, on the axis plane nearest
  your view (look from above: XY), coloured by the field and covering the plate with a margin. It is drawn over the plate, so you
  can read the field inside it. A handle (the same arrow as an Extrude's) sits in its middle: drag it along the quad's normal; the
  quad follows without a pause you notice, the legend's numbers follow, and nothing is added to Undo (the Edit menu does not change,
  the title bar shows no edit). Select a Linear Gradient: the slice starts on its own plane. Pinned: `ViewportSliceRenderTests`,
  `FieldPreviewSliceTests`, `theLegendsToggleChangesTheRampAndTheSliceHandleEditsNoDocument`. **Observed:**
- [ ] **FI-4 The legend.** A small glass card stands above the axis triad at the viewport's lower left, clear of the docked graph
  panel (move the panel to the bottom and hide it: the card keeps clear of the triad and the show button). It shows the ramp as a
  bar, three numbers under it (for the Remap or the Radial Gradient plain numbers; for a Distance Field "… mm"; for a signed
  distance to a solid the middle number is 0 and the ends are the same size), the "0…1" toggle and the slice buttons XY, YZ, XZ and
  Off (and Plane for a Linear Gradient). Pressing XY/YZ/XZ moves the quad to that plane through the plate; Off removes it and its
  handle and keeps the tint; "0…1" fixes the numbers to 0, 0.5, 1 at once. The card goes when you select a node with no field. The
  text is legible in all three themes. Pinned: `FieldLegendWindowTests`, `FieldLegendLabelsTests`. **Observed:**
- [ ] **FI-5 A failure and a big part.** Wire a Distance Field into a Remap, then delete the solid it measures to (so the field
  can't be sampled): the legend shows the reason in red instead of numbers and the tint goes. For a part over 200,000 vertices
  ("Preview sampled coarsely") use a Hole Pattern of 2,000 holes on a thick plate and select a field: the legend says so and the tint
  appears without a long wait. Pinned: `aFailedSamplingSaysSoInTheKernelsWordsAndKeepsNoTint`,
  `aBigMeshIsSampledCoarselyAndTheLegendSaysSo`. **Observed:**
- [ ] **FI-6 Field Scatter.** Right-click the plate's top face: the menu offers Scatter on Face after Pattern on Face; choose it.
  A Field Scatter appears beside the Extrude, selected, wired to it, and its points show as small axis triads over the face, none
  nearer than its Min spacing and all clear of the edge by its margin, with the area they fill dashed. Wire the Radial Gradient into
  its `field` with Min spacing 5 and Max spacing 12: the points are close together in the middle and sparse towards the corners
  (a field of 0 is the densest). Change the seed: a different scatter. Its inspector ends with the note about renumbering. Wire a
  Hole Pattern after it, pick a hole's rim with an Edges by Tag, then change a spacing so there are fewer points than the pick's
  number: the Edges by Tag warns "Instance {n} no longer exists". Pinned: `ScatterOnFaceTests`, `ScatterPreviewTests`,
  `FieldScatterPickTests`. **Observed:**
- [ ] **FI-7 The vented plate.** Build the acceptance part by hand: Field Scatter on the top face with a Distance Field of the
  outline (Remap 0…14 mm to 0…1), a Remap 0…14 mm to Ø2…Ø4 into a Sample Field at a Cull by Field's survivors (Probability, a Noise
  Field), and a Hole Pattern: holes are small at the edges, larger towards the middle, thinned at random; a second run of the same
  file gives the same part. Pinned: `FieldsAcceptanceTests`. **Observed:**

## Group C23 — MetalUI C23: text measured, not estimated (Adopt C23)
```

- [ ] **Step 4: The whole suite, lint and the record**

Run `swiftlint lint --strict` (zero violations) and the full `swift test` (background, to a log), judged by the rule in Global Constraints: exit code 0, no line saying "recorded an issue" or "failed after", and 11 "Test run with" lines. This task adds no test.
Expected: master + 179 tests (3,652).

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs
git commit -m "docs: fields 7b-3 notes, roadmap, errata and human checks FI"
```
## Self-Review

Run against `docs/superpowers/specs/2026-10-12-fields-design.md` after the plan was written, then the plan was applied task by task in a scratch copy (see "How this plan was verified").

**1. Spec coverage.**

| Spec | Where |
|---|---|
| §3.3 Field Scatter: a layout node under 7a's rules (`singleValuesRefusal`, `PatternLimit`); a picked face or a profile; `field`, `minSpacing`, `maxSpacing`, `seed`; spacing `minSpacing + clamp(field, 0, 1) × (maxSpacing − minSpacing)`; Bridson with `SeededRandom` under its own `Purpose`; no two points closer than `minSpacing`; a flat list facing the normal, numbered in generation order; renumbering (D7) | Task 2 (`PoissonScatter`, `Purpose.scatter`), Task 3 (`FieldScatterNode`, `FaceRegion+Profile`, the pick warning) |
| §4 messages ("Field Scatter would place 2,431 points; patterns are limited to 2,000 instances."), the inspector help, a field's recipe row | Task 3 (messages, `InspectorControl.note`); the recipe row is 7b-1's |
| §6 when a preview shows (a selected Fields node, evaluated before anything downstream is wired; it goes with the selection); Field Scatter's axis-triad overlay | Tasks 4 (triads, evaluated though unwired), 7 (`FieldPreviewSelection`), 8 (`applyPreview`, `fieldPreviewRequest`) |
| §6 surface tint: `ViewportItem.fieldValues` and `FieldRamp`, one float vertex buffer and a ramp lookup, the GPU structs mirrored and pinned, `CreatorViewport` knowing nothing of fields | Task 5 |
| §6 slice plane: a quad on a grid (one texture), the starting plane (own, else the box centre on the axis plane nearest the view), a viewport handle along the normal, the legend's XY / YZ / XZ / hide, view state in memory | Tasks 6 (the quad), 7 (`SlicePose`), 8 (state, handle), 9 (buttons) |
| §6 the three roles in `CreatorStyle`, Dracula's for old `.mctheme` files, listed by the theme editor | Task 1 |
| §6 range (automatic, signed centred on 0, "0…1"), the legend card with min, mid, max, units, toggles, "Preview sampled coarsely" | Tasks 7 (`FieldPreviewRange`, `Field.unit`), 9 (`FieldLegendView`) |
| §6 responsiveness: off the main actor, a newer request cancels, the old tint stays, over 200,000 vertices a deterministic subset and nearest-vertex values, cached kernel distances | Tasks 7 (`CoarseSampling`, `FieldPreviewSampler`), 8 (`FieldPreviewModel`, the distance cache) |
| §7 `FieldBench` row 3 (Field Scatter) and row 4 (the edit to a tinted preview on the bracket) | Task 11 |
| §8 testing: scatter (spacing, density, determinism, limits, refusals), paths (a renumbered pick warns), previews (range, start pose, which selections, cancellation, coarse cap, a render test), the acceptance test, human checks FI | Tasks 2, 3, 5 to 9, 10, 12 |
| Errata (7b-1): the graded-sizes order | Task 10 builds Remap → Sample Field → Hole Pattern; a list into a single-valued input is refused in the layouts' words (Task 3) |
| Spec asks left to 7b-2 | the relink flow (human check), images, format 7 |

**2. Placeholder scan.** No "TBD", "implement later" or "similar to Task N". The ellipses in the plan are UI text ("0…1", "Edit sketch…") and the literal `…` in recipes and messages. Every step that changes code shows the code; every edit to an existing file is an exact old and new text.

**3. Type consistency.** Names are defined once and used as defined: `PoissonScatter.Outcome` (Task 2; Task 3), `FieldScatterNode.ceiling`, `.help`, `.noRegion`, `.bothRegions`, `.noRoom`, `.notANumber` (Task 3; Tasks 3, 11), `FaceLayout.pattern` / `.scatter` (Task 4), `FieldRamp` and `ViewportItem.fieldValues` / `.fieldRamp` (Task 5; Tasks 7, 8), `ViewportSlice` and `samplePoints()` (Task 6; Tasks 7, 8), `Field.ownPlane` / `measuresWithKernel` / `isSignedDistance` / `unit`, `FieldPreviewSelection`, `FieldPreviewRange.make(extent:centredOnZero:fixedToUnit:)`, `CoarseSampling.sampledIndices(count:limit:)` / `expand(positions:sampled:values:)`, `FieldPreviewSampler.tint(of:at:limit:kernel:cache:)` / `gridValues(of:in:kernel:cache:)`, `SlicePose.startingChoice(for:toEye:)` / `starting(for:bounds:toEye:)` / `pose(for:field:bounds:)` / `through(_:bounds:)` / `fitted(_:choice:bounds:)` / `moved(to:)` / `resolution(for:)`, `SliceChoice` and `SliceAxis` (Task 7; Tasks 8, 9), `FieldPreviewModel` (`follow`, `stop`, `chooseSlice`, `moveSlice`, `setUnitRange`, `waitForSampling`, `tinted`, `viewportSlice`, `sliceHandle`, `legend`) and `FieldLegend` (Task 8; Tasks 9, 11), `FieldPreviewModel.sliceHandleID` (Task 8; Task 8's `handleChanged`), `AppLayout.legendInsets` (Task 9), `FieldBenchApp` (Task 11). Each later task's Interfaces block lists what it consumes.

**4. Review Focus.** Each of the five lines has its tests in the task that owns the code (named in the line). Two more cases were found while writing the tasks and added to them: a field that is not a number inside Field Scatter (Task 3) and a pick in progress while a preview is up (Task 8).

## How this plan was verified

Every code block was applied, task by task, to a scratch copy of this worktree (a sibling `MetalUI` symlinked to `/Users/maxburger/Developer/MetalUI`: `b17aee19` for the baseline run, `498dd7ee`, which changes no source, for the task-by-task run), by a script that reads this file (a `Create`, `Replace` or `Edit` line followed by its fences). After each task the copy built with no new warning (`swift build --build-tests`), was clean under `swiftlint lint --strict`, and passed a full `swift test` by the rule in Global Constraints. The counts in each task's last steps are the sums of the "Test run with" lines of those runs. The baseline before Task 1 was green with 3,473 tests. `scripts/bench.sh FieldBench` (rows 3 and 3b) and the row 4 suite were run once each in a release build on the loaded Mac; their lines are in `docs/verification/performance.md` as saturated and are no verdict. Task 11's performance record was applied again after those lines were written; the final text of Tasks 11 and 12 was applied to the Task 10 tree and linted, and its code is the code the full run passed.
