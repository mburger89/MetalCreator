# DIM-1 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document units, the ANSI dimension style, a world-space dimension primitive drawn over the viewport, an in-view value
box that commits only on Return, and the sketch editor's dimensions redrawn and edited that way.

**Architecture:** Units and dimension geometry are `CreatorGeometry` values; `DimensionStyle`, `OverlayDimension`, its pure screen
layout (`DimensionLayout`) and the value box are `CreatorViewport`'s; MetalUI shapes and text draw them over the GPU surface and
take no pointer: `ViewportModel` hit-tests the texts it last laid out. The sketch editor answers the box through
`DimensionEditing`; the app routes by ID prefix. Shared names and every decision touching the spec are in
`docs/superpowers/plans/2026-10-27-dim-overview.md`: read it first.

**Tech Stack:** Swift 6.4, MetalUI (`../MetalUI`, read only), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-10-27-driving-dimensions-design.md` §4.1, §4.5, §5, §6, §7 (the box), §8 (units), §10.

**Branch / worktree:** `dim-1-foundation` in `/Users/maxburger/Developer/worktrees/dim-1` (see the overview's Worktrees note).

## Global Constraints

- The overview's Global Constraints apply to every task: Swift 6.4 strict concurrency, Swift Testing only, `@MainActor @Observable` models, portable code (no CoreText/CoreGraphics/Metal outside `#if canImport`, `.primary` for shortcuts), colours only in `CreatorStyle`, `UndoName`/`SketchStepName` constants without numbers or typed text, `swiftlint lint --strict` clean, never broad `pkill`, never modify `../MetalUI`, the two commit trailers.
- Per task: `swift build --build-tests`, then `swift test --filter <suites named in the task>`; Task 16 runs the full suite (12 "Test run with" lines, exit 0, no "recorded an issue"/"failed after") on macOS and Linux.
- File format 10 (Task 4); `units` written only when not `DocumentUnits.millimetres`; a file without it reads millimetres.
- Spec §5 values, verbatim: millimetres keep the leading zero and drop trailing zeros ("0.5", "60"); inches drop the leading zero and show trailing zeros to the precision (".50", "2.250"); "Ø8", "R17", "2X Ø8", "45°", "(70)", "width = 60"; arrowheads filled, 3:1, constant on-screen size; text unidirectional, centred in a break of the dimension line.
- Spec §6: internal values stay millimetres; precision defaults 2 places in inches and 1 in millimetres; typing accepts at least `in`, `"` and `mm`.
- Spec §7: while typing nothing changes (no solve, no evaluation, no camera move); Return parses and commits one "Change Dimension" step; Esc or a click elsewhere closes with no change; a refusal keeps the box open with the message in red.
- Text sizes are measured (`TextMeasure`), never estimated; model tests pass a fake measure, view tests `TextMeasure.real()`.

## Review Focus

1. A unit or precision change while a value box is open: the box (whose text is in the old unit) closes and nothing is committed. Test: Task 15 `aUnitChangeClosesAnOpenValueBox`.
2. Opening a box on a value with more decimals than the display and pressing Return untouched changes nothing and adds no undo step. Tests: Task 9 `returnWithTheOpeningTextCommitsNothing`, Task 14 `anUntouchedReturnIsNoStep`.
3. Typed spellings people will try (`12,5`, `1/2`, `2 ft`, `1e3`, `12.5MM`, stray spaces): a clean refusal with the box's message, never a silently wrong value. Tests: Task 2 `refusesWhatItCannotReadExactly`, Task 14 `nonNumbersAndBadValuesAreRefusedInTheBox`.
4. Degenerate or unseen geometry (zero length, a radius of 0, a point behind the camera, a plane seen edge-on): the dimension is left out, with no NaN in anything placed. Tests: Task 6 `aDegenerateDimensionIsLeftOut`, Task 7 `aZeroRadiusIsLeftOut`, Task 12 `aDimensionWhoseGeometryIsGoneIsLeftOut`.
5. The edited dimension goes away while its box is open (sketch Done, undo from the menu, a solve that drops it): the box closes and nothing is committed. Tests: Task 9 `theBoxClosesWhenItsDimensionGoesAway`, Task 14 `finishingTheSketchClosesTheBox`.

---

### Task 1: File gap DIM-a

**Files:**
- Modify: `docs/metalui-gaps.md` (a summary-table row after the last one; a new section at the end)

- [ ] **Step 1: Add the row** `| DIM-a | No click count on a tap's value (double-click on a dimension's text in the viewport) | — (to assign) | ❌ open: asked 2026-10-27; the viewport hit-tests dimension texts itself and passes clickCount 1 until then |`.
- [ ] **Step 2: Add the section** `## Hit by driving dimensions (DIM-1), 2026-10-27` with the entry **DIM-a**, using the overview's gap text (use case: `ViewportView.surface`'s `SpatialTapGesture` → `ViewportModel.click(at:modifiers:clickCount:)`; why neither `count: 2` nor a gesture on the text view works; wanted: `SpatialTapGesture.Value.clickCount`, the platform's count of the press that ended the tap, MetalUI-only like `modifiers`; meanwhile: the box opens in tests through `openValueBox(for:)`, and in the app a double-click does nothing).
- [ ] **Step 3: Commit** `docs: MetalUI gap DIM-a (click count on a tap)`. Report to the orchestrator that DIM-a must be sent to the MetalUI session.

### Task 2: Units in CreatorGeometry

**Files:**
- Create: `Sources/CreatorGeometry/Units/LengthUnit.swift`, `DimensionQuantity.swift`, `DocumentUnits.swift`, `DocumentUnits+Codable.swift`, `DocumentUnits+Text.swift`, `DocumentUnits+Parsing.swift`
- Test: `Tests/CreatorGeometryTests/Units/DocumentUnitsTests.swift`, `UnitTextTests.swift`, `UnitParsingTests.swift`

**Interfaces:**
- Produces: `LengthUnit`, `DimensionQuantity`, `DocumentUnits` exactly as in the overview, plus `DocumentUnits.suffix(for quantity: DimensionQuantity) -> String` (" mm", " in", "°", "" for a count).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func precisionDefaultsToOnePlaceInMillimetresAndTwoInInches() {
    #expect(DocumentUnits().fractionDigits == 1)
    #expect(DocumentUnits(length: .inches).fractionDigits == 2)
    #expect(DocumentUnits(precision: 9).fractionDigits == 4)
    #expect(DocumentUnits(precision: -1).fractionDigits == 0)
}
@Test func convertsThroughTwentyFivePointFour() {
    let inches = DocumentUnits(length: .inches)
    #expect(inches.value(fromMillimetres: 25.4) == 1)
    #expect(abs(inches.millimetres(fromValue: 2.25) - 57.15) < 1e-12)
}
@Test func encodesOnlyWhatDiffersFromTheDefault() throws  // {"length":"in"}; precision 3 adds "precision":3;
    // decoding {} → .millimetres; {"length":"furlong"} → .millimetres; {"precision":12} → precision 4
