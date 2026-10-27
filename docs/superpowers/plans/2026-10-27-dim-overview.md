# Driving Dimensions: Overview and Shared Interfaces

> **For agentic workers:** this file is not a task list. It splits the spec into four stage plans, orders them, and fixes the
> names and signatures every stage shares. Each stage plan (`2026-10-27-dim-<n>-*.md`) is executed with
> superpowers:subagent-driven-development (recommended) or superpowers:executing-plans, and reads this file first.

**Goal:** ANSI dimensions on the part and in sketches, edited in place (double-click, type, Return), in millimetres or inches.

**Architecture:** Value types for units and dimension geometry live in `CreatorGeometry` (every module reaches them). The look
(`DimensionStyle`), the world-space primitive (`OverlayDimension`), its screen layout and the value box live in
`CreatorViewport`, which still never learns about the graph. Dimensions are drawn as MetalUI shapes and text over the GPU
surface (like today's labels), never by the renderer, so they are never in the ID pass, framing or `sceneBounds`. All hit
testing of dimension text is the `ViewportModel`'s, from its last laid-out boxes; the views take no pointer. The sketch editor
and (DIM-3) the app shell answer the viewport through one protocol, `DimensionEditing`.

**Tech Stack:** Swift 6.4, MetalUI (`../MetalUI`, read only), Swift Testing, OpenCascade through `CreatorOCCT` (DIM-3/4 only).

**Spec:** `docs/superpowers/specs/2026-10-27-driving-dimensions-design.md` (commit ba8dd21). Research notes for §5 numbers:
`/private/tmp/claude-501/-Users-maxburger-Developer/89808cd9-ba62-46fa-aaed-bac3e12fa878/scratchpad/ansi-dimensions.md` and
`fusion-dimensioning.md` beside it (session scratch; the values that matter are copied into the plans).

## MetalUI gaps (file before DIM-1 starts its Task 9)

| Gap | What | Who waits |
|---|---|---|
| **DIM-a** | `SpatialTapGesture.Value` has no click count. The viewport's click is a `SpatialTapGesture` on the surface, so it cannot tell the second click of a double-click from a new click; `DragGesture.Value.clickCount` exists (S5-b) but the viewport's primary drag has a non-zero minimum distance and never reports a click. Wanted: `SpatialTapGesture.Value.clickCount`, the platform's count of the press that ended the tap (`NSEvent.clickCount` / SDL's `clicks`), MetalUI-only like `modifiers` (GI-a). A `count: 2` tap on the surface would hold every single click for the double-click interval, and a tap gesture on the dimension's text view would make it the press's target, swallowing the right and middle drags, scroll, pinch and hover that start on it (the arena is the target and its ancestors only, `Gesture.swift` `IX-D`), so neither is used. | DIM-1 Task 11 (one line of glue). Everything else in DIM-1 is model-tested with `clickCount: 2` passed directly. |

No other limit was found: a focused `TextField` over the viewport (`.focused`, `.onAppear { isFocused = true }`), its
selection (C25), `.onSubmit`, `.onKeyPress(.escape)`, `.disabled`, `keyContext`, `.resignsFocusOnPress()` (C24),
`Path`/`Shape` fill and stroke, and the located `.contextMenu` all exist on MetalUI master `98304aab`. A focused field's editing
keys run before `Button` shortcuts (`Window.swift` key stages), so the sketch toolbar's letter keys type into the box; the
viewport's keymap keys (F, +, −) type into it once the box carries the `Panel` key context (DIM-1 Task 10).
Any new limit met while executing is added to `docs/metalui-gaps.md` and sent to the MetalUI session; never worked around.

## Global Constraints (every stage)

