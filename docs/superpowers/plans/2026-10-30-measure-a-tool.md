# Measure, part A (the tool) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Measure tool in the viewport: pick faces, edges and corners of solids and read radius, diameter, length, area,
the exact shortest distance (OpenCascade's) and the angle between them, drawn as dimensions and listed in a glass panel.

**Architecture:** Two kernel additions (a cylinder's radius and axis point on `FaceInfo`; `Kernel.shortestDistance` over
`BRepExtrema_DistShapeShape`), two small viewport hooks (`ViewportTool.hoverChanged`, Section from Face in a tool's face
menu), and a CreatorApp `Measure/` folder: pure maths (`MeasureReadings`, `MeasureSnap`, `MeasureDimensions`), the tool
(`MeasureSession`, a `ViewportTool` with free navigation) and the panel. Measurements are not kept or saved yet (part B).

**Tech Stack:** Swift 6.4 (strict concurrency), Swift Testing, OpenCascade 7.9 through the C shim, MetalUI.

**Spec:** `docs/superpowers/specs/2026-10-30-section-measure-design.md` §4.1–§4.3, §7, §9 ("Vertices", "Measure among other
tools", "Platforms"). Part B (§4.2's section edges and mesh points, §4.4, §5's `measurements`) is not in this plan.

## Global Constraints

- OCCT only behind `Kernel`; every shim call under `OCCTKernel.serialized`; every C allocation has a `*_free`; no C++
  exception crosses into Swift (`guarded`); shim stays portable (no `M_PI`, no POSIX headers, no `__attribute__`).
- Swift Testing only. `swiftlint lint --strict`: 0. Twelve "Test run with" lines on macOS and Linux; none prints
  "recorded an issue" or "failed after" except the known `HLSLEngineTests.onTheCutTheHLSLEngineAgreesWithTheMetalEngine`.
- No Metal / CoreGraphics / CoreText outside `#if canImport(…)`. Keyboard shortcuts on MetalUI events use `.primary`.
- A MetalUI bug or missing feature goes in `docs/metalui-gaps.md`, never worked around.
- Values use the document's units (`DocumentUnits`) through `viewport.dimensionStyle.text(_:units:)` in the view and
  `units.fieldText(_:quantity:)` in the panel; messages use `Locale.messages`.
- Measure makes no command, no undo step, never marks the document edited.
- Toolchain: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; swiftlint may also need
  `TOOLCHAIN_DIR=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain`. Linux:
  `PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH" scripts/linux-test.sh test`.

## Decisions (made here; the spec leaves them to the builder)

- **Shortcut M** (free in the viewport context, the graph canvas and the sketch toolbar), bound like D:
  `KeyBinding("m", MeasureKeyAction(), context: AppKeyContext.viewport)` with D's `pointerLocation != nil` guard.
- **Tint:** measurements use the existing `.dimensionReference` tint (a measurement drives nothing). No new theme role.
- **Hover look:** an edge under the pointer is drawn over the model as an overlay polyline (`.hovered`, width 3); a snapped
  corner as an overlay point (`.hovered`, size 10); picked edges as polylines and picked corners as points in `.selected`.
  Faces keep the viewport's own face hover. Picked faces draw nothing extra (their dimension shows them).
- **Corner snap:** while an edge is hovered, its nearer end within **10 points** on screen becomes the hover (a corner). A
  closed circle (sweep ≥ 2π − 1e-9) offers its centre instead, within 10 points of the centre's screen point. Ends come from
  `EdgeCurve` (a line's start/end; an arc's start and start rotated by sweep about its axis), else the ends of the
  `DisplayMesh.edgePolylines` entry.
- **Clicks:** a pick toggles (clicking a picked element again removes it); a third pick starts a new measurement holding only
  that pick; a click on empty space clears the measurement; a click on a ghost, a guide or a mesh item (a `Solid` with
  `displayedMesh`) does nothing. Every click in Measure returns `true` from `clickedModel`, so it never selects nodes.
- **Angles** are between undirected lines and planes, reported in **0°…90°**: two straight edges by their directions, two
  flat faces by their normals, an edge and a face as 90° minus the angle between the edge and the normal. A cylinder's axis
  counts as a line for angles. Parallel gives 0°, shown.
- **Centre distance** (two circles, two cylinders, or one of each): the distance between the two centres when the axes are
  parallel within 1e-6 rad (cylinders: between the axes, i.e. the axis points' separation perpendicular to the axis); for
  non-parallel axes it is not shown.
- **What a pick shows alone:** circle or arc edge → Radius and Diameter; cylinder face → Radius and Diameter; straight edge →
  Length; any other edge → Length (`EdgeInfo.length`); flat or other face → Area; corner → its X, Y, Z (panel only).
- **Dimensions drawn:** distance as `.linear` between the two witness points (none when the distance is below 1e-9); radius
  as `.radial` with the text "R…" for an arc (sweep < 2π − 1e-9) and "Ø…" (`.diameter`) for a full circle or a cylinder;
  a straight edge's length as `.linear` along it; the angle as `.angular` at the midpoint of the distance's witness segment
  with arms along the two directions projected into the plane they span (none when parallel); area and corners: panel only.
  Dimension ids are `OverlayDimensionID("measure/<n>")`.
- **Model edits in part A:** when the scene's solids change (by identity) the measurement is cleared. Part B re-resolves.
- **Distance always goes through the kernel** (spec anti-goal: a solid's number is OpenCascade's), corners as points.
- **Layout:** the Measure panel sits in `SectionPanelDock`'s trailing column under the Section panel (8 pt apart), width 220.

## Review Focus

1. Two picks on **different parts** (two solids) — the kernel call takes two shapes; expect a distance, not a refusal
   (Task 2 test `twoSolidsAreMeasuredAgainstEachOther`).
2. **Touching or intersecting** picks (two faces sharing an edge) — distance 0, no linear dimension drawn, panel shows 0
   (Task 2 `adjacentFacesAreZeroApart`, Task 4 `aZeroDistanceDrawsNoDimension`).
3. **Moving the plane / editing while a distance is computing** — a stale result must never land on a newer measurement
   (Task 5 `aStaleDistanceIsDropped`).
4. **Starting Measure while sketching, or sketching while measuring** — exclusive; nothing left set on `viewport.tool`
   (Task 5 `sketchingEndsMeasure`, `measureIsRefusedWhileSketching`).
5. **A pick on a mesh or ghost item** — ignored, not crashing on missing topology (Task 5 `meshItemsAreNotPicked`).

---

### Task 1: A cylinder's radius and axis point on `FaceInfo`

**Files:**
- Modify: `Sources/CreatorKernel/FaceInfo.swift`, `Sources/COCCT/include/cocct.h` (`occt_face_info`),
  `Sources/COCCT/cocct_inspect.cpp` (`describe_face`), `Sources/CreatorOCCT/OCCTRawTopology.swift`,
  `Sources/CreatorOCCT/OCCTTagger.swift`, `Sources/CreatorKernel/FakeKernel.swift` (prism arc sides, fillet)
- Test: `Tests/CreatorOCCTTests/FaceRadiusTests.swift`, `Tests/CreatorKernelTests/FakeKernelFaceRadiusTests.swift`

**Interfaces:**
- Produces: `FaceInfo.radius: Double?` and `FaceInfo.axisPoint: Vector3?` (cylinders only; nil otherwise), with
  `init(id:kind:normal:area:centroid:tags:radius: Double? = nil, axisPoint: Vector3? = nil)`. For a cylinder `normal` is
  its axis direction (as today).

- [ ] **Step 1: Failing tests.** OCCT: a 40×30×10 box with a Ø8 hole (extrude a profile with a circle hole) — the hole's
  cylinder face has `radius == 4` within 1e-9, its `axisPoint` lies on the hole's axis (distance from the axis < 1e-9) and
  `normal` is ±Z; every plane face has `radius == nil`. Fake: a prism of a profile with an arc segment — the arc side face
  has the arc's radius, `axisPoint` = the arc centre on the profile plane, `normal` = the profile normal; a fillet face has
  the fillet radius.
- [ ] **Step 2:** Run `swift test --filter FaceRadius` — fails to compile.
- [ ] **Step 3: Implement.** `occt_face_info` gains `int has_axis; double radius; double axis_point[3];` (doc comment:
  cylinders only). `describe_face` fills them from `surface.Cylinder().Radius()` and `.Location()`. Swift reads them through
  `OCCTRawTopology.Face` into `FaceInfo`. FakeKernel's prism arc sides set `normal`, `radius`, `axisPoint`; its fillet sets
  `radius` and `axisPoint` (a point on the fillet's axis).
- [ ] **Step 4:** Run `swift test --filter CreatorKernelTests`, `--filter CreatorOCCTTests`, `--filter CreatorNodesTests` and
  `--filter CreatorAppTests` — all pass (the fake's arc sides now have a normal: if a test elsewhere depended on it being
  nil, report it rather than changing that test's meaning).
- [ ] **Step 5: Commit** `feat(kernel): a cylinder face's radius and axis point`.

### Task 2: `Kernel.shortestDistance`

**Files:**
- Create: `Sources/CreatorKernel/Measure/MeasureElement.swift`, `Sources/CreatorKernel/Measure/ShapeDistance.swift`,
  `Sources/CreatorKernel/FakeKernel+Measure.swift`, `Sources/COCCT/cocct_measure.cpp`,
  `Sources/CreatorOCCT/OCCTShape+Measure.swift`, `Sources/CreatorOCCT/OCCTKernel+Measure.swift`
- Modify: `Sources/CreatorKernel/Kernel.swift` (requirement + default), `Sources/CreatorKernel/KernelUnavailable.swift`
  (forward like `section`), `Sources/COCCT/include/cocct.h`
- Test: `Tests/CreatorOCCTTests/ShortestDistanceTests.swift`, `Tests/CreatorKernelTests/FakeKernelMeasureTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum MeasureElement: Sendable {
      case face(Solid, FaceID)
      case edge(Solid, EdgeID)
      case point(Vector3)
  }
  public struct ShapeDistance: Sendable, Hashable {
      public var distance: Double     // millimetres
      public var from: Vector3        // on the first element
      public var to: Vector3          // on the second
  }
  // Kernel
  func shortestDistance(between first: MeasureElement, and second: MeasureElement) throws -> ShapeDistance
  ```
  Default: `throw KernelError.unsupported("measuring")`. An out-of-range ID throws `KernelError.invalidInput` with the
  sentence "That face or edge no longer exists." (`Locale.messages` not needed).
- Template: `occt_section` / `OCCTShape+Section.swift` / `OCCTKernel+Section.swift` (untyped throws inside the
  `serialized` closure — Swift 6.4 IRGen crashes on typed throws there).

- [ ] **Step 1: Failing tests (OCCT).** On a 40×30×10 box: `oppositeFacesAreTheBoxApart` (the ±X faces: 40, witness points
  on each face, |from − to| == distance, all within 1e-9); `anEdgeToAFace` (a top edge to the bottom face: 10);
  `aCornerToAFace` (`.point` at a corner to the opposite face: 40); `adjacentFacesAreZeroApart` (0 within 1e-9);
  `twoSolidsAreMeasuredAgainstEachOther` (two boxes 5 mm apart: 5); `aHoleWallToAnOuterFace` (box with a Ø8 hole centred
  at x = 20: hole wall to the −X face is 16). Fake: `.point` to `.point`, a point to a line edge (`EdgeCurve.line`, the
  segment, clamped to its ends) and line edge to line edge (segment–segment) are exact; anything else throws
  `.unsupported`.
- [ ] **Step 2:** Run `swift test --filter ShortestDistance` and `--filter FakeKernelMeasure` — fail to compile.
- [ ] **Step 3: Implement.** C: `typedef struct { double distance; double from[3]; double to[3]; } occt_shape_distance;`
  and `int occt_shortest_distance(const occt_shape *a, int kind_a, int index_a, const double point_a[3], const occt_shape
  *b, int kind_b, int index_b, const double point_b[3], occt_shape_distance *out, occt_status *status);` (kind 0 point,
  1 face, 2 edge; indices 1-based in `map_of(…, TopAbs_FACE|EDGE)`; `a`/`b` ignored for a point; nothing to free). Build
  each sub-shape (a vertex for a point), run `BRepExtrema_DistShapeShape`, `user_error("These can't be measured.")` when
  it is not done or has no solution, and take solution 1's `PointOnShape1/2`. Swift: `OCCTKernel.shortestDistance`
  checks cancellation, validates IDs against the solid's topology, and calls the shim under `Self.serialized` (two
  sources when the solids differ). FakeKernel implements its exact cases.
- [ ] **Step 4:** Run both filters, then `--filter CreatorKernelTests` and `--filter CreatorOCCTTests` — pass.
- [ ] **Step 5: Commit** `feat(kernel): shortest distance between faces, edges and points`.

### Task 3: Viewport hooks for a measuring tool

**Files:**
- Modify: `Sources/CreatorViewport/Tool/ViewportTool.swift`, `Sources/CreatorViewport/Model/ViewportModel.swift` (where
  `hovered` is assigned), `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift`
- Test: `Tests/CreatorViewportTests/ToolHoverTests.swift`, `Tests/CreatorViewportTests/ToolFaceMenuTests.swift`

**Interfaces:**
- Produces (both with defaults in the protocol extension, so the sketch editor is unchanged):
  ```swift
  /// The model element under the pointer changed (nil: nothing, or the pointer left). Called after `hovered` is set,
  /// on every platform (on SDL when a hover pick lands).
  func hoverChanged(_ target: PickTarget?, at point: ScreenPoint?, projector: ViewportProjector)   // default: no-op
  /// Whether the face menu offers Section from Face while this tool is set (Look At is always offered).
  var offersSectionFromFace: Bool { get }                                                          // default: false
  ```

- [ ] **Step 1: Failing tests.** A test tool records `hoverChanged` calls: hovering a face reports `.face`, moving off the
  model reports nil, and a camera move under a still pointer reports again; with `offersSectionFromFace == true` the menu
  on a flat face is `[.lookAt, .sectionFromFace]`, with `false` it stays `[.lookAt]`; no tool: unchanged.
- [ ] **Step 2:** Run `swift test --filter CreatorViewportTests` — the new tests fail.
- [ ] **Step 3: Implement.** Call `tool?.hoverChanged(hovered, at: <last pointer point>, projector: <the model's
  projector>)` wherever `hovered` changes (the synchronous pick in `pointerHovered` and the SDL path when a hover pick
  lands); relax `faceMenuItems`' `guard tool == nil` to add `.sectionFromFace` (same flat-face condition as without a tool)
  when `tool.offersSectionFromFace`.
- [ ] **Step 4:** Run `swift test --filter CreatorViewportTests` — pass.
- [ ] **Step 5: Commit** `feat(viewport): tools hear the hovered element and may offer Section from Face`.

### Task 4: The measuring maths (pure)

**Files:**
- Create: `Sources/CreatorApp/Measure/MeasurePick.swift`, `Sources/CreatorApp/Measure/MeasureReadings.swift`,
  `Sources/CreatorApp/Measure/MeasureSnap.swift`, `Sources/CreatorApp/Measure/MeasureDimensions.swift`
- Test: `Tests/CreatorAppTests/Measure/MeasureReadingsTests.swift`, `MeasureSnapTests.swift`, `MeasureDimensionsTests.swift`

**Interfaces:**
- Consumes: `FaceInfo.radius/axisPoint` (Task 1), `MeasureElement`, `ShapeDistance` (Task 2).
- Produces:
  ```swift
  enum CornerEnd: Hashable, Sendable { case start, end, centre }
  enum MeasurePick: Hashable, Sendable {
      case face(solid: Int, FaceID)
      case edge(solid: Int, EdgeID)
      case corner(solid: Int, EdgeID, CornerEnd, at: Vector3)
      var solidIndex: Int { get }
      func element(in solids: [Solid]) -> MeasureElement   // a corner is .point(at)
  }
  enum MeasureQuantity: Hashable, Sendable { case distance, angle, radius, diameter, length, area, centreDistance, position }
  struct MeasureReading: Hashable, Sendable { var quantity: MeasureQuantity; var value: Double; var point: Vector3? }
  enum MeasureReadings {
      /// Everything that needs no kernel call: one pick's readings, or two picks' angle and centre distance.
      static func readings(for picks: [MeasurePick], topologies: [Int: Topology]) -> [MeasureReading]
  }
  enum MeasureSnap {
      /// The pick under the pointer: a corner when an edge's end (or a closed circle's centre) is within `radius` points.
      static func pick(for target: PickTarget?, at point: ScreenPoint, topology: Topology?, mesh: DisplayMesh?,
                       screenPoint: (Vector3) -> ScreenPoint?, radius: Double = 10) -> MeasurePick?
  }
  enum MeasureDimensions {
      static func dimensions(for picks: [MeasurePick], readings: [MeasureReading], distance: ShapeDistance?,
                             topologies: [Int: Topology], style: DimensionStyle, units: DocumentUnits) -> [OverlayDimension]
  }
  ```
  The rules are this plan's Decisions (angles 0°…90°, centre distance, single-pick readings, dimension shapes, ids
  `measure/<n>`, tint `.dimensionReference`). Copy how `FeatureDimensionBuilder` picks `direction`, `side` and
  `.standoff` for its linear and radial dimensions.

- [ ] **Step 1: Failing tests.** Readings: an arc edge (radius 3, sweep π) → radius 3 and diameter 6; a cylinder face
  (radius 4) → radius 4, diameter 8; a straight edge from (0,0,0) to (3,4,0) → length 5; a face of area 12 → area 12; a
  corner → position; two perpendicular flat faces → angle 90; two parallel faces → angle 0; an edge at 30° to a face's plane
  → angle 30; two edges at 135° directions → angle 45; two parallel cylinders with axis points 20 apart → centre distance
  20; skew cylinder axes → no centre distance; any two picks with no angle-bearing pair (corner + face) → no angle.
  Snap: an edge hovered with the pointer 4 pt from its start's screen point → `.corner(.start)`; 30 pt away → `.edge`; a
  closed circle hovered near its centre → `.corner(.centre)`; a face target → `.face`; nil → nil; an edge without curve
  uses its polyline's ends. Dimensions: a 40 mm distance → one `.linear` from `from` to `to` with text from
  `style.text(DimensionReading(40, .length), units:)`; `aZeroDistanceDrawsNoDimension`; an arc → `.radial` text "R…"; a full
  circle and a cylinder → "Ø…"; a straight edge alone → `.linear` along it; perpendicular faces with a distance →
  an `.angular` at the witness midpoint; parallel faces → no `.angular`; ids are unique and start "measure/".
- [ ] **Step 2:** Run `swift test --filter 'CreatorAppTests.Measure'` — fail to compile.
- [ ] **Step 3: Implement** the four files.
- [ ] **Step 4:** Run the filter — pass.
- [ ] **Step 5: Commit** `feat(measure): readings, corner snap and dimensions`.

### Task 5: The Measure tool in the app

**Files:**
- Create: `Sources/CreatorApp/Measure/MeasureSession.swift`, `Sources/CreatorApp/AppModel+Measure.swift`,
  `Sources/CreatorApp/Measure/MeasureKeyAction.swift`
- Modify: `Sources/CreatorApp/AppModel.swift` (`measure` property; `load` ends it), `AppModel+Sketch.swift`
  (`beginSketch` ends it), `AppModel+ModelDimension.swift` (`beginModelDimension` ends it; starting Measure ends D),
  the pick-session start (ends it), `AppModel+Scene.swift` (overlay and clear-on-new-solids), `AppModel+Dimensions.swift`
  (`dimensionsToShow()` appends the measurement's dimensions, none while sketching), `AppInput.swift` (M),
  `TopBar.swift` (a "Measure" toggle after "Section"), `AppCommands.swift` (View ▸ "Measure" / "Stop Measuring" after
  Flip Section)
- Test: `Tests/CreatorAppTests/Measure/MeasureSessionTests.swift`, `Tests/CreatorAppTests/Measure/AppMeasureTests.swift`

**Interfaces:**
- Consumes: Tasks 2–4; `ViewportModel.displayMesh(of:)`, `viewport.items`, `viewport.dimensionStyle`, `AppModel.units`.
- Produces:
  ```swift
  @MainActor @Observable final class MeasureSession: ViewportTool {
      private(set) var picks: [MeasurePick]
      private(set) var hover: MeasurePick?
      private(set) var readings: [MeasureReading]
      private(set) var distance: ShapeDistance?
      private(set) var isMeasuring: Bool          // a distance is being computed
      private(set) var problem: String?           // the kernel's refusal, `KernelError.userMessage`
      private(set) var revision: Int              // bumps on every change the scene must redraw
      func clear()
      var overlay: ViewportOverlay { get }        // hover and picked edges/corners (Decisions: Hover look)
      func dimensions(style: DimensionStyle, units: DocumentUnits) -> [OverlayDimension]
      func waitForDistance() async                // for tests and `settle()`
  }
  // AppModel
  var measure: MeasureSession? { get }
  func setMeasure(_ on: Bool)                     // refused (no-op) while sketch != nil
  ```
  `navigation` is `.free`, `offersSectionFromFace` is true, `clicked(at:)` returns false (so the click is picked),
  `clickedModel` applies the Decisions' click rules and returns true, drags return false (navigation and handles keep
  them). The distance runs in a `Task` against the kernel; each new pair bumps a generation and a result for an older one
  is dropped. `setMeasure(true)` sets `viewport.tool`; ending clears it only `if viewport.tool === measure`. The overlay
  shown is `layoutOverlay` merged with `measure.overlay` (lines, points and fills concatenated). `settle()` waits for
  `waitForDistance()`.

- [ ] **Step 1: Failing tests** (FakeKernel; picks driven by calling the tool's methods with targets).
  `clickingTwoEdgesMeasuresTheirDistance` (two parallel line edges of a fake prism: distance and a `.linear` dimension in
  `dimensionsToShow()`); `aThirdPickStartsANewMeasurement`; `clickingAPickAgainRemovesIt`; `anEmptyClickClears`;
  `clicksNeverSelectNodes` (the graph selection is unchanged after a measuring click on a feature's face);
  `aStaleDistanceIsDropped` (a held distance via a FakeKernel hook — add `setMeasureHook(_:)` like `setSectionHook` — then a
  new pair; only the new distance lands); `aRefusedDistanceShowsTheKernelsWords`; `newSolidsClearTheMeasurement`;
  `sketchingEndsMeasure`; `measureIsRefusedWhileSketching`; `startingDEndsMeasureAndMeasureEndsD`; `meshItemsAreNotPicked`;
  `ghostsAreNotPicked`; `measureNeverMarksTheDocumentEdited` (no undo step either); `theKeyMStartsMeasure` through the
  keymap with the pointer over the viewport, and not over the graph; `hoverShowsTheEdgeAndSnapsToACorner` (the overlay has a
  `.hovered` polyline, then a `.hovered` point near an end).
- [ ] **Step 2:** Run `swift test --filter 'CreatorAppTests.Measure'` — fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Run `swift test --filter CreatorAppTests` — pass (965+ before).
- [ ] **Step 5: Commit** `feat(measure): the Measure tool`.

### Task 6: The Measure panel

**Files:**
- Create: `Sources/CreatorApp/Measure/MeasurePanel.swift`
- Modify: `Sources/CreatorStyle/GlassSurface.swift` (`case measurePanel`, `.ultraThin`), `Sources/CreatorApp/Section/SectionPanelDock.swift`
  (the panel under the Section panel, 8 pt apart; doc comment), `AppLayout` only if the dock's height maths needs it
- Test: `Tests/CreatorAppTests/Measure/MeasurePanelTests.swift`

**Interfaces:**
- Consumes: `AppModel.measure`, `MeasureSession` (Task 5), `AppModel.units`.

Copy (exact): title "Measure"; with no pick "Click a face, edge or corner."; rows labelled "Distance", "Angle", "Radius",
"Diameter", "Length", "Area", "Centre distance", "Position" (X, Y, Z joined by ", "), in that order, values through
`units.fieldText(_:quantity:)` (area: the length value of the unit squared, the unit's suffix followed by "²", at
`units.fractionDigits`); "Measuring…" while `isMeasuring`; `problem` in the warning colour; buttons "Clear" (disabled with
no pick) and "Done" (`.keyboardShortcut(.escape, modifiers: [])`, ends Measure). Shown only while `measure != nil` and
`sketch == nil`; width 220 (`SectionPanel.width`).

- [ ] **Step 1: Failing tests** (headless render or model-level, as `SectionPanel`'s tests do): the prompt with no pick;
  the rows and their order for two perpendicular faces (Distance, Angle); area text "12 mm²" for a 12 mm² face in mm and
  the inch equivalent in inches; "Measuring…" while held; Done ends Measure; the panel is absent while sketching.
- [ ] **Step 2:** Run `swift test --filter MeasurePanel` — fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Run `swift test --filter CreatorAppTests` and `swift test --filter CreatorStyleTests` — pass.
- [ ] **Step 5: Commit** `feat(measure): the Measure panel`.

### Task 7: Checks, docs and the full run

**Files:**
- Modify: `docs/verification/human-checks.md` (group ME-A), `CLAUDE.md` (status line after Section part B; `CreatorKernel`
  bullet: `FaceInfo.radius/axisPoint`, `Kernel.shortestDistance` over `cocct_measure.cpp`; `CreatorApp` bullet: `Measure/`)

- [ ] **Step 1:** Write ME-A-1… covering: M and the top bar toggle start and end Measure, Esc ends it; hover look on edges
  and corners; a hole's Ø; a box's wall thickness between two faces (exact); a corner-to-face distance; the angle of a
  chamfer face to its neighbour; two parts' distance; a click never selects a node; handles still drag; the face menu
  offers Look At and Section from Face; an edit clears the measurement; sketching ends Measure; Linux build (one check).
- [ ] **Step 2:** CLAUDE.md status: "Measure, part A (the tool; plan `docs/superpowers/plans/2026-10-30-measure-a-tool.md`)
  code is done; its human checks (group ME-A) are pending." plus the module notes above.
- [ ] **Step 3:** Full `swift test` (12 lines; only the known failure), `swiftlint lint --strict` (0), Linux
  `scripts/linux-test.sh test` (exit 0, 12 lines).
- [ ] **Step 4: Commit** `docs(measure): part A checks and status`.