@Test func editTextKeepsEnoughDigitsToChangeNothing() {
    let mm = DocumentUnits(), inch = DocumentUnits(length: .inches)
    #expect(mm.editText(60, quantity: .length) == "60")
    #expect(mm.editText(12.345678, quantity: .length) == "12.3457")
    #expect(inch.editText(60, quantity: .length) == "2.3622")
    #expect(mm.editText(22.5, quantity: .angle) == "22.5")
    #expect(mm.editText(6, quantity: .count) == "6")
    #expect(mm.editText(-0.00001, quantity: .length) == "0")
}
@Test func fieldTextRoundsToThePrecisionWithItsSuffix() {
    // mm: 12.5 → "12.5 mm", 60 → "60 mm"; inches: 57.15 → "2.25 in", 12.7 → "0.50 in"; angle 30 → "30°", 22.25 → "22.3°"
}
@Test func readoutNumbersAreFixedDigits()  // mm 24.5 → "24.5", 24 → "24.0", -0.04 → "0.0"; inches 24.5 → "0.96"
@Test func readsTheDocumentsUnitOrASuffix() {
    let mm = DocumentUnits(), inch = DocumentUnits(length: .inches)
    #expect(mm.parse(" 12.5 mm ", quantity: .length) == 12.5)
    #expect(mm.parse("12.5MM", quantity: .length) == 12.5)
    #expect(mm.parse("2in", quantity: .length) == 50.8)
    #expect(mm.parse("2\"", quantity: .length) == 50.8)
    #expect(mm.parse("2 inches", quantity: .length) == 50.8)
    #expect(mm.parse("5 cm", quantity: .length) == 50)
    #expect(mm.parse(".5", quantity: .length) == 0.5)
    #expect(inch.parse("2", quantity: .length) == 50.8)
    #expect(inch.parse("50 mm", quantity: .length) == 50)
    #expect(mm.parse("45°", quantity: .angle) == 45)
    #expect(mm.parse("45 deg", quantity: .angle) == 45)
    #expect(mm.parse("6", quantity: .count) == 6)
}
@Test(arguments: ["", "abc", "12,5", "1/2", "1e3", "2 ft", "12 mm mm", "--3"])
func refusesWhatItCannotReadExactly(_ text: String) { #expect(DocumentUnits().parse(text, quantity: .length) == nil) }
@Test func refusesAUnitOfTheWrongQuantity()  // "45 mm" as .angle, "45°" as .length, "6.5" and "6 mm" as .count → nil
```

- [ ] **Step 2: Run** `swift test --filter CreatorGeometryTests` — Expected: FAIL (types missing).
- [ ] **Step 3: Implement.** Numbers go through `FormatStyle` (`.number.precision(.fractionLength(…)).rounded(rule: .toNearestOrAwayFromZero).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))`), a result of zero is written without a sign. `editText` keeps up to 4 decimals (mm, angles) or 5 (inches), trimmed; `fieldText` uses `fractionDigits`, trimmed in mm, fixed in inches, angles up to 1 decimal trimmed. `parse`: trim whitespace, number `[+-]?(digits(.digits?)?|.digits)` then optional spaces then a case-insensitive suffix: length `mm`, `cm`, `in`, `inch`, `inches`, `"` or none (the document's unit); angle `°`, `deg` or none; count none and integral; anything else, or a non-finite result, is `nil`.
- [ ] **Step 4: Run** `swift test --filter CreatorGeometryTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(geometry): document units, unit text and unit-aware parsing`.

### Task 3: The ANSI dimension style

**Files:**
- Create: `Sources/CreatorViewport/Dimensions/DimensionStyle.swift`, `DimensionReading.swift`, `DimensionStyle+Text.swift`
- Test: `Tests/CreatorViewportTests/Dimensions/DimensionTextTests.swift`

**Interfaces:**
- Consumes: Task 2's `DocumentUnits`, `DimensionQuantity`.
- Produces: `DimensionStyle`, `DimensionStyle.ansi`, `DimensionReading`, `text(_:units:)` (overview signatures). `ansi`'s values, in points: `arrowLength` 9, `arrowWidth` 3, `extensionGap` 3, `extensionOvershoot` 6, `textGap` 4, `standoff` 28, `leaderLength` 24, `shoulderLength` 10, `lineWidth` 1, `pinMarkRadius` 3; `edgeOnLimit` 10° in radians.

- [ ] **Step 1: Write the failing tests**

```swift
let mm = DocumentUnits(), inch2 = DocumentUnits(length: .inches), inch3 = DocumentUnits(length: .inches, precision: 3)
func text(_ r: DimensionReading, _ u: DocumentUnits = DocumentUnits()) -> String { DimensionStyle.ansi.text(r, units: u) }
@Test func millimetresKeepTheLeadingZeroAndDropTrailingZeros() {
    #expect(text(.init(0.5, .length)) == "0.5"); #expect(text(.init(60, .length)) == "60")
    #expect(text(.init(12.25, .length)) == "12.3"); #expect(text(.init(12.04, .length)) == "12")
}
@Test func inchesDropTheLeadingZeroAndKeepTrailingZeros() {
    #expect(text(.init(12.7, .length), inch2) == ".50"); #expect(text(.init(57.15, .length), inch2) == "2.25")
    #expect(text(.init(57.15, .length), inch3) == "2.250"); #expect(text(.init(76.2, .length), inch2) == "3.00")
    #expect(text(.init(6.35, .length), DocumentUnits(length: .inches, precision: 0)) == "0")
}
@Test func symbolsPrecedeTheNumber() {
    #expect(text(.init(17, .radius)) == "R17"); #expect(text(.init(8, .diameter)) == "\u{D8}8")
    #expect(text(.init(45, .angle), inch2) == "45°"); #expect(text(.init(22.25, .angle)) == "22.3°")
    #expect(text(.init(6, .count)) == "6X")
}
@Test func equalFeaturesArePrefixedNX() {
    #expect(text(.init(8, .diameter, count: 2)) == "2X Ø8"); #expect(text(.init(8, .diameter, count: 1)) == "Ø8")
}
@Test func aReferenceWrapsTheWholeText() {
    #expect(text(.init(70, .length, isReference: true)) == "(70)")
    #expect(text(.init(8, .diameter, count: 2, isReference: true)) == "(2X Ø8)")
    #expect(text(.init(60, .length, name: "width")) == "width = 60")
    #expect(text(.init(60, .length, isReference: true, name: "width")) == "(width = 60)")
}
@Test func noNegativeZero() { #expect(text(.init(-0.01, .length)) == "0") }
@Test func theAnsiStyleHasThreeToOneArrows() { #expect(DimensionStyle.ansi.arrowLength / DimensionStyle.ansi.arrowWidth == 3) }
```