- `swift-tools-version: 6.4`, Swift 6 language mode, full strict concurrency: no `@unchecked Sendable`, no `nonisolated(unsafe)` to silence a diagnostic.
- Tests are Swift Testing only (`import Testing`, `@Test`, `#expect`); no XCTest.
- Shared models are `@MainActor @Observable final class`.
- Portable code: no CoreText, CoreGraphics, ImageIO or Metal outside a `#if canImport(…)` file or block; keys and modifier checks on MetalUI events say `.primary`; the dimension views are MetalUI shapes and text only.
- Colour hex values only in `CreatorStyle`; everything else names a `ThemeRole` / `OverlayTint`.
- Undo names are `UndoName` / `SketchStepName` constants: no numbers, never typed text (a dimension's or parameter's name).
- File format: version 10 from DIM-1 (below); every new key optional, written only when it differs from its default, decoded with a default; a file of format 1 to 9 opens unchanged and is written as 10.
- `swiftlint lint --strict` reports zero violations before each commit.
- Light verification per task: `swift build --build-tests`, then `swift test --filter <the touched suites>`. Full suite at the end of each stage: exit 0, exactly 12 "Test run with" lines, and no "recorded an issue" or "failed after" in the output.
- Never `pkill`/`killall` swift, swift-test or xctest broadly: MetalUI's session shares this Mac. Kill only the PIDs your own command started.
- Never modify `../MetalUI` (read it freely). A MetalUI limit becomes a gap entry in `docs/metalui-gaps.md`.
- Commit messages end with:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_0164u3kDFFDgzFW7axHFXzbS
  ```

## Stages, order and branches

| Stage | Plan | Branch / worktree | Starts after | Touches |
|---|---|---|---|---|
| DIM-1 foundation | `2026-10-27-dim-1-foundation.md` | `dim-1-foundation`, `/Users/maxburger/Developer/worktrees/dim-1` | now | Geometry, Viewport, Style, Graph (units, format 10), SketchEditor, App |
| DIM-2 sketch | `2026-10-27-dim-2-sketch.md` (to write) | `dim-2-sketch`, `…/worktrees/dim-2` | DIM-1 merged | Sketch, SketchEditor (and SketchStore in App for label placement) |
| DIM-3 model | `2026-10-27-dim-3-model.md` (to write) | `dim-3-model`, `…/worktrees/dim-3` | DIM-1 merged | Graph (DimensionSpec, pins), Nodes, App |
| DIM-4 acceptance | `2026-10-27-dim-4-acceptance.md` (to write) | `dim-4-acceptance`, `…/worktrees/dim-4` | DIM-2 and DIM-3 merged | App, Nodes tests, docs, CLAUDE.md |

DIM-2 and DIM-3 run in parallel: DIM-1 fixes every seam they share (the menu hooks, the dimension-ID prefixes, the
format version, `AppModel.shownDimensions()`), so their only common files are `UndoName.swift` /
`SketchStepName.swift` (append-only constants) and the GraphFile doc comment (append one sentence each). DIM-1 Task 11
(DIM-a) may land after DIM-1's other tasks; DIM-2 and DIM-3 do not wait for it.

**Worktrees.** `Package.swift` names `../MetalUI`, so a worktree at `/Users/maxburger/Developer/worktrees/<name>` needs
`/Users/maxburger/Developer/worktrees/MetalUI` to be the MetalUI checkout. **Today that path is a plain directory of MetalUI
build logs, not a link**; the orchestrator (not an agent) moves the logs and creates
`ln -s ../MetalUI /Users/maxburger/Developer/worktrees/MetalUI`. If an agent must instead edit the path in `Package.swift`
to `../../MetalUI`, it never stages or commits that edit (`git diff --cached Package.swift` is empty before every commit).
Linux runs use a track of their own: `XP_TRACK=dim-<n> IMAGE=metalcreator-linux:dim-<n> scripts/linux-test.sh test`.

## Decisions taken here that touch the spec, the file or what the user sees

1. **Format 10, bumped in DIM-1.** DIM-2 adds `DimensionKind` cases, which a format-9 reader cannot decode (CLAUDE.md:
   such a change requires a bump), and an older reader would silently drop units, pins and label placements on save (the
   spec's own condition; cable ties bumped to 9 for the same reason). One bump covers the project: 10 adds the document's
   `units`, then (DIM-2) the new dimension kinds and `labelPoint`, then (DIM-3) `dimensionPins`. No release ships between the
   stages, so they share 10.
2. **Units live on the top-level `Graph`** (key `units`), not in `ViewState`: changing them is an undoable step ("Change
   Units", "Change Precision") and marks the document edited, as a parameter change does, so Close asks to save. The spec
   allowed either.
3. **Dimensions are MetalUI views, not GPU lines**: always drawn over the part (ANSI practice), hidden while the camera
   animates (as labels are, gap M4-b), never in the ID pass, framing or `sceneBounds`.
4. **Text is hit-tested by the model**; a single click on a dimension's text is the viewport's and reaches neither the
   sketch tool nor the face pick (nothing happens in DIM-1; DIM-3 may select). Until DIM-a is adopted a double-click does
   not open the box in the running app.
5. Numbers: Ø is U+00D8 (Latin-1, in every font we ship; the readout's "⌀" U+2300 becomes "Ø" too); angles show at most one
   decimal, trailing zeros dropped, in any unit; an exposed dimension keeps its "name = " prefix and a reference wraps the whole
   text: "(width = 60)". Precision defaults: 1 place in millimetres, 2 in inches; range 0 to 4; choosing a unit resets
   precision to that unit's default.
6. Value boxes and the sketch inspector's value fields open with up to 4 decimals (mm) or 5 (in), trimmed, so opening and
   pressing Return without typing changes nothing (and is no undo step).
7. Two new theme roles, `dimensionDriving` and `dimensionReference` (group "Dimensions", last), equal in the built-ins to
   the focus and comment colours. Sketch dimensions change colour: driving was the foreground (white in Dracula), now cyan.
8. View ▸ Units (Millimetres, Inches) and View ▸ Precision (1, 0.1, 0.01, 0.001, 0.0001) are the entry point; the app
   remembers the last length unit chosen for new documents. The viewport's grid label stays in millimetres (known
   inconsistency, like the node inspector, spec §6).
9. The sketch editor's tool-option fields (fillet radius and the like) follow the document unit too, with its other fields.
10. `OverlayLabel`, `PlacedLabel` and `ViewportOverlay.labels` are removed: sketch dimensions were their only user.
11. **Flip detection (spec §7)** is DIM-2's: the solver has no runtime flip detector. DIM-2 adds
    `SketchFlipCheck` (loop orientation signs before and after the solve); sized there as one task.

## Shared interfaces

Producer stage in brackets. Signatures are the contract; a stage that needs to change one says so in its plan and in this
file.

### CreatorGeometry `Sources/CreatorGeometry/Units/` [DIM-1]

```swift
public enum LengthUnit: String, Sendable, Hashable, CaseIterable, Codable {
    case millimetres = "mm", inches = "in"
    public var millimetresPerUnit: Double      // 1, 25.4
    public var symbol: String                  // "mm", "in"
    public var title: String                   // "Millimetres", "Inches"
    public var defaultPrecision: Int           // 1, 2
}
public enum DimensionQuantity: Sendable, Hashable {
    case length, radius, diameter, angle, count
    public var isLength: Bool                  // length, radius, diameter
}
public struct DocumentUnits: Sendable, Hashable, Codable {
    public static let precisionRange: ClosedRange<Int>   // 0...4
    public static let millimetres: DocumentUnits         // .init()
    public var length: LengthUnit
    public var precision: Int?                           // nil: length.defaultPrecision
    public init(length: LengthUnit = .millimetres, precision: Int? = nil)
    public var fractionDigits: Int
    public func value(fromMillimetres millimetres: Double) -> Double
    public func millimetres(fromValue value: Double) -> Double
    public func editText(_ value: Double, quantity: DimensionQuantity) -> String     // "60", "2.3622", "45", "6"
    public func fieldText(_ value: Double, quantity: DimensionQuantity) -> String    // "12.5 mm", "2.25 in", "30°"
    public func readoutNumber(_ millimetres: Double) -> String                       // "24.5", "0.96"
    public func parse(_ text: String, quantity: DimensionQuantity) -> Double?        // mm, degrees or a count
}
```

`Sources/CreatorGeometry/Dimensions/` [DIM-1]:

```swift
public enum DimensionPlacement: Sendable, Hashable {
    case standoff                // the style's standoff from the geometry, in screen points
    case through(Vector3)        // the dimension line / leader end / arc passes through this world point
}
public enum DimensionGeometry: Sendable, Hashable {
    case linear(from: Vector3, to: Vector3, direction: Vector3, side: Vector3, placement: DimensionPlacement)
    case radial(center: Vector3, radius: Double, normal: Vector3, toward: Vector3, placement: DimensionPlacement)
    case angular(vertex: Vector3, first: Vector3, second: Vector3, normal: Vector3, placement: DimensionPlacement)
    public var planeNormal: Vector3     // linear: direction × side
}
```

### CreatorViewport `Sources/CreatorViewport/Dimensions/` [DIM-1]

```swift
public struct DimensionReading: Sendable, Hashable {
    public var value: Double; public var quantity: DimensionQuantity
    public var count: Int?; public var isReference: Bool; public var name: String?
    public init(_ value: Double, _ quantity: DimensionQuantity, count: Int? = nil, isReference: Bool = false, name: String? = nil)
}
public struct DimensionStyle: Sendable, Hashable {
    public enum Notation: Sendable, Hashable { case ansi }   // ISO seam: `.iso` and `static let iso` later (spec §9)
    public var notation: Notation
    public var arrowLength, arrowWidth, extensionGap, extensionOvershoot, textGap: Double
    public var standoff, leaderLength, shoulderLength, lineWidth, edgeOnLimit, pinMarkRadius: Double
    public static let ansi: DimensionStyle
    public func text(_ reading: DimensionReading, units: DocumentUnits) -> String
}
public struct OverlayDimensionID: Hashable, Sendable, Comparable {
    public var rawValue: String
    public init(_ rawValue: String)
}
public struct OverlayDimension: Hashable, Sendable {
    public var id: OverlayDimensionID
    public var geometry: DimensionGeometry
    public var text: String
    public var tint: OverlayTint          // .dimensionDriving, .dimensionReference, .conflicting, .selected
    public var isPinned: Bool             // draws the pin mark (DIM-3 sets it)
    public var isGhosted: Bool            // drawn faded (DIM-3: pinned feature dimensions while sketching)
}
public struct HostMenuAction: Hashable, Sendable { public var title: String; public var key: String }
public struct DimensionValueBoxContent: Hashable, Sendable { public var text: String; public var note: String? }
public enum DimensionCommitOutcome: Hashable, Sendable { case accepted, refused(String) }

