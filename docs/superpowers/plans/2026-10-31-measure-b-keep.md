# Measure, part B: section edges, mesh points, kept measurements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure picks section edges and points on meshes, keeps finished measurements on screen and in the file, and
re-resolves and re-measures every kept one after each evaluation.

**Architecture:** A pick is made against the scene as part A does (`MeasurePick`, by solid index), then turned into a
stored, scene-free `MeasureAnchor` (tags, not IDs: `FacePick`, `EdgePick`, a section edge by its source face, a mesh point
by its position). Every scene or section change resolves the anchors back to `MeasurePick`s (`MeasureResolver`) and
measures them again: the current measurement in `MeasureSession`, the kept ones in a new `MeasureBook` owned by
`AppModel`. Kept measurements live in `DocumentModel.measurements` and are saved as `ViewState.measurements`, an optional
key (no format bump). Distances to section curves and polylines go through the kernel with two new `MeasureElement` cases.

**Tech Stack:** Swift 6.4 (strict concurrency), Swift Testing, OpenCascade 7.9 through the C shim, MetalUI.

**Spec:** `docs/superpowers/specs/2026-10-30-section-measure-design.md` (§4, §5, §9, §10). Part A's plan:
`docs/superpowers/plans/2026-10-30-measure-a-tool.md`.

## Global Constraints

- OCCT only behind `Kernel`, every shim call under `OCCTKernel.serialized`; every C allocation has a `*_free` (the new
  operand struct allocates nothing); no C++ exception crosses into Swift; shim stays portable (no `M_PI`, use `cocct::kPi`).
- No CoreGraphics, Metal or CryptoKit outside `#if canImport(…)`; tests that need OCCT are gated `#if canImport(CreatorOCCT)`.
- Swift Testing only; `swiftlint lint --strict` reports 0; macOS and Linux print 12 "Test run with" lines and nothing prints
  "recorded an issue" or "failed after" (the known `HLSLEngineTests.onTheCutTheHLSLEngineAgreesWithTheMetalEngine` failure
  predates the branch).
- Measurements are view state: no command, no undo step, no edited dot, nothing in exports. New starts without them.
- `ViewState.measurements` is an optional key, written only when non-empty; an unreadable entry is dropped on reading,
  never the whole file. `GraphFile.currentFormatVersion` stays 10.
- Panel text: "No longer found" for a kept measurement that does not resolve; a mesh- or polyline-derived value is prefixed
  "≈ "; numbers through `DocumentUnits` as part A's panel does.
- A MetalUI gap goes in `docs/metalui-gaps.md` and to the `metalui-42` session, never worked around.

## Rulings (calls made in this plan, not discussed with the user)

1. **Keeping.** The third click keeps the current two-pick measurement and starts a new one with that click; the panel's
   **Keep** button keeps the current measurement of one or two picks (a hole's diameter). Only kept measurements are saved.
2. **Kept ones are always drawn** outside sketch mode (their dimensions, not their pick highlights), and the Measure panel
   shows while Measure runs **or** while any kept measurement exists, so they can be removed without starting the tool.
3. **Stored tags are the viewport's own.** Inside a group the viewport's topology already carries top-level scoped tags
   (`NodeID.scoped`), so anchors store them as they are, as the section's face reference does; no `relativeToLevel`. A
   measurement whose part is not shown (another level, Selected-node preview) reads "No longer found", the same known
   limitation as the section's face.
4. **Mesh points** are picked on click only (a CPU ray cast through `ViewportModel.surfacePoint(at:solidIndex:)`), never on
   hover: a lattice has millions of triangles. A mesh point is stored by its world position and always resolves. A distance
   from a mesh point is the kernel's exact distance from that point, shown "≈" because the point came from a mesh.
5. **Section edges** are picked on the CPU within 6 points on screen, before the model pick, and are hovered the same way.
   They snap to no vertex. A solid's section edge is stored as its source face's `FacePick`, its index among that face's
   pieces in the section, how many there were, and its midpoint: the index is used when the count is unchanged, else the
   piece nearest the midpoint. A mesh's section edge (one closed loop from `MeshSlicer`) is stored as the point on it
   nearest the click and resolves to the mesh piece nearest that point moved onto the current section plane, within 1 mm.
   With the section off, a section-edge anchor does not resolve ("No longer found").
6. **The mesh resolution** shown beside a "≈" value is the mesh's own (`Solid.displayedMeshResolution`, set where
   `MeshSolids` makes the display solid); the text is `≈ 12.3 mm · mesh 0.4 mm`. A polyline from a solid's section has no
   resolution: just `≈ 12.3 mm`.
