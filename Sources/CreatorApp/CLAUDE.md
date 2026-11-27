# CreatorApp and MetalCreatorApp

Notes for this module, moved from the root `CLAUDE.md` (which Claude Code loads in every session) so they load only when work touches this folder. The project-wide rules, commands and toolchain notes stay in the root file.

M6 (app shell) code is done; its human checks (group M6) are pending.
MetalUI C8 (the app shell: close and quit veto, window title and edited dot, open-document events) is
adopted, with the hidden title bar (gap M6-c) and MetalUI C22's window drag (gap C8-a; plan `docs/superpowers/plans/2026-10-12-adopt-c22.md`); its human checks (group AS; the drag is AS-5) are pending.

Toolbar icons (`toolbar-icons`, MetalUI #277's bundled symbols, CI pin `e051f257`: the top bar's Undo, Redo and Export, the graph header's Add, Library, zoom, dock switch (a segmented `Picker` of two `Image`s) and Hide, and the view cube's Home and View menu are borderless icon buttons; each passes its own short `.accessibilityLabel` ("Add node", "Zoom out") and a `.help` with the full words and shortcut, since the glyphs carry none, and the header's words are `HeaderText`; every icon is a `ToolbarIcon` (`CreatorStyle`), a fixed 24 x 24 hit box so a near miss never reaches the viewport or SDL's window drag; Add is a `plus`, bundled by MetalUI #290) code is done; its human checks (group TI) are pending.
Packaging (`scripts/package-app.sh`, `docs/packaging.md`) is done; its human checks (group P) are pending.

M7 (measure and record) code is done: spec §7.3's numbers are in `docs/verification/performance.md`, taken by the
release benchmarks in `Tests/CreatorAppTests/Bench` (`scripts/bench.sh`); `docs/metalui-gaps.md` opens with a summary
table of every gap, its MetalUI item and its status; its human checks (group M7) are pending.

Section analysis, part A (placement; spec `docs/superpowers/specs/2026-10-30-section-measure-design.md`, plan `docs/superpowers/plans/2026-10-30-section-a-placement.md`) code is done; its human checks (group SA-A) are pending. `SectionSettings`, `SectionReference` and `SectionOrigin` (`CreatorGraph/Section`) are saved as `ViewState.section` (an optional key, no format bump); `SectionGeometry`, `SectionModel`, `SectionPanel` / `SectionPanelDock` (left of the open theme editor) and `AppModel+Section` are in `CreatorApp/Section`. The Section replaces the Cut view on every platform (top bar toggle, View menu, Section from Face in the face menu) and is hidden in sketch mode.
Section analysis, part B (the cap; plan `docs/superpowers/plans/2026-10-30-section-b-cap.md`) code is done; its human checks (group SA-B) are pending and its benchmark rows `sa-1` to `sa-3` are recorded in `docs/verification/performance.md` (a lattice's slice, `sa-2`, takes about 2 ms and `sa-2b` 5 ms on a prepared mesh; the numbers are from a loaded Mac). `Kernel.section(_:by:tolerance:)` gives a `PlaneSection` (OCCT: `cocct_section.cpp`; `FakeKernel`: boxes), `MeshSlicer.slice` the same for a mesh (`MeshSlicer.prepare` welds a mesh by exact position once into a `Prepared`, which the section cap keeps per mesh and reslices at every plane; a cancelled weld sets `wasCancelled` and is never kept), `PolygonTriangulator` (`CreatorGeometry`) fills it, `SectionCapModel` / `SectionCaps` (`CreatorApp/Section`) compute it off the main actor at the clip plane moved inward by `max(1e-4, 1e-6 × the largest absolute coordinate of the capped solids' bounds)` mm (`SectionCaps.inset(for:)`) and the viewport draws it (`ViewportSection`, `showSection`; theme roles `sectionFill`, `sectionHatch`, `sectionEdge`). A failed section says "The cut face couldn't be filled for every part." in the Section panel (a face the triangulator cannot fill keeps its boundary pieces and a region with no triangles). A pick session leaves the section and its caps as they were (`refreshScene` skips `section.update` and `sectionCaps.follow`), though edits to the section during it still apply; outside Final preview a Section from Face whose face is not in the preview keeps the remembered frame and says "The face isn't part of this preview."
Measure, part A (the tool; plan `docs/superpowers/plans/2026-10-30-measure-a-tool.md`) code is done; its human checks (group ME-A) are pending. M, the top bar's Measure toggle or View ▸ Measure start it; picks of edges, faces and corners give radius, diameter, length, area, distances, centre distances and angles, drawn as reference-coloured dimensions; a full circle's centre is its own hover and pick target within min(10, 0.5 × the circle's on-screen radius) points, tested before the edge and face fallbacks, among the hovered solid's circles only, the one nearest the camera on a tie and never one on the cut-away side, so a small circle still picks as its edge. A measurement is view state: no command, no undo step, cleared by a change to a picked part (a replaced solid at a picked index; other items changing keep it); M toggles it.
Measure, part B (keeping; plan `docs/superpowers/plans/2026-10-31-measure-b-keep.md`) code is done; its human checks (group ME-B) are pending. Section-edge and mesh-point picks join the tool; the third click keeps the pair, or the panel's Keep (disabled with no picks or while a pick is lost); a measurement with any approximate pick marks every value "≈ … · mesh …". A distance that can't be made reads "Couldn't measure" and is not retried until a pick or the solid under it changes; points, corners, mesh points and a mesh's section outlines are measured in Swift (`PolylineDistance`, no OpenCascade); hover tests a section piece only when the pointer is within its projected bounds; an arc whose start isn't on its radius is refused. Kept measurements are saved as the optional `ViewState.measurements` (no format bump), re-measure after each evaluation, are drawn and listed with Measure off (never in sketch mode or a pick session), and make no undo step and no edit.

Zebra stripes (a reflection check for surface continuity: spec `docs/superpowers/specs/2026-11-01-zebra-design.md`, plan `docs/superpowers/plans/2026-11-01-zebra.md`) code is done; its human checks (group ZE) are pending and its benchmark row `zebra-1` is in `docs/verification/performance.md`. `ZebraSettings`, `ZebraFrame` and `ZebraDirection` (`CreatorGraph/Zebra`) are saved as `ViewState.zebra` (an optional key, no format bump); `ViewportZebra` (`ViewportModel.showZebra`), `ZebraBand` (the stripe function's CPU twin) and `ZebraUniforms` are in `CreatorViewport`; the top bar's Zebra toggle, View ▸ Show/Hide Zebra Stripes, Z and `ZebraPanel` (in the section dock below Measure; Lock captures the pose's right, up and toEye) are the app's. Zebra beats the field tint, ghosts are never striped, and sketch mode hides it. A mesh item is striped like any opaque solid (the renderer binds the zebra pipeline per non-ghost item; `MeshDisplayCreaseRenderTests` draws one). `TriangleMesh.creaseAngle` (30 on an Import Mesh node's mesh; `nil` elsewhere) makes `displayMesh` split a vertex at each edge that turns more than the angle (`TriangleMesh.creasedDisplay`, linear in the triangles; triangle order and count unchanged, display vertices may outnumber the mesh's, so per-vertex data is keyed on the display mesh, never on mesh vertex indices), so a CAD part's stripes show flat faces.

Cross-platform, sub-project xp-1 (Linux and Windows on MetalUI's SDL backend: everything but the 3D view and OpenCascade; plan
`docs/superpowers/plans/2026-10-13-xp-1.md`, spec `docs/superpowers/specs/2026-10-13-cross-platform-design.md` §2) code is done and
the suite is green on Linux in CI (GitHub Actions, `.github/workflows/xp.yml`, x86_64 and aarch64; `scripts/linux-test.sh` runs the
same in Docker); its human checks (group XP) are pending. Window chrome on SDL (MetalUI S1, gap XP-G3, branch `xp-adopt-s1`, CI pin `ceca59f6`): the window is borderless and MetalUI draws minimise, zoom and close (`drawsWindowControls` stays at its default), `TopBar` pads by `titleBarInsets.left` (`AppLayout.topBarClearance`, macOS's traffic lights) and `.right` (`topBarTrailingClearance`, SDL's 138-point cluster), the bar stays at the margin inside the 32-point band as on macOS, and the drawn Close reaches `AppModel.closeRequested()` through `installCloseHandling`; `SDLChromeWindowTests` pins both shapes (MetalUI's `Options.sdlChrome`); the drag regions are published with the real viewport behind the bar (gap XP-G11 fixed by MetalUI S1b, PR #87, branch `xp-adopt-s1b`, CI pin `a4ebe288`: a hitbox carves a handle only if it ranks above it, and a window-wide backdrop does not carve the band; divergence 425 amended, a viewport press inside the 32-point band drags the window, which nothing relies on), human checks XP-11..XP-14. The Windows job (CI run 38546048595) is green once: it builds, the suite passes (10 "Test run with" lines), and `--self-test` and
`--smoke-test 20` pass. Two failures that had been Windows-only were MetalCreator's own: the slice's starting axis chose YZ over XY on a
last-bit tie of the default camera's view direction (`SlicePose.startingChoice` now treats near-equal alignments as a tie), and the window
root, taller than the window with Windows' text metrics, was centred upward by the window's wrapper, so the top bar and the drag strip
sat 3 points high (`AppWindowRoot` now pins the root to the window's top left). The Windows job stays `continue-on-error`, with a
`::warning::` step and a summary line when its suite is red. On the way: `ImageResolver.read` has a Windows branch, the named-pipe and
device tests and `PackagingScriptTests` are not run on Windows, and the test executables reserve a 16 MB stack (`-Xlinker /STACK:16777216`;
a layout tree overflowed Windows' 1 MB default thread stack).

- `CreatorApp` + `MetalCreatorApp`: the app shell, the only target joining Graph, Nodes, Viewport and the editors.
  The model dimension tool (spec `2026-10-27-driving-dimensions-design.md` §3.5): `ModelDimensionSession` (`AppModel.modelDimension`) takes two picks, the
  trace rule (`ModelDimensionTrace`) finds the sketch entity each face or edge came from through the Sketch node's `sketchTrace`, and picks from different
  features show the chip; the dimension is added at its measured value as one "Add Dimension" step (a reference when it would over-define), then its
  box opens through `pendingValueBox`. D is in the viewport key context (the sketch's own D wins in sketch mode; a focused text field types it) and the
  face menu's Dimension starts the tool.
  Sketch mode is `AppModel.sketch` (`SketchSession`: the editor as the viewport's tool, its overlay followed), entered
  by the Sketch node's "Edit sketch" (`InspectorAction.editSketch`); the scene is ghosted and handle-free meanwhile,
  the top bar holds `SketchToolbar` and the inspector `SketchInspector`, each in `SketchChrome` (glass over an opaque
  backdrop, so a click on the chrome never reaches the editor beneath). `SketchStore` turns a commit into one batch:
  the `sketch` setting, a cleared constant under each exposed dimension's name (the value lives in the sketch alone),
  and a renamed exposed dimension's wire moved (dropped when it stops being exposed). A Project commit also stores each pick
  under `NodeSetting.projection(reference)` and wires the solid's producer into `references` (one wire: `resolveProjection`
  refuses another part, or one made from the sketch); a removed projection clears its pick. The face menu's New Sketch on
  Face (`newSketchOnFace`) inserts Plane from Face and a wired Sketch as one batch and opens the sketch on
  `PlaneFromFaceNode.plane(of:)`.
  `@MainActor @Observable AppModel` owns the open document's parts (document, editor, graph input, viewport; replaced
  together on New and Open), turns results into `ViewportItem`s (`SceneBuilder`; in Final preview a selected rule's edges on a solid no shown
  part holds come as guide items, Errata (Viewport: a rule's edges over the Final part)) and `HandleSpec`s into
  `ViewportHandle`s (`HandleBuilder`), turns viewport events into graph commands (picking writes Edges by Tag rules),
  and opens, saves and exports (`ExportKind`: STEP and STL of solids are the kernel's; any mesh, and every 3MF, is streamed by
  `StreamedExport`: the graph is evaluated with `MeshQuality.streamedExport`, each Output node is one 3MF object (one per mesh when it holds several), each `MeshStream` is
  meshed window by window into the file, and the export sheet's Cancel removes the half-written file). The section is `SectionModel` (`AppModel.section`, `handleID "section-plane"`; `SectionGeometry` makes the clip, the frame and the handle from `SectionSettings`, saved in `ViewState.section`; the top bar's "Section" toggle, View ▸ Show Section and Flip Section, the face menu's Section from Face, `SectionPanel`; hidden in sketch mode, on every platform): 7b's `SlicePose` and handle, view state. A selected layout node is evaluated even before anything is wired to it and shows its
  placements
  as an overlay of axis triads (`LayoutPreview`, `OverlayTint.axisX/Y/Z`; Face Pattern also dashes the area it fills),
  which never
  picks, frames or opens a menu; the face menu's Pattern on Face (`AppModel.patternOnFace`) inserts a Face Pattern
  holding the
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
  Selected
  node previews the level's selected node, handles and picking work there, and a pick is written through
  `GraphContent.relativeToLevel` (Done and a viewport click drop a pick whose level is no longer the one shown); Final
  preview and export stay on the top level. Sketch mode is top-level only
  ("Edit sketch" and New Sketch on Face inside a group say so). The open sketch follows a wired plane: when it moves the
  camera looks at it again (`viewport.lookAt`), and when its node fails or its wire goes the sketch stays on the last plane
  and says so once (`SketchSession.hasPlane`; a plane that is only evaluating again is waited for). `AppInput` installs the window's input once and forwards to the current document.
  The window shell is MetalUI C8's, wired in `MetalCreatorApp`: `Window.onCloseRequest` is `AppModel.closeRequested()`
  (`CloseDecision`; `.later` with unsaved changes, the Save / Don't Save / Cancel alert, `answerSaveChanges(_:)` replying
  through `replyToCloseRequest`; ⌘Q asks the same handler because the app sets no `onTerminateRequest`),
  `WindowChromeSync` keeps `Window.title`, `isDocumentEdited` and `representedURL` on the document
  (`AppModel.windowChrome`), the window opens with the hidden title bar (`AppLayout.windowStyle`, gap M6-c; check AS-5): `TopBar` pads
  by `AppLayout.topBarClearance` and `topBarTrailingClearance` of the window's `titleBarInsets` (left: AppKit's traffic lights; right: MetalUI's drawn buttons on SDL; zero in full screen), and the window is dragged by `WindowDragHandle`
  (CreatorStyle; MetalUI C22's `WindowDragGesture`, gap C8-a): the strip `AppLayout.windowDragStripHeight` along the top, and the top
  bar's empty space (its label and the gap beside the controls; the sketch toolbar's too), never behind a control (a disabled one would
  pass the press to a handle behind it), and
  `App.onOpenURL` is `AppModel.openRequested(_:)` (the path argument goes through `App.open(_:)`; a file that arrives while
  any alert is up is ignored).
  `MetalCreatorApp` is the executable (`OCCTKernel`). It makes the app's `ThemeStore` (`AppThemes.store()`: user
  defaults, `~/Library/Application Support/MetalCreator/Themes`) and its `ThemeEditorModel`, and opens the window on
  `AppWindowRoot`: `AppRoot` with the theme editor (`ThemeEditorDock`, a floating glass panel at the top right) over
  it, the store in the environment and `.theme(current.controlTheme)` for MetalUI's controls. View ▸ Theme is
  `ThemeMenu` (every theme, then Edit Themes…). `LaunchCommand` parses its command line: a file to open, or the
  headless `--help`, `--version`, `--self-test` (`SelfTest`: OCCT, STEP/STL export, MetalUI's shaders) and `--info-plist`.
  `AppBundleInfo` is the version's one source; the packaged `Info.plist` is generated from it, never edited.

  Measure (`CreatorApp/Measure`; `AppModel+Measure`): `MeasureSession` is a `ViewportTool` (hover draws the edge, a corner within 10 pt snaps), with
  `MeasureReadings` (the numbers), `MeasureSnap`, `MeasureDimensions` (the drawn dimensions) and `MeasurePanel` under the Section panel. It is exclusive with
  sketching, D and pick sessions (refused while one runs, ended by one starting), and ends on New and Open.
  Keeping (part B): `MeasureAnchor` (a part, face or edge pick, a `SectionEdgeAnchor` or a mesh point) and `KeptMeasurement` (`CreatorGraph/Measure`, with `CornerEnd`) are saved in `ViewState.measurements`; `MeasureResolver` finds each anchor in the current results (a lost one greys the row "No longer found"), `MeasureScene` holds what is drawn, `MeasureBook` the kept list, re-measured after each evaluation, and `MeasureSectionPick` picks the cap's outline from `SectionCapModel.parts`/`plane`. `Kernel` measures `MeasureElement.curve` and `.polyline`; `ViewportModel.surfacePoint(at:solidIndex:)` and `Solid(displaying:resolution:)` serve mesh points.
  Continuity (`MeasureSession+Kernel`): one picked edge adds a Continuity row to the panel, "G2", "G1 · curvature jump N %" or "G0 · 90°" (the document's angle display), from `Kernel.continuity`; an `.unsupported` answer shows no row, any other failure "Couldn't measure"; a kept one-edge measurement asks again after each evaluation and its summary appends " · <continuity>".

  Slow evaluations (`CreatorApp/SlowEvaluation`, human checks group SE pending): `SlowEvaluationChipView` is a `GlassPanel(.chip)` with MetalUI's spinner and "Building Fillet…" ("Building Fillet and 2 more…" for several), in `SlowEvaluationDock` one row above the mesh badge (`AppLayout.slowEvaluationInsets`). `SlowEvaluationModel` (`AppModel.slowEvaluation`) holds the behaviour: it shows 0.5 s after a run starts, keeps that wait through a replacing evaluation (`isEvaluating` stays true, so no flicker) and hides the moment none is running (finished, failed or cancelled); the wait is the injectable `wait`, tests never sleep. A run is `DocumentModel.isEvaluating` (true through a replacing evaluation, false at `apply`, held results included), read with `withObservationTracking` by `AppModel.followEvaluation()` (no polling); the wait starts when it goes true and the chip goes when it goes false. The names only word the chip: the nodes whose `NodeState` is `.evaluating` (the state the node badge's spinner draws), as the graph panel names them, Output nodes left out of the name and the count, the rest ordered by how long each took last time, longest first, then name, then ID (`AppModel.chipNames(of:)`; the times are `DocumentModel.lastDurations`, from `.ok(duration:)` at `apply`, unobserved, a warning carrying none, replaced with the document). They are approximate (an edit marks every stale downstream node at once and the evaluator reports no per-node progress, so a name may be a node already done), and with none (a file opening, a node new to the graph) the chip reads "Building…". No percentage. It takes no pointer (a click where it appeared reaches the viewport) and isn't hidden in sketch mode.

The app installs the window's input through `AppInput`, never `GraphPanelInput.install(on:)` (only
`GraphPanelPreview` still uses it), because New and Open replace the document's `GraphPanelInput`.
App-shell input stopgaps live only in `AppInput`: the viewport's keys carry the `!Panel` key context (the graph panel
and the inspector contribute `Panel`), and over the graph canvas F, + and − are declined so the graph's own keys work
(F frames the graph's selection there). The
camera reaches `ViewState` only through `cameraSettled`/`homeChanged`, never per frame. Regular Polygon is
`typeVersion` 2 (`rotation`), and so are TPMS, Strut Lattice and Voronoi Lattice (`blend`: their `migrate` stores 0, the sharp join they were saved with, while a new node reads the socket's 1 mm).

Drawing refresh key (`DrawingSession.RefreshKey`, drawings speed R5): `RefreshKey.annotations` holds each annotation as `DrawingAnnotation.placementStripped` (CreatorDrawing), so a drag of where an annotation sits changes no key and starts no last-good refresh (`AppModel.drawingRefreshStarts` counts the tasks started; `DrawingRefreshKeyTests`). Placement fields, which `AnnotationRefresh.lastGood` never reads: a dimension's `placement.offset` (kept as its side, 5 or -5: `DrawingMeasure` picks the end of a line nearer the side the offset points to) and `placement.textShift`, a hole callout's whole `placement`, a datum's `distance` and `dimensionEnd`, a frame's and a surface texture's `offset`, a balloon's `offset`, a parts list's `bottomRight`, a revision table's `topRight` (a note's `position` too, though notes never reach the key). Centre marks and lines have no placement field and stay as they are. What `lastGood` reads stays in the key: anchors, a dimension's `placement.angle` (an angle dimension's sector), a symbol's leader (anchor and hint find its foot) and a balloon's whole leader. A new annotation field is read until `placementStripped` says otherwise; the cost of a wrong strip is a figure that does not refresh after a drag.
