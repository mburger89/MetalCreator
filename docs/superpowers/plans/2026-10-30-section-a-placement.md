# Section analysis, part A (placement) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Cut view with Section analysis's placement: a section on an origin plane or a flat face, a typed or dragged offset,
a flip, a Section panel, Section from Face, on every platform, kept in the file's view state. (The cap is part B; until then the cut
still shows the far wall darkened, as today.)

**Architecture:** The saved part (`SectionSettings`: on/off, reference, offset, flip) lives on `DocumentModel` and in `ViewState`
under an optional key, so it is saved like the camera and never edits the document. A pure `SectionGeometry` turns settings plus the
scene into a frame, a `ViewportClip` and a `ViewportHandle`. A small `@MainActor @Observable SectionModel` in the app remembers the last
plane of a face reference and what the panel shows; `AppModel+Section` makes every change. `CutViewModel` and its gate go.

**Tech Stack:** Swift 6.4 (strict concurrency), Swift Testing, MetalUI, the existing viewport clip (Metal and SDL GPU).

**Spec:** `docs/superpowers/specs/2026-10-30-section-measure-design.md` (§3.1, §3.2, §3.5, §5, §9; part B is §3.3–§3.4).

## Global Constraints

- View-only: no `GraphCommand`, no undo step, no edited dot, nothing in export or evaluation (spec §1 anti-goals, §3.5).
- Every platform: macOS, Linux, Windows. `CutViewModel.isAvailable` and every `#if canImport(Metal)` gate on the cut go (spec §3.1).
- `ViewState` keys are optional on decode, written only when set, no format bump; an unreadable `section` entry is dropped (spec §5).
- Copy, verbatim: top bar toggle "Section"; menu "Show Section" / "Hide Section", "Flip Section"; face menu "Section from Face";
  lost face "The section's face no longer exists." (spec §3.2).
- A face reference: the plane through the face with its outward normal; a positive offset goes into the material (against the outward
  normal); unflipped, the outward side is cut away. An origin plane: offset along its normal (`SliceAxis.plane.normal`), unflipped, the
  normal's side is cut away (spec §9).
- Sketch mode hides the section (no clip, no handle, no panel) and leaving it brings it back (spec §3.5).
- Project rules (CLAUDE.md): Swift Testing; `swiftlint lint --strict` zero violations; twelve "Test run with" lines, none printing
  "recorded an issue" or "failed after", on macOS and on Linux (`scripts/linux-test.sh test`).

## Review Focus

1. A typed offset that is not a length ("abc", empty, "1e999", "-0") — expect the field to revert to the current value and nothing to
   move; a length in another unit ("1 in") — expect 25.4 mm. Test in Task 3.
2. The face a section was made on vanishes after an edit, or is never found after reopening a file — expect the last plane kept (or no
   cut when there is none) and the panel note, never a crash or a cut on another face. Test in Task 4.
3. Open, New and reopen — expect a file's saved section to come back on Open, New to start with none, and an older file (no key) to
   open uncut. Test in Task 3.