7. **Resolving a pick across parts.** An anchor resolves on the first shown, opaque, non-guide item (scene order) where it
   names exactly one face or edge; a guess (`isAmbiguous`) is used, as the section uses one.

## Review Focus

1. A kept measurement whose part is edited so its pick matches two edges: it must read "No longer found", never measure
   the first match (Task 4, `anAnchorMatchingTwoEdgesDoesNotResolve`).
2. An evaluation that lands while a kept distance is being computed: the older result must never overwrite the newer
   (Task 6, `aNewerRefreshDropsAnOlderDistance`).
3. A file with one damaged measurement entry beside good ones: the good ones open (Task 2,
   `aDamagedMeasurementIsDroppedAlone`).
4. Undo after keeping a measurement: undo must not remove it or touch anything else, and the document is not edited
   (Task 6, `keepingMakesNoUndoStepAndNoEdit`).
5. The section switched off while a section edge is the current pick: the current measurement must show "No longer found",
   not crash or keep a stale distance (Task 5, `turningTheSectionOffLosesASectionEdgePick`).

---

### Task 1: Measuring section curves and polylines in the kernel

**Files:**
- Modify: `Sources/CreatorKernel/Measure/MeasureElement.swift`
- Modify: `Sources/COCCT/include/cocct.h` (the header holding `occt_shortest_distance`), `Sources/COCCT/cocct_measure.cpp`
- Modify: `Sources/CreatorOCCT/OCCTShape+Measure.swift`, `Sources/CreatorOCCT/OCCTKernel+Measure.swift`
- Modify: `Sources/CreatorKernel/FakeKernel+Measure.swift`
- Test: `Tests/CreatorKernelTests/FakeKernelMeasureTests.swift` (extend), `Tests/CreatorOCCTTests/ShortestDistanceTests.swift` (extend; find the file part A added with `grep -rl shortestDistance Tests/CreatorOCCTTests`)

**Interfaces:**
- Produces: `MeasureElement.curve(EdgeCurve)` (a line or a circle arc, exact) and `MeasureElement.polyline([Vector3])`
  (at least two points). `Kernel.shortestDistance(between:and:)` takes them unchanged.

- [ ] **Step 1: Write the failing tests.** FakeKernel (`FakeKernelMeasureTests`):
  `aPointToAPolylineIsTheNearestSegment` — point (5, 3, 0) to polyline [(0,0,0), (10,0,0), (10,10,0)] gives distance 3,
  `to` (5, 0, 0); `aLineCurveMeasuresAsItsSegment` — `.curve(.line(start: (0,0,0), end: (10,0,0)))` to point (5, 4, 0) is 4;
  `anArcIsUnsupported` — `.curve(.circle…)` throws `KernelError.unsupported`; `aOnePointPolylineIsRefused` throws
  `KernelError.invalidInput`. OCCT (`#if canImport(CreatorOCCT)`): `aPointToAnArcIsExact` — a quarter arc, centre origin,
  axis +Z, radius 10, start (10,0,0), sweep π/2, to point (20, 0, 0): distance 10 to 1e-9, `to` (10, 0, 0);
  `aClockwiseArcIsTheSameSet` — sweep −π/2 from (10,0,0) to point (0, −20, 0) is 10; `aPolylineToAFaceIsExact` — a
  20 × 20 × 10 mm extrusion centred on the origin (top face z = 10) to polyline [(0,0,15), (5,0,12)] is 2.
- [ ] **Step 2: Run** `swift test --filter FakeKernelMeasureTests` and `swift test --filter ShortestDistanceTests`. Expected:
  compile failure (no such cases).