@MainActor public protocol DimensionEditing: AnyObject {
    func valueBoxContent(for id: OverlayDimensionID) -> DimensionValueBoxContent?   // nil: not editable, no box
    func commitValue(_ text: String, to id: OverlayDimensionID) async -> DimensionCommitOutcome
    func menuActions(for id: OverlayDimensionID) -> [HostMenuAction]                 // default []
    func performMenuAction(_ action: HostMenuAction, for id: OverlayDimensionID)     // default: nothing
}
```

`ViewportModel` gains [DIM-1]: `dimensions`, `showDimensions(_:)`, `dimensionStyle`, `placedDimensions(measuring:)`,
`dimension(at:)`, `click(at:modifiers:clickCount:)`, `weak var dimensionEditor`, `fieldKeyContext`, `valueBox`,
`openValueBox(for:)`, `valueBoxDraftChanged(_:)`, `valueBoxSelectionChanged(_:)`, `submitValueBox() async`,
`cancelValueBox()`, `valueBoxLostFocus()`, `placedValueBox(measuring:)`; `ViewportMenuItem.host(HostMenuAction, dimension: OverlayDimensionID?)`;
`ViewportTool.menuActions(at:) -> [HostMenuAction]` and `performMenuAction(_:)` (defaults: none). Exact signatures in DIM-1
Tasks 6 and 9. `OverlayTint` gains `.dimensionDriving`, `.dimensionReference` [DIM-1].

**Dimension IDs:** `"sketch/<DimensionID.rawValue>"` for the open sketch's dimensions (DIM-1, `SketchDimensionDrawing.overlayID`);
`"feature/…"` is reserved for DIM-3, which defines the rest of the string (node, input or sketch dimension, instance).

### CreatorStyle [DIM-1]

`ThemeColors.dimensionDriving`, `.dimensionReference`; `ThemeRole("dimensionDriving", "Driving dimension", .dimensions, …)`,
`ThemeRole("dimensionReference", "Reference dimension", .dimensions, …)`; `ThemeRoleGroup.dimensions` ("Dimensions"), last.

### CreatorGraph [DIM-1 unless marked]

```swift
extension Graph { public var units: DocumentUnits }                 // key "units", written when != .millimetres
extension GraphCommand { case setUnits(DocumentUnits) }               // affectsResults false, touches no node
extension UndoName { static let changeUnits = "Change Units"; static let changePrecision = "Change Precision" }
extension DocumentModel { public var units: DocumentUnits }           // content.graph.units
GraphFile.currentFormatVersion == 10
// [DIM-3]
public struct DimensionPin: Sendable, Hashable, Codable, Comparable { public var node: NodeID; public var target: DimensionTarget }
public enum DimensionTarget: Sendable, Hashable, Codable { case input(SocketName), sketchDimension(DimensionID) }
extension Graph { public var dimensionPins: [DimensionPin] }          // key "dimensionPins", sorted, written when non-empty
extension GraphCommand { case pinDimension(DimensionPin), unpinDimension(DimensionPin) }   // affectsResults false
extension UndoName { static let pinDimension = "Pin Dimension"; static let unpinDimension = "Unpin Dimension" }
public struct DimensionSpec: Sendable, Hashable {
    public var target: DimensionTarget
    public var geometry: DimensionGeometry
    public var quantity: DimensionQuantity
    public var value: Double              // mm, degrees or a count
    public var count: Int?                // NX: one constant over N instances
}
extension NodeOutputs { public var dimensions: [DimensionSpec] }    // appended per run; collected into NodeResult
extension NodeResult { public var dimensions: [DimensionSpec] }
```

Group, Ungroup, Make Unique and paste move and rename pins as they do ties (`GroupCommands`, `GroupScopes`) [DIM-3].

### CreatorSketch / CreatorSketchEditor

[DIM-1] `DimensionKind.quantity: DimensionQuantity` (in CreatorSketch; DIM-2 extends it for its kinds);
`SketchEditorModel: DimensionEditing`; `SketchEditorModel.units: DocumentUnits`; `SketchEditorModel.dimensions:
[OverlayDimension]`; `SketchEditorEvents.checkValueCommit: @MainActor () async -> String?` (default `{ nil }`): after a value-box
commit, the host evaluates and answers a refusal message having already taken the step back (DIM-3 implements it, spec §7).

[DIM-2] `DimensionKind.centreDistance(SketchEntityID, SketchEntityID)`, `.lineDistance(SketchEntityID, SketchEntityID)`,
`.horizontalDistance(SketchEntityID, SketchEntityID)`, `.verticalDistance(SketchEntityID, SketchEntityID)`, each with a
residual and analytic Jacobian in `SketchSolver`; `SketchDimension.labelPoint: Vector2?` (plane coordinates; `nil`: the style's
standoff; DIM-1's drawing turns a non-nil one into `.through`); `SketchFlipCheck.isFlipped(_ before: SketchSolution, _ after:
SketchSolution, in sketch: Sketch) -> Bool`; `SketchStepName.placeDimension = "Place Dimension"`. The D tool's value box reuses
`ViewportModel.openValueBox(for:)` with the pending dimension's ID `"sketch/new"`; right-click while placing is
`ViewportTool.menuActions(at:)`.

### CreatorApp [DIM-1 unless marked]

`AppModel.shownDimensions() -> [OverlayDimension]` (DIM-1: the open sketch's; DIM-3 adds contextual and pinned feature
dimensions), `AppModel.refreshDimensions()`, `AppModel.dimensionRouter: AppDimensionEditing` (forwards `"sketch/"` IDs to the
open sketch editor; DIM-3 adds `"feature/"`), `AppModel.setUnits(_:)`, `AppModel.setPrecision(_:)`, `UnitPreference` protocol
with `InMemoryUnitPreference` and `UserDefaultsUnitPreference`. [DIM-3] `AppModel.commitChecked(…) async ->
DimensionCommitOutcome` (perform, evaluate, invisible rollback on an error downstream, spec §7), the feature-dimension
builder beside `HandleBuilder`, the private-chain walk (spec §3.1) and the selection rule (§3.3).

### Stage scopes (what each later plan must cover)

- **DIM-2**: spec §4.2 (value box on placement, placement chooses horizontal/vertical/aligned, right-click Radius/Diameter
  and Driving/Reference), §4.3 (the four kinds, 2X display from Equal sets), §4.4 (over-define → reference), §7's flip refusal,
  §8's `labelPoint` (dragging a dimension's text moves it: one "Place Dimension" step).
- **DIM-3**: spec §3.1–§3.4 and §7 (rollback): `DimensionSpec` from Sketch, Extrude, Revolve, Hole/Boss-Pin/Slot Pattern,
  Linear/Grid/Circular Pattern, Fillet, Chamfer, Box/Cylinder/Sphere and their implicit twins, Shell; contextual display by
  node selection and face click (`TopoTag`); pins (saved, context menu through `DimensionEditing.menuActions`, remapped by
  Group/Ungroup/Make Unique/paste); parameter-wired dims editable with "Width (parameter, used by 3 features)" as the box's
  `note`; other wired dims as references with the source in a hover chip (model-side hover, as clicks); implicit nodes
  (§3.4); decluttering overlapping texts (spec §3.3's bar).
- **DIM-4**: spec §3.5 (model dimension tool: two picks tracing to one Sketch add a sketch dimension and open its box; else the
  chip "These come from different features: a measurement tool is planned"), the new sketch-based bracket fixture, §1's
  success scenario end to end in mm and inches, the §7.2 bracket's private-chain and parameter tests, human checks group DIM,
  the CLAUDE.md project-state and module lines, the sketcher spec erratum (S5c reversed), the MetalUI-gaps summary row status.