- [ ] **Step 2: Run** `swift test --filter DimensionTextTests` — Expected: FAIL.
- [ ] **Step 3: Implement** `text(_:units:)`: number by quantity (lengths in `units`' length unit at `fractionDigits`, mm trimmed, inches fixed with the leading zero removed below 1; angles ≤ 1 decimal trimmed + "°"; count integer + "X"); then "R"/"Ø" prefix; then "NX " when `count ≥ 2`; then "name = "; then parentheses for a reference.
- [ ] **Step 4: Run** `swift test --filter DimensionTextTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(viewport): DimensionStyle.ansi and ASME number rules`.

### Task 4: Document units in the file (format 10)

**Files:**
- Modify: `Sources/CreatorGraph/Graph.swift` (stored `units`, coding key `units`), `GraphCommand.swift` (`case setUnits(DocumentUnits)` in `touchedNodes` → `[]`, `affectsResults` → `false`), `Graph+Commands.swift` (apply; inverse is `.setUnits(old)`), `GraphFile.swift` (`currentFormatVersion = 10` and one doc sentence: "10: the document's units (`Graph.units`) …; DIM-2 and DIM-3 add theirs under 10"), `UndoName.swift` (`changeUnits`, `changePrecision`), `DocumentModel.swift` (`public var units: DocumentUnits { content.graph.units }`), any other exhaustive `GraphCommand` switch the compiler names, `CLAUDE.md` (the "File format is version 9" sentence becomes 10 with "10 added the document's units (optional key `units` on the top-level graph)")
- Test: `Tests/CreatorGraphTests/Units/DocumentUnitsFileTests.swift`; existing tests that pin the current version as the literal 9 switch to `GraphFile.currentFormatVersion` (tests about reading an old file keep their literal)

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aFileWithoutUnitsReadsMillimetres() throws   // a format-9 JSON fixture → graph.units == .millimetres
@Test func unitsRoundTrip() throws                      // .inches precision 3 → JSON has "units":{"length":"in","precision":3}; decodes equal
@Test func millimetresAtTheirDefaultPrecisionWriteNoKey() throws  // encoded JSON has no "units"
@Test func theFormatIsTenAndNineStillOpens() throws     // currentFormatVersion == 10; a 9 file decodes and re-encodes as 10
@Test func setUnitsIsOneUndoStepThatChangesNoResult() async {
    // perform(.setUnits(.init(length: .inches)), name: UndoName.changeUnits) → document.units.length == .inches,
    // undoName == "Change Units", GraphCommand.setUnits(.millimetres).affectsResults == false; undo → .millimetres
}
```

- [ ] **Step 2: Run** `swift test --filter CreatorGraphTests` — Expected: FAIL.
- [ ] **Step 3: Implement** as listed; decoding uses `decodeIfPresent(…) ?? .millimetres`, encoding skips `== .millimetres`.
- [ ] **Step 4: Run** `swift test --filter CreatorGraphTests` and `swift test --filter UndoNameTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(graph): document units on the top-level graph, file format 10`.

### Task 5: Dimension theme roles and tints

**Files:**
- Modify: `Sources/CreatorStyle/ThemeColors.swift` (+`dimensionDriving`, `dimensionReference`, last), `ThemeRole+All.swift`, `ThemeRoleGroup.swift` (`.dimensions`, "Dimensions", last), `ColorTheme+Dracula.swift` (`0x8be9fd`, `0x6272a4`), `ColorTheme+Alucard.swift` (`0x036a96`, `0x6c664b`), `ColorTheme+Nord.swift` (`0x88c0d0`, `0x81a1c1`); `Sources/CreatorViewport/Overlay/OverlayTint.swift` (+`.dimensionDriving`, `.dimensionReference`), `Render/ViewportPalette+Overlay.swift` and its SDL twin if separate, `View/ViewportModel+TextColors.swift`
- Test: `Tests/CreatorStyleTests/DimensionRoleTests.swift`; `Tests/CreatorViewportTests/ViewportPaletteTests.swift` (one test added)

- [ ] **Step 1: Write the failing tests**

```swift
@Test func theDimensionRolesAreLastInTheirOwnGroup() {
    #expect(ThemeRole.all.suffix(2).map(\.name) == ["dimensionDriving", "dimensionReference"])
    #expect(ThemeRoleGroup.dimensions.title == "Dimensions"); #expect(ThemeRoleGroup.allCases.last == .dimensions)
}
@Test(arguments: [ColorTheme.dracula, .alucard, .nord])
func builtInsGiveDrivingTheFocusColourAndReferenceTheComment(_ theme: ColorTheme)
    // colors.dimensionDriving == colors.focus; colors.dimensionReference == colors.comment
@Test func aThemeFileWithoutThemReadsDraculas() throws   // ThemeFile without the two keys → Dracula's values
// ViewportPaletteTests:
@Test func theDimensionTintsTakeTheirRoles()             // textColor(for: .dimensionDriving) is the theme's dimensionDriving, likewise reference
```

- [ ] **Step 2: Run** `swift test --filter CreatorStyleTests` — Expected: FAIL.
- [ ] **Step 3: Implement**; fix the role-count and key pins in `ThemeRoleTests` the compiler or the suite names.
- [ ] **Step 4: Run** `swift test --filter CreatorStyleTests` and `swift test --filter ViewportPaletteTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(style): dimension theme roles and overlay tints`.

### Task 6: The dimension primitive and linear layout

**Files:**
- Create: `Sources/CreatorGeometry/Dimensions/DimensionPlacement.swift`, `DimensionGeometry.swift`; `Sources/CreatorViewport/Dimensions/OverlayDimensionID.swift`, `OverlayDimension.swift`, `PlacedDimension.swift`, `ScreenSegment.swift`, `DimensionCamera.swift`, `DimensionLayout.swift`, `DimensionLayout+Linear.swift`, `Sources/CreatorViewport/Model/ViewportModel+Dimensions.swift`
- Modify: `Sources/CreatorViewport/Model/ViewportModel.swift` (`public private(set) var dimensions: [OverlayDimension] = []`, `public var dimensionStyle = DimensionStyle.ansi`, `@ObservationIgnored var drawnDimensions: [PlacedDimension] = []`)
- Test: `Tests/CreatorViewportTests/Dimensions/LinearDimensionLayoutTests.swift`, `DimensionVisibilityTests.swift`; `Tests/CreatorViewportTests/Support/DimensionFixtures.swift` (`topDownCamera(pointsPerMillimetre:)`, a fake measure of 8 pt per character)

**Interfaces:**
- Consumes: Task 3's style; Task 5's tints.
- Produces (overview types plus):

```swift
public struct ScreenSegment: Hashable, Sendable { public var a: ScreenPoint; public var b: ScreenPoint }
public struct PlacedDimension: Hashable, Sendable {
    public static let textPadding = 4.0, textHeight = 18.0
    public struct Arrow: Hashable, Sendable {
        public var tip: ScreenPoint; public var direction: Vector2          // unit, on screen, pointing at the tip
        public func corners(length: Double, width: Double) -> [ScreenPoint]  // tip, then the two base corners
    }
    public var id: OverlayDimensionID; public var text: String; public var tint: OverlayTint; public var isGhosted: Bool
    public var segments: [ScreenSegment]; public var arrows: [Arrow]
    public var textOrigin: ScreenPoint; public var textSize: ViewportSize; public var showsText: Bool
    public var pinMark: ScreenPoint?
    public func textContains(_ point: ScreenPoint) -> Bool
}
struct DimensionCamera {   // pose + size; project, viewDirection(at:), pointsPerMillimetre(at:along:) -> Double?
}
enum DimensionLayout {
    @MainActor static func place(_ dimension: OverlayDimension, style: DimensionStyle, camera: DimensionCamera,
                                 measure: TextMeasure) -> PlacedDimension?
}
extension ViewportModel {
    public func showDimensions(_ dimensions: [OverlayDimension])   // not in renderKey or sceneBounds
    public func placedDimensions(measuring measure: TextMeasure) -> [PlacedDimension]   // [] while animating or sizeless; records drawnDimensions
    public func dimension(at point: ScreenPoint) -> OverlayDimensionID?   // the last drawn text box containing it, topmost (last) first
}
```

- [ ] **Step 1: Write the failing tests** (60 mm from (0,0,0) to (60,0,0), direction +x, side +y, top-down orthographic at 2 pt/mm unless stated)

```swift
@Test func theDimensionLineStandsOffByTheStyle()             // both dimension-line ends 28 pt above (smaller y) the projected ends
@Test func extensionLinesLeaveAGapAndRunPastTheLine()        // each starts 3 pt from its point, ends 6 pt past the line
@Test func theTextBreaksTheLineAtItsMiddle()                 // "60" box (16 + 2·4 wide, 18 high) centred on the line's middle;
                                                             // no segment of the line enters the box grown by 4
@Test(arguments: [1.0, 4.0]) func arrowsArePointsSizedWhateverTheZoom(_ ppm: Double)   // corners span 9 along, 3 across
@Test func aShortDimensionPutsArrowsAndTextOutside()         // (0,0,0)→(5,0,0): arrows point inward, text centre right of the right end
@Test func aSavedPlacementPutsTheLineThroughIt()             // .through((30, 20, 0)) → line at the projected y of 20 mm
@Test func aDimensionSeenNearlyEdgeOnIsHidden()              // camera 5° above the dimension's plane → nil; 15° → placed
@Test func aDegenerateDimensionIsLeftOut()                   // from == to; zero direction; a point behind a perspective camera → nil;
                                                             // every coordinate of the placed ones is finite
// DimensionVisibilityTests:
@Test func dimensionsAreNeitherSceneNorRender()              // showDimensions leaves renderKey and sceneBounds unchanged
@Test func noDimensionsWhileAnimatingOrSizeless()
@Test func theTextHitIsTheLastDrawnBox()                     // dimension(at: text centre) == id; on the line outside the text → nil; overlap → later
```

- [ ] **Step 2: Run** `swift test --filter LinearDimensionLayoutTests` and `--filter DimensionVisibilityTests` — Expected: FAIL.
- [ ] **Step 3: Implement linear placement** (`d` = unit direction, `s` = unit side; `nil` if either has no length):

```
ea = from·s, eb = to·s, mid = (from + to) / 2
o  = .through(q): q·s | .standoff: max(ea, eb) + style.standoff / pointsPerMillimetre(at: mid, along: s)
A  = from + s·(o − ea),  B = to + s·(o − eb)
hide if |(d × s)·viewDirection(at: mid)| < sin(edgeOnLimit), if any projection is nil, or if |B′ − A′| < 1 pt
extension (p, P): e = P′ − p′; if |e| > extensionGap: p′ + ê·gap → P′ + ê·overshoot
u = unit(B′ − A′); along = |u.x|·w + |u.y|·h (the text box's extent along u)
fits (|B′ − A′| ≥ along + 2·textGap + 2·arrowLength): arrows at A′ (−u) and B′ (+u), text centred, line clipped outside the box grown by textGap
else: arrows at A′ (+u) and B′ (−u) on leaders of 2·arrowLength outside, text centred at B′ + u·(2·arrowLength + textGap + along/2)
```

  Text box: measured width rounded up + 2·`textPadding`, height `textHeight`. `placedDimensions` places in list order; `pinMark` is the text box's top-right corner when `isPinned`.
- [ ] **Step 4: Run** the two suites — Expected: PASS.
- [ ] **Step 5: Commit** `feat(viewport): OverlayDimension and its linear layout`.

### Task 7: Radial and angular layout

**Files:**
- Create: `Sources/CreatorViewport/Dimensions/DimensionLayout+Radial.swift`, `DimensionLayout+Angular.swift`
- Test: `Tests/CreatorViewportTests/Dimensions/RadialDimensionLayoutTests.swift`, `AngularDimensionLayoutTests.swift`

**Interfaces:**
- Consumes/produces: Task 6's `DimensionLayout.place` handles every `DimensionGeometry` case.

- [ ] **Step 1: Write the failing tests** (top-down, 2 pt/mm)

```swift
@Test func aRadiusLeaderMeetsTheCircleWithAnArrowAndAShoulder()
    // circle at the origin, r 10, toward (1,1,0)/√2: arrow tip on the circle 20 pt from the centre at 45°, pointing at the centre side;
    // leader 24 pt outward; shoulder 10 pt to the right, horizontal; text's left edge 4 pt past the shoulder, centred on it
@Test func aLeaderOnTheLeftTurnsItsShoulderLeft()      // toward (−1,0,0): shoulder to −x, text's right edge 4 pt before its end
@Test func aCircleSeenEdgeOnIsHidden()
@Test func aZeroRadiusIsLeftOut()
@Test func anAngleArcSpansTheSmallerAngle()             // vertex origin, first (10,0,0), second (0,10,0): every arc point in x ≥ 0, y ≥ 0; text at 45°
@Test func angleArrowsSitOnTheArcsEnds()                // tips on the rays, directions tangent to the arc, pointing outward
@Test func extensionLinesReachAnArcBeyondTheLines()     // radius beyond first/second → extension lines along each ray, gap and overshoot as linear
```

- [ ] **Step 2: Run** both suites — Expected: FAIL.
- [ ] **Step 3: Implement.** Radial: `toward` projected into the circle's plane and normalised; `P = center + toward·radius`; `r̂ = unit(P′ − C′)` (`nil` under 1e-6); leader end `L = P′ + r̂·leaderLength` (`.through(q)`: `L = q′`); shoulder `L → L + (±shoulderLength, 0)`, the sign of `L.x − C′.x`; text beyond the shoulder by `textGap`; one arrow, tip `P′`, direction `unit(P′ − L)`. Angular: rays `u₁`, `u₂` (unit, in plane) and their angle θ; radius ρ = `.standoff`: `(standoff + leaderLength) / pointsPerMillimetre(at: vertex, along: u₁)`, `.through(q)`: `|q − vertex|`; 24 arc points turning `u₁` towards `u₂` about the normal by θ; text centred at the middle point, the arc clipped around it; arrows at both ends along the end chords; extension lines when ρ is beyond a ray's point.
- [ ] **Step 4: Run** both suites — Expected: PASS.
- [ ] **Step 5: Commit** `feat(viewport): radial and angular dimension layout`.

### Task 8: Drawing dimensions

**Files:**
- Create: `Sources/CreatorViewport/View/DimensionView.swift` (`Component`), `DimensionLinesShape.swift` (`Shape`: every segment, stroked `lineWidth`), `DimensionArrowsShape.swift` (`Shape`: the arrows' triangles, filled)
- Modify: `Sources/CreatorViewport/View/ViewportView+Parts.swift` (`stack`: after the handle labels, a `for` over `model.placedDimensions(measuring: measure)` drawing `DimensionView`; everything `.allowsHitTesting(false)`)
- Test: `Tests/CreatorViewportTests/Dimensions/DimensionRenderTests.swift`

**Interfaces:**
- Consumes: Tasks 6–7. `DimensionView(placed: PlacedDimension, style: DimensionStyle, ink: Color, fill: Color)`: lines and arrows in `ink`, the text (`.caption`) in `ink` on a `fill` rounded box (radius 4) as labels are today, the pin mark a filled circle of `pinMarkRadius`, opacity 0.4 when `isGhosted`; nothing drawn for the text when `!showsText`. The stack passes `model.textColor(for: placed.tint)` and `model.labelFill`.

- [ ] **Step 1: Write the failing tests** (render `DimensionView` alone with `renderFrame` and `testTextSystem()`: portable, so they run on Linux and Windows too)

```swift
@Test func theTextIsDrawnInsideItsBox() throws          // "60": 2 glyphs whose centres lie in textOrigin/textSize
@Test func linesAndArrowsArePainted() throws            // scene.images is not empty (shapes are rasterized paths)
@Test func aHiddenTextDrawsNoGlyphs() throws            // showsText false → no glyphs
#if canImport(Metal)
@Test func theViewportDrawsEachDimensionsText() throws  // ViewportView over a model with one dimension (as the old label test did)
#endif
```

- [ ] **Step 2: Run** `swift test --filter DimensionRenderTests` — Expected: FAIL.
- [ ] **Step 3: Implement** (shapes in the view's coordinates, `Path` `move`/`addLine`/`closeSubpath`; a `Component` struct inside the builder's `for`, never an opaque helper: gap M4-b).
- [ ] **Step 4: Run** `swift test --filter DimensionRenderTests` and `swift test --filter CreatorViewportTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(viewport): draw dimensions over the scene`.

### Task 9: Text hits, the value box model and menu hooks

**Files:**
- Create: `Sources/CreatorViewport/Dimensions/DimensionEditing.swift` (protocol, default `menuActions`/`performMenuAction`, `DimensionValueBoxContent`, `DimensionCommitOutcome`, `HostMenuAction`), `DimensionValueBox.swift`, `PlacedValueBox.swift`, `Sources/CreatorViewport/Model/ViewportModel+ValueBox.swift`
- Modify: `ViewportModel+Input.swift` (`click(at:modifiers:clickCount:)`), `ViewportModel+ContextMenu.swift`, `ViewportMenuItem.swift` (`case host(HostMenuAction, dimension: OverlayDimensionID?)`, title = the action's), `Tool/ViewportTool.swift` (`menuActions(at:) -> [HostMenuAction]`, `performMenuAction(_:)`, defaults none), `ViewportModel+Dimensions.swift` (`showDimensions` cancels a box whose ID is gone; the edited dimension is placed with `showsText == false`)
- Test: `Tests/CreatorViewportTests/Dimensions/ValueBoxTests.swift`, `DimensionMenuTests.swift`; `Tests/CreatorViewportTests/Support/FakeDimensionEditor.swift` (records commits and menu actions; answers a set outcome; can hold a commit open until released)

**Interfaces:**

```swift
public struct DimensionValueBox: Hashable, Sendable {   // imports MetalUI for TextSelection
    public var id: OverlayDimensionID; public var draft: String; public var opening: String
    public var selection: TextSelection?; public var note: String?; public var message: String?; public var isChecking: Bool
}
public struct PlacedValueBox: Hashable, Sendable { public var box: DimensionValueBox; public var origin: ScreenPoint; public var size: ViewportSize }
extension ViewportModel {
    public func click(at point: ScreenPoint, modifiers: ViewportModifiers = [], clickCount: Int = 1)
    public weak var dimensionEditor: (any DimensionEditing)?            // stored in ViewportModel.swift
    public var fieldKeyContext: String                                   // stored, default ""
    public private(set) var valueBox: DimensionValueBox?                 // stored
    @discardableResult public func openValueBox(for id: OverlayDimensionID) -> Bool
    public func valueBoxDraftChanged(_ text: String)
    public func valueBoxSelectionChanged(_ selection: TextSelection?)
    public func submitValueBox() async
    public func cancelValueBox()
    public func valueBoxLostFocus()                                      // cancels unless checking
    public func placedValueBox(measuring measure: TextMeasure) -> PlacedValueBox?
}
```

  `click`: after `events.pressed()` and `stopAnimation()`, a press on a drawn dimension text is the viewport's: `clickCount ≥ 2` opens its box, and the click reaches neither the tool nor the pick; any other click first cancels an open box. Box size: measured draft width rounded up + 16, at least 72 wide, 22 high, centred on the edited dimension's text box (its last drawn place when not drawn this frame).

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aDoubleClickOnTextOpensTheBoxWithItsValueSelected()  // click 1 then 2 → draft "60", selection covers it; editor asked once
@Test func aSingleClickOnTextReachesNeitherToolNorPick()       // RecordingTool sees no click; events.clicked not called
@Test func aDimensionWithNoContentOpensNoBox()
@Test func typingChangesOnlyTheDraft()                          // drafts "7", "70": editor.commits empty, renderKey and pose unchanged
@Test func returnCommitsTheTypedTextOnce() async                // commits == [("70", id)], box nil, pose unchanged
@Test func returnWithTheOpeningTextCommitsNothing() async       // Review Focus 2: commits empty, box nil
@Test func aRefusalKeepsTheBoxOpenWithTheMessage() async        // refused("A length must be more than 0 mm.") → message set, draft kept
@Test func whileCheckingTheBoxTakesNoInput() async              // held commit: isChecking; drafts and a second submit ignored; commits.count == 1
@Test func losingFocusWhileCheckingKeepsTheBox() async
@Test func escapeOrAClickElsewhereCancels()                     // cancelValueBox / click on empty space → nil, no commit
@Test func theBoxClosesWhenItsDimensionGoesAway()               // Review Focus 5: showDimensions([]) → nil, no commit
@Test func theBoxSitsOverTheTextAndHidesIt()
// DimensionMenuTests:
@Test func aDimensionsMenuComesFromItsEditor()                  // over the text, even with a planar tool: [.host(pin, dimension: id)]; choose → performed
@Test func aToolCanOfferAMenuOffTheModel()                      // RecordingTool.menuActions → [.host(a, dimension: nil)]; choose → tool performed
```

- [ ] **Step 2: Run** `swift test --filter ValueBoxTests` and `--filter DimensionMenuTests` — Expected: FAIL.
- [ ] **Step 3: Implement.** `submitValueBox`: `draft == opening` closes with no call; otherwise `isChecking = true`, `message = nil`, `await editor.commitValue(draft, to: id)`; if the box is still that one, `.accepted` closes it, `.refused(m)` sets `message = m`, `isChecking = false`.
- [ ] **Step 4: Run** both suites and `swift test --filter CreatorViewportTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(viewport): dimension text hits, the value box and host menu hooks`.

### Task 10: The value box view

**Files:**
- Create: `Sources/CreatorViewport/View/DimensionValueBoxView.swift`
- Modify: `Sources/CreatorViewport/View/ViewportView+Parts.swift` (draw it after the dimensions when `placedValueBox` is non-nil); `Sources/CreatorApp/DocumentParts.swift` (`viewport.fieldKeyContext = AppKeyContext.panel`)
- Test: `Tests/CreatorViewportTests/Dimensions/ValueBoxRenderTests.swift`

**Interfaces:**
- Consumes: Task 9. The view: `TextField("", text: box.draft, selection: box.selection, onChange: model.valueBoxDraftChanged, onSelectionChange: model.valueBoxSelectionChanged)`, `.font(.caption)`, `.focused($isFocused)`, `.onAppear { isFocused = true }`, `.onSubmit { Task { await model.submitValueBox() } }`, `.onKeyPress(.escape) { model.cancelValueBox(); return .handled }`, `.disabled(box.isChecking)`, `.onChange(of: isFocused)` → `valueBoxLostFocus()` on a loss, `.onChange(of: box.isChecking)` refocusing after a refusal, `.keyContext(model.fieldKeyContext)` when it is not empty; the `note` above in `hintColor`, "Checking…" or the `message` below in `textColor(for: .conflicting)`. Pattern: `Sources/CreatorEditor/CommentEditorField.swift`.

- [ ] **Step 1: Write the failing tests** (render the view alone over a model with an open box: portable)

```swift
@Test func theDraftIsDrawnInTheBox() throws               // "70": 2 glyphs inside origin/size
@Test func aRefusalIsDrawnUnderTheBox() throws            // message glyphs below the box's bottom edge
@Test func checkingSaysSo() throws                        // "Checking…" glyphs below while isChecking
```

- [ ] **Step 2: Run** `swift test --filter ValueBoxRenderTests` — Expected: FAIL.
- [ ] **Step 3: Implement.** Check in MetalUI's `KeyContext.swift` that `.keyContext` with the app's "Panel" is what keeps F, + and − in the field (`AppInput`'s `!Panel` bindings); behaviour in a real window is tested in Task 14.
- [ ] **Step 4: Run** `swift test --filter ValueBoxRenderTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(viewport): the dimension value box`.

### Task 11: Adopt DIM-a (waits on MetalUI)

**Blocked until** MetalUI master has `SpatialTapGesture.Value.clickCount` (DIM-a). Run Tasks 12–16 meanwhile; do this one last or in a follow-up.

**Files:**
- Modify: `Sources/CreatorViewport/View/ViewportView+Parts.swift` (`surface`: `model.click(at:modifiers:clickCount: $0.clickCount)`), the CI pin (`METALUI_COMMIT` in `.github/workflows/xp.yml`, pinned by `CIPinTests`), `docs/metalui-gaps.md` (DIM-a row and entry: fixed, adopted, the test's name)
- Test: `Tests/CreatorAppTests/DimensionDoubleClickWindowTests.swift` (pattern: `CanvasDoubleClickWindowTests.swift`)

- [ ] **Step 1: Write the failing test** `aDoubleClickOnADimensionsTextOpensItsBox`: a window with an open sketch holding one dimension; two presses at the text's centre with click counts 1 and 2 → `app.viewport.valueBox?.id == "sketch/1"`; one press → no box.
- [ ] **Step 2: Run** `swift test --filter DimensionDoubleClickWindowTests` — Expected: FAIL (no box).
- [ ] **Step 3: Implement** the glue line and the pin bump.
- [ ] **Step 4: Run** the test and `swift test --filter CIPinTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(viewport): adopt MetalUI's tap click count (gap DIM-a)`.

### Task 12: Sketch dimensions drawn as ANSI dimensions

**Files:**
- Create: `Sources/CreatorSketchEditor/SketchDimensionDrawing.swift`; `Sources/CreatorSketch/Model/DimensionKind+Quantity.swift` (`public var quantity: DimensionQuantity`: distance and length → `.length`, radius, diameter, angle); `Sources/CreatorApp/AppModel+Dimensions.swift` (`shownDimensions()`, `refreshDimensions()`)
- Modify: `SketchEditorModel+Overlay.swift` / `SketchOverlayBuilder.swift` (no labels; `public var dimensions: [OverlayDimension]`), `Sources/CreatorApp/SketchSession.swift` (follows `editor.dimensions` with the overlay and calls `dimensionsChanged`, a closure the app sets to `refreshDimensions`; `stop()` calls it too)
- Delete: `Sources/CreatorSketchEditor/SketchDimensionLabels.swift`, `Sources/CreatorViewport/Overlay/OverlayLabel.swift`, `PlacedLabel.swift`, `ViewportOverlay.labels`, `ViewportModel.overlayLabels(measuring:)` and its loop in `ViewportView+Parts.swift`, `Tests/CreatorViewportTests/OverlayLabelTests.swift`
- Test: `Tests/CreatorSketchEditorTests/SketchDimensionDrawingTests.swift` (replaces `DimensionLabelTests.swift` and `DimensionLabelBranchTests.swift`; keep the branch test's assertion, retargeted to the geometry); `Tests/CreatorAppTests/SketchDimensionsShownTests.swift`

**Interfaces:**
- Consumes: Tasks 3, 6, 7. `SketchDimensionDrawing.dimensions(sketch:solution:plane:conflicting:wired:units:style:) -> [OverlayDimension]`, `overlayID(_ id: DimensionID) -> OverlayDimensionID` ("sketch/<rawValue>") and `dimensionID(from: OverlayDimensionID) -> DimensionID?`.
- Mapping (`P(v) = plane.point(v)`, `X(v) = plane.xAxis·v.x + plane.yAxis·v.y`, placement `.standoff`): length and point–point distance → `.linear(from: P(a), to: P(b), direction: X(unit(b−a)), side: X(normal(of: b−a)))`; point–line → the same from the point to its foot (none when they coincide); radius and diameter → `.radial(center, radius, normal: plane.normal, toward: X(direction at the arc's middle, or 45° on a circle))`; angle → `.angular(vertex: P(corner), first: P(middle of the first line), second: P(middle of the second), normal: plane.normal)`. Text: `style.text(DimensionReading(value, kind.quantity, isReference: !isDriving || wired, name: isExposed ? name : nil), units:)`, value as today (a reference shows its measurement). Tint: conflicting → `.conflicting`, reference or wired → `.dimensionReference`, else `.dimensionDriving`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func eachKindDrawsItsGeometryOnThePlane()       // on a tilted plane: anchors equal plane.point of the solved points; kinds as mapped
@Test func textsFollowTheStyleAndTheUnits()           // length 60 → "60" (inches: "2.36"), radius "R10", diameter "Ø20", angle "45°",
                                                      // reference "(60)", exposed "width = 60"
@Test func tintsSayDrivingReferenceOrConflict()
@Test func aDimensionWhoseGeometryIsGoneIsLeftOut()   // suspended projected edge; a point–line distance with the point on the line
@Test func idsAreSketchPrefixed()                     // overlayID(DimensionID(3)).rawValue == "sketch/3"; round trip; "feature/x" → nil
// SketchDimensionsShownTests:
@Test func theOpenSketchsDimensionsAreShownAndGoWithIt() async   // beginSketch → viewport.dimensions.count == 2; finishSketch → []
```

- [ ] **Step 2: Run** `swift test --filter SketchDimensionDrawingTests` and `--filter SketchDimensionsShownTests` — Expected: FAIL.
- [ ] **Step 3: Implement**; update `SketchModeRenderTests` and any test that read `overlay.labels`.
- [ ] **Step 4: Run** `swift test --filter CreatorSketchEditorTests`, `--filter CreatorViewportTests`, `--filter SketchMode` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(sketch-editor): sketch dimensions drawn as ANSI dimensions`.

### Task 13: The sketch editor in document units

**Files:**
- Modify: `Sources/CreatorSketchEditor/SketchEditorModel.swift` (`public var units: DocumentUnits = .millimetres`), `SketchEditorModel+Dimensions.swift` (rows, `setValue` parsing with `units.parse(text, quantity: kind.quantity)`, refusals naming `units.length.symbol`), `ReadoutText.swift` (lengths in `units`; "⌀" becomes "Ø"), `SketchEditorModel+Readout.swift`, `+DragReadout.swift`, `+Copies.swift`, `+Fillet.swift`, `Views/ToolOptionsView.swift`; `Sources/CreatorApp/AppModel+Sketch.swift` (the editor starts with `document.units`)
- Delete: `Sources/CreatorSketchEditor/DimensionText.swift`
- Test: `Tests/CreatorSketchEditorTests/SketchUnitsTests.swift`; existing readout tests' "⌀" → "Ø"

**Interfaces:**
- Consumes: Task 2. An editable row's `value` is `units.editText(v, quantity:) + units.suffix(for:)` ("2.3622 in"); a reference or wired row's is `units.fieldText(v, quantity:)`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func rowsShowValuesInTheDocumentsUnit()          // inches: driving 60 → "2.3622 in"; reference 60 → "2.36 in"; angle "45°"
@Test func aTypedValueFollowsTheUnitOrItsSuffix()      // inches: "2" → 50.8, "50 mm" → 50; mm: "2 in" → 50.8
@Test func refusalsNameTheUnit()                       // inches: "0" → refusal "A length must be more than 0 in."
@Test func theReadoutSpeaksTheDocumentsUnit()          // a 24.5 mm line in inches → "0.96 in · 0.0°"; r 10 circle → "Ø 0.79 in"
@Test func toolOptionsFollowTheUnit()
```

- [ ] **Step 2: Run** `swift test --filter SketchUnitsTests` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorSketchEditorTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(sketch-editor): values, readout and tool options in the document's unit`.

### Task 14: Editing a sketch dimension in the view

**Files:**
- Create: `Sources/CreatorSketchEditor/SketchEditorModel+ValueBox.swift`; `Sources/CreatorApp/AppDimensionEditing.swift`
- Modify: `Sources/CreatorSketchEditor/SketchEditorEvents.swift` (`public var checkValueCommit: @MainActor () async -> String? = { nil }`), `Sources/CreatorApp/AppModel.swift` (`let dimensionRouter: AppDimensionEditing`; `connectParts` sets `viewport.dimensionEditor = dimensionRouter`), `SketchSession.swift` (`stop()` cancels an open box)
- Test: `Tests/CreatorSketchEditorTests/SketchValueBoxTests.swift`, `Tests/CreatorAppTests/DimensionValueBoxWindowTests.swift` (pattern: `CanvasTitleTypingWindowTests.swift`; the box is opened with `viewport.openValueBox(for:)` until Task 11)

**Interfaces:**

```swift
extension SketchEditorModel: DimensionEditing {
    public func valueBoxContent(for id: OverlayDimensionID) -> DimensionValueBoxContent?   // driving and unwired: units.editText; else nil
    public func commitValue(_ text: String, to id: OverlayDimensionID) async -> DimensionCommitOutcome
}
@MainActor final class AppDimensionEditing: DimensionEditing { weak var app: AppModel? }   // "sketch/" → app.sketch?.editor
```

  `commitValue`: the inspector's checks (not a number, wired, reference, `valueProblem`) answer `.refused` with today's sentences; an unchanged value is `.accepted` with no step; the edited sketch is solved first and a status that is not `isUsable` is refused ("That value would over-constrain the sketch." for `.overConstrained`, the reason for `.failed`) with nothing committed; else `commit(…, named: SketchStepName.changeDimension)`, then `await events.checkValueCommit()` and a non-nil message is `.refused(message)`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aDrivingDimensionOpensWithItsExactValue()          // "60"; inches "2.3622"
@Test func aReferenceOrWiredDimensionOpensNoBox()
@Test func returnCommitsOneChangeDimension() async            // one commit named "Change Dimension", value 70
@Test func anUntouchedReturnIsNoStep() async                  // Review Focus 2: commitValue("60") on 60 → accepted, no commit
@Test func aValueThatCannotSolveIsRefused() async             // refused, no commit, sketch unchanged
@Test func nonNumbersAndBadValuesAreRefusedInTheBox() async   // "abc" → "“abc” isn't a number."; "0" → "A length must be more than 0 mm.";
                                                              // angle "200" → "An angle must be between 0° and 180°."; "12,5" refused
@Test func aHostRefusalAfterTheCommitReachesTheBox() async    // checkValueCommit → "Extrude: …" → .refused("Extrude: …")
// DimensionValueBoxWindowTests (FakeKernel, an open sketch with one length dimension):
@Test func typingChangesNoDocument() async throws             // type "7","0": content unchanged, undoName nil
@Test func returnCommitsOneStepAndTheCameraStays() async throws   // undoTitle "Undo Change Dimension"; camera pose unchanged
@Test func escapeCancels() async throws
@Test func aPressOnTheViewportCancels() async throws
@Test func theViewportsAndToolbarsKeysTypeIntoTheBox() async throws   // "F" and "c" land in the draft; no framing, tool unchanged
@Test func finishingTheSketchClosesTheBox() async throws      // Review Focus 5
```

- [ ] **Step 2: Run** `swift test --filter SketchValueBoxTests` and `--filter DimensionValueBoxWindowTests` — Expected: FAIL.
- [ ] **Step 3: Implement**; share the checks with `setValue` through one private helper.
- [ ] **Step 4: Run** `swift test --filter CreatorSketchEditorTests` and `swift test --filter CreatorAppTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat: edit a sketch dimension in the view (spec §4.5, §7)`.

### Task 15: Choosing units in the app

**Files:**
- Create: `Sources/CreatorApp/UnitPreference.swift` (`@MainActor protocol UnitPreference: AnyObject { var lastLength: LengthUnit { get set } }`, `InMemoryUnitPreference`, `UserDefaultsUnitPreference`, key `"MetalCreator.lastLengthUnit"`), `UnitsMenu.swift` (`Toggle`s as `ThemeMenu` does: Millimetres, Inches; precisions titled "1", "0.1", "0.01", "0.001", "0.0001"), `AppModel+Units.swift`
- Modify: `AppModel.swift` (init takes `unitPreference: any UnitPreference = InMemoryUnitPreference()`), `AppModel+Files.swift` (New starts with `DocumentUnits(length: unitPreference.lastLength)` before `savedContent` is taken, so it is not an edit), `AppCommands.swift` (View ▸ Units, View ▸ Precision), `Sources/MetalCreatorApp/main.swift` (`UserDefaultsUnitPreference()`); the editor's units follow `document.units` wherever the app refreshes after an edit, undo or redo
- Test: `Tests/CreatorAppTests/AppUnitsTests.swift`

**Interfaces:**

```swift
extension AppModel {
    public var units: DocumentUnits { document.units }
    public func setUnits(_ length: LengthUnit)   // .setUnits(DocumentUnits(length:)), UndoName.changeUnits; same unit: nothing;
                                                 // remembers the choice; cancels an open value box; refreshDimensions()
    public func setPrecision(_ digits: Int)      // UndoName.changePrecision; the unit's default stores nil
}
```

- [ ] **Step 1: Write the failing tests**

```swift
@Test func choosingInchesIsOneUndoStepAndAnEdit() async   // undoTitle "Undo Change Units"; isEdited; open sketch editor units inches
@Test func undoGivesTheOpenSketchItsUnitsBack() async
@Test func aNewDocumentUsesTheLastUnitChosen() async      // preference inches → New → units inches, isEdited false
@Test func aUnitChangeClosesAnOpenValueBox() async        // Review Focus 1: box nil, no commit
@Test func theDefaultPrecisionStoresNoKey() async         // setPrecision(1) in mm → document.units.precision == nil
@Test func savedUnitsReopen() async throws                // inches, precision 3 → save → open → equal
@Test func theMenusListUnitsAndPrecisions()               // titles in order
```

- [ ] **Step 2: Run** `swift test --filter AppUnitsTests` — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorAppTests` — Expected: PASS.
- [ ] **Step 5: Commit** `feat(app): View ▸ Units and Precision, remembered for new documents`.

### Task 16: Stage verification

- [ ] **Step 1:** `swiftlint lint --strict` — Expected: 0 violations.
- [ ] **Step 2:** `swift test 2>&1 | tee /private/tmp/claude-501/dim1-full.log`, then `grep -c "Test run with" …` → 12 and `grep -E "recorded an issue|failed after" …` → nothing; exit status 0.
- [ ] **Step 3:** `XP_TRACK=dim-1 IMAGE=metalcreator-linux:dim-1 scripts/linux-test.sh test` — Expected: exit 0, 12 "Test run with" lines, none of the two failure phrases.
- [ ] **Step 4:** Report to the orchestrator: commits, Task 11's state (DIM-a open or adopted), and anything that changed an overview interface.