- [ ] **Step 3: Implement.** Replace `occt_shortest_distance`'s eight scalar parameters with two operand structs:

  ```c
  typedef struct {
      const occt_shape *shape;   // kinds 1 and 2
      int kind;                  // 0 point, 1 face, 2 edge, 3 polyline, 4 circle arc
      int index;                 // 1-based, kinds 1 and 2
      double point[3];           // kind 0
      const double *points;      // kind 3: point_count x, y, z triples (borrowed)
      int point_count;           // kind 3, at least 2
      double centre[3], axis[3], start[3];  // kind 4
      double radius, sweep;      // kind 4; a negative sweep runs clockwise about axis
  } occt_measure_operand;
  int occt_shortest_distance(const occt_measure_operand *a, const occt_measure_operand *b,
                             occt_shape_distance *out, occt_status *status);
  ```

  Kind 3 is `BRepBuilderAPI_MakePolygon` (fewer than 2 points: `user_error("These can't be measured.")`); kind 4 is
  `BRepBuilderAPI_MakeEdge(gp_Circ(gp_Ax2(centre, axis', xdir), radius), 0, |sweep|)` with `axis' = axis` for a positive
  sweep and `-axis` for a negative one, `xdir = start − centre` normalised (refuse a zero radius or a start on the axis).
  `OCCTMeasureOperand` gains `.polyline([Vector3])` and `.arc(…)`; it keeps the points array alive across the call.
  `.curve(.line(a, b))` maps to a two-point polyline. FakeKernel measures `.polyline` and `.curve(.line)` as segments
  (minimum over segments with its existing `closestPoints`/`closest`), and throws `unsupported("measuring a curved edge")` for an arc.
- [ ] **Step 4: Run** both filters, then `swift test --filter CreatorOCCTTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(measure): measure to section curves and polylines`.

### Task 2: The stored form and `ViewState.measurements`

**Files:**
- Create: `Sources/CreatorGraph/Measure/MeasureAnchor.swift`, `Sources/CreatorGraph/Measure/KeptMeasurement.swift`
- Modify: `Sources/CreatorGraph/ViewState.swift`, `Sources/CreatorGraph/DocumentModel.swift`
- Modify: `Sources/CreatorApp/Measure/MeasurePick.swift` (delete `CornerEnd`, now in CreatorGraph)
- Test: `Tests/CreatorGraphTests/MeasureViewStateTests.swift`

**Interfaces:**
- Produces (all `public`, `Hashable`, `Sendable`, `Codable`):

  ```swift
  public enum CornerEnd: String { case start, end, centre }            // moved from CreatorApp
  public struct SectionEdgeAnchor { public var face: FacePick; public var index: Int; public var count: Int; public var midpoint: Vector3 }
  public enum MeasureAnchor {
      case face(FacePick)
      case edge(EdgePick)
      case corner(EdgePick, CornerEnd)
      case sectionEdge(SectionEdgeAnchor)
      case meshSectionEdge(Vector3)
      case meshPoint(Vector3)
  }
  public struct KeptMeasurement: Identifiable { public var id: UUID; public var anchors: [MeasureAnchor] }  // 1 or 2 anchors
  ```

  `MeasureAnchor` encodes as one key naming its case (`{"face":{…}}`, `{"corner":{"edge":{…},"end":"start"}}`, …), as
  `SectionReference` does. `ViewState.measurements: [KeptMeasurement]` (default `[]`) and
  `DocumentModel.measurements: [KeptMeasurement]` (a separate observable property, assembled into `viewState` like
  `section`; setting it is no edit).

- [ ] **Step 1: Write the failing tests** in `MeasureViewStateTests`: `everyAnchorRoundTrips` (one measurement per case
  through `JSONEncoder`/`JSONDecoder`, equal after); `noMeasurementsWritesNoKey` (encoded `ViewState()` has no
  `"measurements"`); `anOlderFileReadsNone` (a view-state JSON without the key decodes `[]`);
  `aDamagedMeasurementIsDroppedAlone` (an array of three where the middle one is `{"anchors":[{"bogus":1}]}`, or has zero
  or three anchors, decodes to the two good ones in order); `settingMeasurementsIsNoEdit` (a `DocumentModel` given
  measurements is not dirty and `undoName` is nil); `newDocumentHasNone`.
- [ ] **Step 2: Run** `swift test --filter MeasureViewStateTests`. Expected: compile failure.
- [ ] **Step 3: Implement.** Lossy decoding: decode the array as `[FailableDecodable<KeptMeasurement>]`-style wrapper
  (a private struct whose `init(from:)` swallows the error into `nil`) and keep the non-nil ones; `KeptMeasurement`'s own
  decoder refuses anchor counts other than 1 or 2. Encode with `if !measurements.isEmpty`. Wire `DocumentModel.measurements`
  everywhere `section` is wired (the `viewState` getter and setter, opening a file); `CornerEnd` moves out of CreatorApp
  (`import CreatorGraph` where it is used).