4. Turning the section on with nothing in the scene, then adding a part — expect nothing to happen until there is a part (as the Cut
   view's `anEmptyDocumentStaysUncut`). Test in Task 3.
5. A drag of the handle past the part's span, and an offset typed far outside it — expect the plane to go there and the handle's range
   to stretch to include it, not clamp the typed value. Test in Task 2.

---

### Task 1: `SectionSettings` in the document's view state

**Files:**
- Create: `Sources/CreatorGraph/Section/SectionSettings.swift` (the three types and their `Codable`)
- Modify: `Sources/CreatorGraph/ViewState.swift` (key `section`), `Sources/CreatorGraph/DocumentModel.swift` (property, `viewState`
  getter/setter, load at the lines that read `file.viewState.camera`)
- Test: `Tests/CreatorGraphTests/ViewStateSectionTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum SectionOrigin: String, Codable, CaseIterable, Sendable { case xy, yz, xz }
  public enum SectionReference: Equatable, Sendable, Codable { case origin(SectionOrigin), face(FacePick) }
  // JSON: {"origin":"xy"} or {"face":{…FacePick's own encoding…}}
  public struct SectionSettings: Equatable, Sendable, Codable {
      public var isOn: Bool; public var reference: SectionReference
      public var offset: Double      // millimetres
      public var isFlipped: Bool
      public init(isOn: Bool, reference: SectionReference, offset: Double, isFlipped: Bool)
  }
  ViewState.section: SectionSettings?          // init parameter `section: SectionSettings? = nil`, last
  DocumentModel.section: SectionSettings?      // observable stored property like `camera`; a non-finite offset is refused (keeps old value)
  ```

- [ ] **Step 1: Write the failing tests** in `ViewStateSectionTests` (Swift Testing, `struct ViewStateSectionTests`):
  - `aSectionRoundTrips`: encode a `ViewState` with `SectionSettings(isOn: true, reference: .face(FacePick(tags: [some tag], normal: .unitZ, centroid: Vector3(1,2,3))), offset: 2.5, isFlipped: true)` and decode it; `#expect(decoded == original)`. Same for `.origin(.yz)`.
  - `noSectionWritesNoKey`: encode `ViewState()`; the JSON has no `"section"` key.
  - `anOlderFileHasNoSection`: decode the JSON of a `ViewState` without the key; `section == nil`.
  - `aDamagedSectionIsDropped`: decode `{"section":{"isOn":true,"reference":{"plane":"xy"},"offset":1,"isFlipped":false}}` and one with `"offset":"x"`; both decode with `section == nil` and do not throw.
  - `theDocumentKeepsItsSectionAndItIsNoEdit`: a `DocumentModel` (as `ViewStateLibraryTests` makes one), set `section`; `viewState.section` matches; the document is not edited (the same dirty check `ViewStateCameraTests` uses for the camera) and `canUndo` is false; setting an offset of `.nan` keeps the old settings; a `GraphFile` saved and loaded brings it back.
- [ ] **Step 2: Run** `swift test --filter CreatorGraphTests.ViewStateSectionTests` — expect compile failure (types missing).
- [ ] **Step 3: Implement** the types and keys. `ViewState.init(from:)` reads the key with `(try? container.decodeIfPresent(SectionSettings.self, forKey: .section)) ?? nil`; `encode` writes it only when non-nil (follow how the struct encodes today; if it relies on synthesized `encode`, add an explicit one that keeps every existing key's behaviour — `ViewStateEncodingTests` must stay green).
- [ ] **Step 4: Run** `swift test --filter CreatorGraphTests` — all pass, including `ViewStateEncodingTests`.
- [ ] **Step 5: Commit** `feat(section): SectionSettings in the view state`.

### Task 2: `SectionGeometry`: settings and scene to a plane, clip and handle

**Files:**
- Create: `Sources/CreatorApp/Section/SectionGeometry.swift`
- Test: `Tests/CreatorAppTests/SectionGeometryTests.swift`

**Interfaces:**
- Consumes: Task 1's types; `SliceAxis` (`Sources/CreatorApp/FieldPreview/SliceAxis.swift`), `SlicePose.startingAxis(toEye:)`,
  `Topology.resolution(of: FacePick)`, `PlaneFromFaceNode.plane(of:)`'s rule for a usable face (`kind == .plane`, normalizable normal).
- Produces:
  ```swift
  struct SectionFrame: Equatable, Sendable {
      var origin: Vector3          // a point of the reference plane
      var normal: Vector3          // unit; the side cut away when unflipped
      var offsetDirection: Vector3 // unit; +normal for an origin plane, −normal (into the material) for a face
  }
  extension SliceAxis { init(_ origin: SectionOrigin); var origin: SectionOrigin }
  enum SectionGeometry {
      static func frame(of origin: SectionOrigin) -> SectionFrame               // origin .zero, normal SliceAxis(origin).plane.normal
      static func frame(ofFace face: FaceInfo) -> SectionFrame?                 // nil unless a flat face with a normal; origin = centroid
      static func resolveFace(_ pick: FacePick, in items: [ViewportItem]) -> (face: FaceInfo, isGuess: Bool)?
      static func clip(_ frame: SectionFrame, offset: Double, isFlipped: Bool) -> ViewportClip
      static func handle(_ frame: SectionFrame, offset: Double, bounds: BoundingBox) -> ViewportHandle
      static func starting(origin: SectionOrigin?, bounds: BoundingBox, toEye: Vector3) -> SectionSettings
  }
  ```
  - `resolveFace`: the first item (scene order) that is not `isGuide` and not ghosted whose `solid.topology.resolution(of:)` has a
    first face with a frame; `isGuess` is that resolution's `isAmbiguous`.
  - `clip`: origin `frame.origin + frame.offsetDirection * offset`, normal `isFlipped ? -frame.normal : frame.normal`.
  - `handle`: id `SectionModel.handleID` (Task 3; until then a `static let handleID = "section-plane"` here is fine, moved in Task 3),
    anchor = the bounds' centre projected into the reference plane, direction `offsetDirection`, value `offset`, style `.linear`,
    tint `.solid`, range = the bounds corners' span along `offsetDirection` measured from `frame.origin`, widened to include `offset`.
  - `starting`: reference `.origin(origin ?? SliceAxis.startingAxis-from-toEye)`, offset = `bounds.center · normal` (the plane through
    the centre), `isFlipped = toEye · normal < 0` (the side facing the viewer is cut), `isOn = true`.

- [ ] **Step 1: Write the failing tests** (`struct SectionGeometryTests`, bounds `(-5,-10,0)…(5,10,30)` as `CutViewModelTests`):
  - `anOriginPlaneStartsThroughTheCentreCuttingTheViewersSide`: `starting(origin: nil, bounds:, toEye: (0.3,0.2,1))` → `.origin(.xy)`, offset 15, not flipped; its clip has origin `(0,0,15)`, normal `.unitZ`, `removes((0,0,25))`, not `(0,0,5)`. From `toEye (0,0.1,-1)` → flipped, clip normal `-unitZ`.
  - `aFaceSectionGoesIntoTheMaterial`: a planar `FaceInfo` with normal `+Z`, centroid `(0,0,30)` (the box's top): frame offsetDirection `-Z`; `clip(frame, offset: 4, isFlipped: false)` has origin `(0,0,26)`, normal `+Z` (the outward side cut). Flipped: normal `-Z`.
  - `aCurvedFaceHasNoFrame`: a `.cylinder` face → `frame(ofFace:) == nil`.
  - `theHandleSpansThePartAndStretchesToATypedOffset`: origin `.xy`, offset 15 → range `0...30`, anchor `(0,0,0)`, direction `.unitZ`; offset 50 → range `0...50`; offset -7 → `-7...30`.
  - `aFaceIsFoundInTheSceneByItsTags`: two `ViewportItem`s over `FakeKernel` boxes (as other `CreatorAppTests` build them), a pick from item 2's `topology.facePick(for:)` → resolves to item 2's face; a pick of tags no item has → `nil`; a ghosted or guide item holding the face is skipped.
- [ ] **Step 2: Run** `swift test --filter CreatorAppTests.SectionGeometryTests` — fails to compile.
- [ ] **Step 3: Implement** `SectionGeometry.swift`.
- [ ] **Step 4: Run** the same filter — pass.
- [ ] **Step 5: Commit** `feat(section): section frames, clip and handle`.

### Task 3: `SectionModel` replaces the Cut view in the app

**Files:**
- Create: `Sources/CreatorApp/Section/SectionModel.swift`, `Sources/CreatorApp/AppModel+Section.swift`
- Delete: `Sources/CreatorApp/CutView/CutViewModel.swift`, `Sources/CreatorApp/AppModel+CutView.swift`,
  `Tests/CreatorAppTests/CutViewModelTests.swift`
- Modify: `Sources/CreatorApp/AppModel.swift` (`let cutView` → `let section = SectionModel()`; `load` calls `section.reset()` instead of
  `cutView.turnOff()`), `AppModel+Scene.swift` (lines 81–82, 87, 147), `AppModel+Viewport.swift` (lines 47–48),
  `TopBar.swift` (39–40), `AppCommands.swift` (41–44)
- Test: `Tests/CreatorAppTests/SectionModelTests.swift`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces:
  ```swift
  @MainActor @Observable final class SectionModel {
      static let handleID = "section-plane"
      private(set) var shown: SectionShown?     // nil when off, hidden (sketch mode) or nothing to cut
      private(set) var note: String?            // the panel's line about the face; nil when fine
      func update(_ settings: SectionSettings?, items: [ViewportItem], bounds: BoundingBox?, hidden: Bool)
      func reset()                              // forgets the remembered face plane (New/Open)
  }
  struct SectionShown: Equatable { var frame: SectionFrame; var clip: ViewportClip; var handle: ViewportHandle?; var faceTitle: String? }
  extension AppModel {
      func setSection(_ on: Bool)               // top bar toggle and View ▸ Show/Hide Section
      func flipSection()
      func setSectionOffset(_ millimetres: Double)
      func setSectionOrigin(_ origin: SectionOrigin)   // switches a face section (or another plane) to an origin plane, through the centre
      @discardableResult func commitSectionOffset(text: String) -> Bool   // parses with `units.parse(_:quantity: .length)`; false leaves it
  }
  ```
  - `update`: off / `hidden` / no bounds → `shown = nil`. Origin reference → its frame. Face reference → `resolveFace`; found: frame,
    remember `(pick, frame)`, `note` = `"The section's face changed; this is the nearest match."` when `isGuess`, else nil; not found:
    the remembered frame for that pick if any, else no `shown`, and `note = "The section's face no longer exists."`. `handle` is nil
    without bounds. `faceTitle` = `"Face of <producing node's name>"` from `MeshQueries.producingNodes(of:)` and the graph's node name
    when there is exactly one, else `"Face"` (pass a name lookup in, or compute it in `AppModel+Section`; builder's call).
  - `AppModel.setSection(true)`: with `document.section == nil` and scene bounds, writes `SectionGeometry.starting(origin: nil, …)`;
    with settings present, sets `isOn = true`; with no bounds and no settings, does nothing. `false` sets `isOn = false` and keeps the rest.
  - `refreshScene` calls `section.update(document.section, items: viewport.items, bounds: viewport.sceneBounds, hidden: sketch != nil)`,
    `viewport.showClip(section.shown?.clip)`, appends `section.shown?.handle`; the observation block reads `document.section`
    instead of `cutView.revision`.
  - `handleChanged`: `id == SectionModel.handleID` → `setSectionOffset(value)`; never reaches the graph path.
  - TopBar: `Toggle("Section", …)` bound to `document.section?.isOn == true` / `setSection`, unconditionally (no `isAvailable`).
    AppCommands: `"Show Section"` / `"Hide Section"`, `"Flip Section"` disabled while off.

- [ ] **Step 1: Write the failing tests** (`@MainActor struct SectionModelTests`, `makeApp` and `GraphBuilder` as the deleted
  `CutViewModelTests` used them):
  - `theAppSectionsTheViewportAndShowsTheHandle`: box graph; `setSection(true)` → `viewport.clip != nil`, a handle with id
    `SectionModel.handleID`; `handleChanged(handleID, 2, .ended)` moves `document.section?.offset` to 2 with `!document.canUndo` and the
    document not edited.
  - `offIsRememberedAndComesBack`: on, offset 3, flip; off → no clip, no handle, settings kept with `isOn == false`; on → offset 3, flipped.
  - `typedOffsets`: `commitSectionOffset(text: "12.5")` → 12.5 and true; `"1 in"` → 25.4; `"abc"`, `""`, `"1e999"` → false and offset unchanged.
  - `aSavedSectionComesBackAndNewStartsWithout`: on, offset 4; `fileData` (or the save path `AppFilesTests` uses) → `load` of that file
    → `document.section?.offset == 4`, clip shown after the scene refreshes; `load(GraphFile(graph:))` (no view state) → no clip.
  - `anEmptyDocumentStaysUncut`: `setSection(true)` on an empty app → `document.section == nil`, no clip.
  - `sketchModeHidesTheSection`: on, then begin a sketch (as `NewSketchOnFaceTests` does) → no clip, no section handle; stop → back.
  - `switchingToAnOriginPlane`: a face section (`document.section` set by hand to `.face(pick)` of the box's top), `setSectionOrigin(.yz)` → `.origin(.yz)`, offset through the centre.
- [ ] **Step 2: Run** `swift test --filter CreatorAppTests.SectionModelTests` — fails.
- [ ] **Step 3: Implement** and remove the Cut view (every `cutView`/`CutViewModel` reference; `grep -rn "cutView\|CutViewModel\|setCutView" Sources Tests` is empty after).
- [ ] **Step 4: Run** `swift test --filter CreatorAppTests` — pass (the window tests that named the Cut view are Task 5's; if they no longer compile, rename their references now and fix their assertions in Task 5).
- [ ] **Step 5: Commit** `feat(section): the section replaces the cut view`.

### Task 4: Section from Face

**Files:**
- Modify: `Sources/CreatorViewport/Model/ViewportMenuItem.swift` (case `sectionFromFace(ViewportFaceRef)`, title "Section from Face"),
  `Sources/CreatorViewport/Model/ViewportModel+ContextMenu.swift` (offered with New Sketch on flat faces with a normal, outside a tool;
  dispatched through `chooseOnFace`), `Sources/CreatorViewport/Model/ViewportEvents.swift`
  (`public var sectionFromFace: @MainActor (ViewportFaceRef, FacePick) -> Void = { _, _ in }`),
  `Sources/CreatorApp/AppModel+Viewport.swift` (wire the event), `Sources/CreatorApp/AppModel+Section.swift`
- Test: `Tests/CreatorViewportTests/ContextMenuTests.swift` (add), `Tests/CreatorAppTests/SectionFromFaceTests.swift`

**Interfaces:**
- Produces: `AppModel.sectionFromFace(_ ref: ViewportFaceRef, _ pick: FacePick)`: writes
  `SectionSettings(isOn: true, reference: .face(pick), offset: 0, isFlipped: false)`; nothing while a sketch is open.

- [ ] **Step 1: Write the failing tests:**
  - `ContextMenuTests.aFlatFaceOffersSectionFromFace`: the menu on a planar face contains `.sectionFromFace(ref)` (after
    `.scatterOnFace`); on a cylindrical face it does not; with a tool set it does not; choosing it calls `events.sectionFromFace` with
    `topology.facePick(for: ref.face)`.
  - `SectionFromFaceTests.itCutsAtTheFaceAndGoesIn`: box graph, `sectionFromFace` on the top face → clip origin on the top face's plane,
    normal outward; `setSectionOffset(4)` → clip origin 4 mm below the top.
  - `itFollowsTheFaceThroughAnEdit`: change the box's height through a graph command; after the scene refreshes the clip is on the new top.
  - `aVanishedFaceKeepsTheLastPlaneAndSaysSo`: section on a face of a node, then delete that node's output from the scene (disconnect
    or delete the node) → clip unchanged and `section.note == "The section's face no longer exists."`; the same settings loaded into a
    fresh app (no remembered plane) → no clip and the same note.
- [ ] **Step 2: Run** `swift test --filter 'ContextMenuTests|SectionFromFaceTests'` — fail.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test --filter CreatorViewportTests` and `--filter CreatorAppTests` — pass.
- [ ] **Step 5: Commit** `feat(section): Section from Face`.

### Task 5: The Section panel, the top bar and the window tests

**Files:**
- Create: `Sources/CreatorApp/Section/SectionPanel.swift` (`SectionPanel`, a `Component` in `GlassPanel(.sectionPanel)`),
  `Sources/CreatorApp/Section/SectionPanelDock.swift` (placed by a new `AppLayout.sectionPanelInsets(dock:panelWidth:panelHeight:)`,
  added to `AppRoot` beside `FieldLegendDock`)
- Modify: `Sources/CreatorStyle/GlassSurface.swift` (case `sectionPanel`, `.ultraThin`), `Sources/CreatorApp/AppLayout.swift`
- Rename/rewrite: `Tests/CreatorAppTests/CutViewWindowTests.swift` → `SectionWindowTests.swift`
- Test: `SectionWindowTests`, plus whatever `GlassSurface.allCases` tests need a row

**Interfaces:**
- Consumes: Task 3's `AppModel` calls and `SectionModel.shown`/`note`.
- Panel content, top to bottom: the title "Section"; a segmented `Picker` "XY / YZ / XZ" (selection the origin plane, none for a face
  reference; choosing calls `setSectionOrigin`); for a face reference the `faceTitle` line; the `note` in the theme's warning colour
  when set; an "Offset" `TextField` showing `units.editText(offset, quantity: .length)` plus the unit suffix, committing on submit and on
  focus loss through `commitSectionOffset(text:)` and reverting its text when that returns false; "Flip" and "Close" buttons
  (`flipSection()`, `setSection(false)`). Shown only while `document.section?.isOn == true` and not in sketch mode. Placement: the
  model area's upper right, 16 points in, under the top bar, left of the theme editor when that is open (builder may pick another
  free corner; it must not cover the view cube, the legend or the mesh badge).

- [ ] **Step 1: Write the failing window tests** (in the style of the old `CutViewWindowTests`, real `AppWindow`):
  - `theTopBarToggleSectionsTheViewportOnEveryPlatform`: the "Section" toggle exists (no platform gate) and switching it shows the clip
    and the panel; switching it off hides both.
  - `thePanelTypesAnOffsetAndFlips`: type "7" in Offset and submit → offset 7; type "x" → the field shows 7 again; Flip flips; Close turns it off.
  - `thePanelPicksAnOriginPlane`: choose "YZ" → `.origin(.yz)`.
  - Delete `withoutAMetalViewportThereIsNoToggle`.
- [ ] **Step 2: Run** `swift test --filter CreatorAppTests.SectionWindowTests` — fail.
- [ ] **Step 3: Implement** the panel, dock, glass surface and layout.
- [ ] **Step 4: Run** `swift test --filter CreatorAppTests` and `swift test --filter CreatorStyleTests` — pass.
- [ ] **Step 5: Commit** `feat(section): the Section panel`.

### Task 6: Linux, docs and the full suite

**Files:**
- Modify: `docs/verification/human-checks.md` (new group **SA-A**: toggle on each platform, drag, typed offset in mm and in, flip,
  Section from Face then edit the part, a deleted face's note, save/reopen, sketch mode hides it; rewrite MT-4 and XP-24's cut sentence
  to point at SA-A), `CLAUDE.md` (status line for section part A after the 7c-3 lines; replace the `CutViewModel` sentence in the
  `CreatorApp` paragraph with `SectionModel`/`SectionGeometry`/`SectionSettings`, and drop "the Cut view are macOS-only" from 7c-3's
  line, leaving Mesh to Solid)
- [ ] **Step 1: Run** `swift test` on the Mac — exit 0, twelve "Test run with" lines, no "recorded an issue" / "failed after".
- [ ] **Step 2: Run** `scripts/linux-test.sh test` — the same on Linux (the section toggle and window tests now run there).
- [ ] **Step 3: Run** `swiftlint lint --strict` — zero violations.
- [ ] **Step 4: Write** the docs above.
- [ ] **Step 5: Commit** `docs(section): part A human checks and status`.