- [ ] **Step 4: Run** `swift test --filter MeasureViewStateTests` and `swift test --filter CreatorAppTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(measure): kept measurements in the view state`.

### Task 3: Section pieces for picking

**Files:**
- Modify: `Sources/CreatorApp/Section/SectionCapModel.swift`
- Create: `Sources/CreatorApp/Measure/MeasureSectionPick.swift`
- Test: `Tests/CreatorAppTests/Measure/MeasureSectionPickTests.swift`, `Tests/CreatorAppTests/SectionCapModelOrderTests.swift` (extend)

**Interfaces:**
- Produces:

  ```swift
  struct SectionedPart: Sendable { let solid: Solid; let section: PlaneSection }
  // SectionCapModel
  private(set) var parts: [SectionedPart]      // published with `section`, cleared with it; same request, same order
  private(set) var plane: Plane?               // the plane `parts` were cut at (SectionCaps.plane(for:))
  // the pieces of a part in one fixed order: regions in order, each region's boundary in order
  extension PlaneSection { var pieces: [SectionPiece] }
  enum MeasureSectionPick {
      /// The piece within `radius` points of `point`, nearest first; `part` indexes `parts`, `piece` indexes `section.pieces`.
      static func nearest(to point: ScreenPoint, in parts: [SectionedPart], screenPoint: (Vector3) -> ScreenPoint?,
                          radius: Double = 6) -> (part: Int, piece: Int)?
  }
  ```

- [ ] **Step 1: Write the failing tests.** `aPublishedCapCarriesItsParts` (FakeKernel box, `follow`, `waitForCaps`:
  `parts.count == 1`, `parts[0].solid === solid`, `plane == SectionCaps.plane(for: clip)`); `aClearForgetsTheParts`
  (`follow(clip: nil…)` empties `parts` and `plane`); `aPointNearAnOutlinePicksIt` (two square pieces projected by an
  identity `screenPoint` taking x, y; a point 4 pt from the second piece's edge gives `(0, 1)`); `aPointFarFromEveryOutlineIsNil`
  (7 pt away); `theNearerOfTwoPiecesWins`.
- [ ] **Step 2: Run** `swift test --filter MeasureSectionPickTests` and `--filter SectionCapModelOrderTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** `start(_:)` collects `SectionedPart(solid:section:)` next to each cap (only for non-empty
  sections) and `ended` publishes them with the caps in the same `revision` bump. `nearest` measures screen distance from
  the point to each projected polyline segment (skipping segments with an end that does not project).
- [ ] **Step 4: Run** the same filters. Expected: PASS.
- [ ] **Step 5: Commit** `feat(measure): the section's pieces for picking`.

### Task 4: Anchors and their resolution

**Files:**
- Modify: `Sources/CreatorApp/Measure/MeasurePick.swift`, `MeasureReadings.swift`, `MeasureDimensions.swift`
- Create: `Sources/CreatorApp/Measure/MeasureScene.swift`, `Sources/CreatorApp/Measure/MeasureResolver.swift`
- Modify: `Sources/CreatorKernel/DisplayMeshStorage.swift`, `Sources/CreatorApp/MeshPreview/MeshSolids.swift`
- Test: `Tests/CreatorAppTests/Measure/MeasureResolverTests.swift`, `MeasureReadingsTests.swift` (extend)

**Interfaces:**
- Consumes: `MeasureAnchor` (Task 2), `SectionedPart`, `PlaneSection.pieces` (Task 3), `MeasureElement.curve/.polyline` (Task 1).
- Produces:

  ```swift
  // MeasurePick gains
  case sectionEdge(solid: Int, piece: SectionPiece, at: Vector3)   // `at`: the point on the piece nearest the click
  case meshPoint(solid: Int, at: Vector3)
  var isApproximate: Bool          // meshPoint, or a sectionEdge whose piece has no curve
  // element(in:): sectionEdge → .curve(curve) or .polyline(polyline); meshPoint → .point
  struct MeasureScene {
      var solids: [Solid]                      // by scene index, as part A's snapshot
      var pickable: [Bool]                     // opaque, not a guide (meshes included)
      var parts: [SectionedPart]
      var plane: Plane?
      var displayMesh: (Solid) -> DisplayMesh? // MainActor-bound closure from the viewport
  }
  enum MeasureResolver {
      static func anchor(for pick: MeasurePick, in scene: MeasureScene) -> MeasureAnchor?
      static func resolve(_ anchor: MeasureAnchor, in scene: MeasureScene) -> MeasurePick?
      /// The mesh resolution behind an approximate pick, if a mesh made it.
      static func meshResolution(of pick: MeasurePick, in scene: MeasureScene) -> Double?
  }
  // Kernel: Solid(displaying:resolution:) with resolution: Double? = nil; Solid.displayedMeshResolution: Double?
  ```

- [ ] **Step 1: Write the failing tests** in `MeasureResolverTests` (FakeKernel solids, scene built by hand):
  `aFacePickFollowsAnEditedBox` (anchor of the top face of a 10 mm extrusion resolves on a rebuilt 20 mm one, same node tag,
  to the face whose centroid z is 20); `anEdgeAndItsCornerFollowTheEdit` (corner `.end` resolves to the rebuilt edge's end
  point); `aCircleCentreResolves`; `anAnchorMatchingTwoEdgesDoesNotResolve` (an `EdgePick` without ordinals whose key now
  matches two edges → `nil`); `aSectionEdgeResolvesByIndexWhenTheCountHolds` and `…ByMidpointWhenTheCountChanged`;
  `aSectionEdgeWithoutASectionDoesNotResolve`; `aMeshSectionEdgeResolvesWithin1mm` and `…NotBeyond`;
  `aMeshPointAlwaysResolves`; `aGhostOrGuideIsNeverResolvedOn`. In `MeasureReadingsTests`: `aSectionArcReadsRadiusAndDiameter`,
  `aSectionLineReadsLengthAndAngle` (against a face normal), `aSectionPolylineReadsItsLengthApproximately`
  (`isApproximate` true, length the polyline's).
- [ ] **Step 2: Run** `swift test --filter MeasureResolverTests` and `--filter MeasureReadingsTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Anchors: face → `topology.facePick(for:)`; edge/corner → `topology.picks(for: [id]).first`;
  section edge of a solid → the source face's `facePick` and its index among `section.pieces` with that `sourceFace`;
  mesh section edge → the pick's `at`; mesh point →
  its position. Resolution follows Ruling 7, edges by `topology.resolution(of: key, expecting: pick.matchCount)` then
  `ordinals` as `EdgeTagMatch.choose` does (that type is in CreatorNodes and internal: repeat its four lines, with a
  comment naming it), requiring exactly one edge. Readings and dimensions: a section piece's `curve` is an edge's curve
  (`.line` → length and line feature, `.circle` → radius/diameter and circle feature); a polyline reads its length only.
  `MeshSolids` passes `TriangleMesh.resolution` to `Solid(displaying:resolution:)`.
- [ ] **Step 4: Run** the two filters and `swift test --filter CreatorAppTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(measure): anchors that follow the model`.

### Task 5: The session picks section edges and mesh points and follows edits

**Files:**
- Modify: `Sources/CreatorApp/Measure/MeasureSession.swift`, `Sources/CreatorApp/AppModel+Measure.swift`,
  `Sources/CreatorApp/AppModel+Scene.swift` (the `measure?.sceneChanged` call)
- Modify: `Sources/CreatorViewport/Model/ViewportModel+Input.swift` (public `surfacePoint`)
- Test: `Tests/CreatorAppTests/Measure/MeasureSessionTests.swift` (extend), `Tests/CreatorViewportTests/SurfacePointTests.swift`

**Interfaces:**
- Consumes: Tasks 3 and 4.
- Produces:

  ```swift
  // ViewportModel
  public func surfacePoint(at point: ScreenPoint, solidIndex: Int) -> Vector3?   // MeshRaycast on that item's display mesh
  // MeasureSession
  private(set) var anchors: [MeasureAnchor]          // the current measurement, stored form
  private(set) var isLost: Bool                      // some anchor no longer resolves
  @ObservationIgnored var keep: (@MainActor (KeptMeasurement) -> Void)?
  func sceneChanged(_ scene: MeasureScene)          // replaces sceneChanged(_ items:)
  func keepCurrent()                                 // hands the current measurement to `keep`, then clears
  // AppModel
  func measureScene() -> MeasureScene
  ```

- [ ] **Step 1: Write the failing tests.** `MeasureSessionTests`: `aClickNearASectionOutlinePicksIt` (FakeKernel box,
  section on, click 3 pt from the outline on screen: `picks` holds a `.sectionEdge`); `theSectionOutlineWinsOverTheFaceBehind`;
  `aClickOnAMeshPicksItsSurfacePoint` (a mesh item: `.meshPoint` at the ray hit); `hoverOverAMeshShowsNothing`;
  `anEditKeepsTheMeasurementAndMeasuresAgain` (two edge picks on a box, the box rebuilt 10 → 20 mm with the same tags:
  picks resolve on the new solid and the distance is measured again; replaces part A's clear-on-change test);
  `anEditThatLosesAPickMarksItLost` (`isLost`, no distance); `turningTheSectionOffLosesASectionEdgePick`;
  `aThirdClickKeepsThePairAndStartsAgain` (`keep` received two anchors, `picks.count == 1`); `keepCurrentKeepsOnePick`.
  `SurfacePointTests`: `aRayThroughAMeshHitsItsNearSide`, `aRayMissingTheItemIsNil`.
- [ ] **Step 2: Run** `swift test --filter MeasureSessionTests` and `swift test --filter SurfacePointTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** In `clickedModel` and `updateHover`, `MeasureSectionPick.nearest` runs first; on a mesh item
  (`displayedMesh != nil`) a click calls `surfacePoint` (hover does not, Ruling 4). Every pick becomes an anchor
  (`MeasureResolver.anchor`) and `picks` is always `anchors` resolved in the latest scene. `sceneChanged` and a section
  publish (observe `SectionCapModel.revision` where the app already follows it) re-resolve and, when the resolved pair
  changed, start the distance again (part A's generation guard). A pick toggles off by its anchor's equality. The app
  wires `keep` to `measureBook.add(_:)` (Task 6; until then a test-only closure).
- [ ] **Step 4: Run** the filters and `swift test --filter CreatorAppTests`. Expected: PASS (update part A tests that
  pinned clear-on-change to the new behaviour; say which in the report).
- [ ] **Step 5: Commit** `feat(measure): section edges, mesh points, and measurements that follow edits`.

### Task 6: `MeasureBook`, the kept measurements

**Files:**
- Create: `Sources/CreatorApp/Measure/MeasureBook.swift`
- Modify: `Sources/CreatorApp/AppModel.swift` (own it; replaced with the document like `section`), `AppModel+Measure.swift`,
  `AppModel+Scene.swift`, `AppModel+Dimensions.swift` (its dimensions join the measurement's)
- Test: `Tests/CreatorAppTests/Measure/MeasureBookTests.swift`

**Interfaces:**
- Consumes: `DocumentModel.measurements` (Task 2), `MeasureResolver`, `MeasureScene` (Task 4).
- Produces:

  ```swift
  @MainActor @Observable final class MeasureBook {
      struct Entry: Identifiable { let id: UUID; var picks: [MeasurePick]?   // nil: no longer found
                                   var readings: [MeasureReading]; var distance: ShapeDistance?
                                   var isApproximate: Bool; var meshResolution: Double?; var isMeasuring: Bool }
      private(set) var entries: [Entry]
      private(set) var revision: Int
      init(kernel: any Kernel, document: DocumentModel)
      func add(_ measurement: KeptMeasurement)        // appends to document.measurements
      func remove(_ id: UUID)
      func removeAll()
      func refresh(_ scene: MeasureScene)             // re-resolve every kept one; measure distances off the main actor
      func dimensions(style: DimensionStyle, units: DocumentUnits) -> [OverlayDimension]  // ids "kept/<id>/<n>"
      func waitForDistances() async
  }
  ```

- [ ] **Step 1: Write the failing tests** (`AppModel` over FakeKernel, as `AppMeasureTests` builds one):
  `keepingMakesNoUndoStepAndNoEdit` (keep a measurement: `document.measurements.count == 1`, not dirty, `undoTitle ==
  "Undo"`; undo of an earlier edit leaves the measurement); `aKeptDistanceFollowsAWallEdit` (keep a two-face distance on a
  box, change its height input, settle: the entry's distance is the new height); `aLostPickReadsNoLongerFound` (delete the
  node: `picks == nil`, no dimension drawn); `aNewerRefreshDropsAnOlderDistance` (hold the kernel with `setMeasureHook`,
  refresh twice, release: the entry has the second scene's distance); `savedMeasurementsResolveAfterOpen` (save, open the
  file in a new `AppModel`: entries exist with `picks == nil` until the first evaluation, then resolve);
  `newClearsThem`; `keptOnesDrawOutsideMeasure` (Measure off, one kept: `measureDimensions()` contains its dimension;
  in sketch mode none).
- [ ] **Step 2: Run** `swift test --filter MeasureBookTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** `refresh` resolves synchronously, then one task measures the two-pick entries in order,
  cancelling the previous task and dropping results by generation, as `MeasureSession` does. `AppModel+Scene` calls
  `measureBook.refresh(measureScene())` where it calls `measure?.sceneChanged`, and again when the section publishes.
  `measureDimensions()` returns the book's dimensions (outside sketch mode and pick sessions, Ruling 2) plus the session's.
- [ ] **Step 4: Run** `swift test --filter MeasureBookTests` and `swift test --filter CreatorAppTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(measure): kept measurements re-measure after each evaluation`.

### Task 7: The panel lists kept measurements

**Files:**
- Modify: `Sources/CreatorApp/Measure/MeasurePanel.swift`, `Sources/CreatorApp/Section/SectionPanelDock.swift` (visibility)
- Test: `Tests/CreatorAppTests/Measure/MeasurePanelTextTests.swift` (extend), the panel's render test if part A has one

**Interfaces:**
- Consumes: `MeasureBook.Entry` (Task 6), `MeasureSession.keepCurrent`, `isLost` (Task 5).
- Produces: `MeasurePanelText.keptSummary(_ entry: MeasureBook.Entry, units:) -> String` (the distance, else the first
  reading in the panel's order; "No longer found" when `picks == nil`), `MeasurePanelText.approximate(_ text: String,
  meshResolution: Double?, units:) -> String` (`"≈ " + text`, plus `" · mesh " + resolution` when known), constants
  `keep = "Keep"`, `clearAll = "Clear All"`, `lost = "No longer found"`.

- [ ] **Step 1: Write the failing tests:** `aKeptDistanceSummarisesAsItsDistance`, `aKeptRadiusSummarisesAsItsRadius`,
  `aLostOneSaysNoLongerFound`, `aMeshValueIsApproximateWithItsResolution` (`"≈ 12.3 mm · mesh 0.4 mm"` in millimetres at the
  default precision), `aPolylineValueIsApproximateWithoutResolution`, `thePanelShowsWithKeptOnesAndMeasureOff`.
- [ ] **Step 2: Run** `swift test --filter MeasurePanelTextTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Under the current measurement's rows (approximate rows through `approximate`), a **Keep**
  button (disabled with no picks or while lost); then one row per kept entry (its summary, secondary text colour when lost,
  and a small "×" `Button` calling `remove`), and **Clear All** when there are kept ones. The panel shows while
  `model.measure != nil || !model.measureBook.entries.isEmpty`, never in sketch mode; Done shows only while measuring.
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorAppTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(measure): the panel keeps measurements`.

### Task 8: Checks, docs and the whole suite

**Files:**
- Modify: `docs/verification/human-checks.md` (group ME-B), `CLAUDE.md` (status line and the Measure module note)

- [ ] **Step 1:** Add group **ME-B**: a section edge hovers and picks; a section arc reads its diameter; a section edge to a
  face reads the wall thickness, which updates when the wall's input changes; a mesh point measures with "≈ … · mesh …";
  the third click keeps; Keep keeps a hole's diameter; × and Clear All remove; kept ones survive Save and Open (after the
  first evaluation) and New clears them; deleting the measured node greys the row "No longer found"; nothing marks the
  document edited or adds an undo step; Linux and Windows the same.
- [ ] **Step 2:** CLAUDE.md: a "Measure, part B" status line after part A's (plan path, human checks ME-B pending), and the
  Measure note gains `MeasureAnchor`/`KeptMeasurement` (CreatorGraph, `ViewState.measurements`), `MeasureResolver`,
  `MeasureBook`, section-edge and mesh-point picks.
- [ ] **Step 3:** Run `swift test` (12 lines; only the known `HLSLEngineTests` failure), `swiftlint lint --strict` (0) and
  `scripts/linux-test.sh test` (exit 0, 12 lines).
- [ ] **Step 4: Commit** `docs(measure): part B checks and status`.
