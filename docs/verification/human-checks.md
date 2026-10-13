# Human checks

Checks an agent can't perform: each needs a person at an unlocked Mac with a real pointer. Tick the box and write
one line under **Observed** ("as expected", or what you saw). Each item names the test that pins the behaviour
headless, so a "looks wrong" report can become a failing test.

## Group V — the 3D viewport (M4)

**Status: IN PROGRESS** (2026-10-07: V7, V9 pass; V5 labels confirmed). Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`).

Run `swift run ViewportHarness` (variants: `HARNESS_GHOST=1`, `HARNESS_SELECT=1`). Clicks, menu choices and handle
drags print to the terminal.

- [ ] **V1 Looks.** You should see:
  - the bracket shaded in lavender greys (spec §6.6, #c5c8de → #6f739a) on a vertical gradient (#3a3d4e → #191a21)
  - white B-rep edges sitting exactly on the surface: no gaps, no flicker along faces, and no triangle wireframe
  - the ground grid under the part, the X/Y/Z triad at the bottom-left, and "mm · grid 10 mm" at the bottom-right

  The edges and the MSAA are smooth on a Retina display. Pinned: `edgePolylinesLieOnTheMesh`, `theShadedPassEncodesEveryLayerCleanly`.
  Observed:
- [ ] **V2 Orbit.** Dragging on the part rotates about the point under the pointer: that point stays put. Dragging on empty
  space rotates about the part's centre. Dragging far up or down stops at straight-down or straight-up, with no flip
  and no spin. Pinned: `orbitKeepsThePivotWhereItWasOnScreen`, `orbitClampsPitchAtThePoles`. Observed:
- [ ] **V3 Pan, zoom and frame.**
  - Shift-drag pans with the pointer (Shift held when the drag starts; the drag reads it from MetalUI, C7).
  - ⌥-drag up zooms in toward where the drag began.
  - + and − zoom toward the pointer.
  - F frames the part (with `HARNESS_SELECT=1`, the selected top face).

  Pinned: `shiftDragPansAndOptionDragZooms`, `keyZoomGoesTowardTheLastHoverPoint`, `fFramesTheSelectionBeforeEverything`. Observed:
- [ ] **V4 Hover.** The face under the pointer gets a faint cyan tint that follows the pointer without flicker or lag.
  After an orbit drag, a +/− zoom or a view-cube click with the pointer left still, the tint is on the face under
  the pointer now, not the one before the move.
  Pinned: `hoverAsksThePickerOrTheCube`, `movingTheCameraUnderAStillPointerRepicks`,
  `idPassReportsTheFaceAndEdgeUnderChosenPixels`. Observed:
- [ ] **V5 View cube.**
  - TOP, FRONT, RIGHT and the other names are painted on the faces: they tilt and turn with the cube, and a face
    turned away hides its name. Each reads upright and unmirrored seen from outside (side faces with +Z up, TOP
    with +Y up as the TOP view shows it, BOTTOM with −Y up so it reads upright after rolling under from FRONT;
    TOP seen from the back is upside down, as in Fusion). They stay visible through the 250 ms animation, and are
    crisp on a Retina screen and smooth at steep angles (no shimmer or jaggies while orbiting). The text runs
    across the face's edge tiles; hovering an edge or corner tints the tile under the text, and the name stays
    on top. Pinned: `CubeLabelTests`, `theFrontLabelIsPaintedOnTheFrontFace`.
  - The region under the pointer turns cyan, and so does the region the camera looks straight from (FRONT after
    clicking FRONT). Pinned: `theCubeTintsTheRegionTheCameraLooksFrom`.
  - Clicking FRONT animates (about 250 ms, smooth) to a straight-on orthographic view.
  - Clicking an edge or corner gives a 45° or isometric view in the current projection.
  - Dragging the cube orbits.
  - ◀ ▲ ▼ ▶ rotate 90° to the adjacent face, and ⌂ goes home.
  - The View menu switches Perspective and Orthographic, Shaded and Shaded + Edges, and Set Home View makes ⌂ return there.

  Pinned: `ViewCubeTests`, `clickingTheCubeLooksAtTheRegionUnderThePointer`, `arrowsAndHomeAnimate`. Observed: 2026-10-07: the painted face labels sit on the faces, turn with the cube and read well (user). Animation, edge/corner views, cube drag, arrows, ⌂ and the View menu not yet confirmed.
- [ ] **V6 Face menu.** Right-click a face: Look At, Select Edges of Face and Show Producing Node, for the face under
  the right press (VC5 checks that after the camera moves).
  - Look At animates to face that face, orthographic, framed on it.
  - The other two print the face's edges and the producing node.
  - Right-click empty space: no menu.

  Pinned: `ContextMenuTests`. Observed:
- [x] **V7 Ghost.** `HARNESS_GHOST=1` draws the part desaturated at about 40% opacity, with the grid visible through it.
  It's one even layer: the far side, the hole walls and the back faces don't show through or darken it (the depth
  prepass). Speckles on the ghost would mean the prepass and colour pass disagree on depth: add `[[invariant]]` to
  the vertex position in `ViewportShaders` and compile with `MTLCompileOptions.preserveInvariance = true`.
  Pinned: ghost flags in `ghostsSelectionAndHoverReachTheFrame`. Observed: 2026-10-07 PASS: desaturated, see-through and even; grid visible through it; no speckles (user screenshot).
- [ ] **V8 Selection.** `HARNESS_SELECT=1` shows the flange's top face and its edges glowing pink (#ff79c6). Edges stay
  pink in Shaded mode. In any mode, clicking a face selects it and its edges, clicking an edge selects that edge,
  and clicking empty space clears (the harness applies clicks itself; in the app, selection belongs to the shell). Pinned: `edgeInstancesAreOnePerSegmentWithTheirPickID`. Observed:
- [x] **V9 Handles.** A purple arrow handle at the plate top labelled "6 mm", and an orange radial handle at a fillet
  labelled "R 3 mm". Dragging a knob moves it along its axis, the label follows, and the terminal prints `changed`
  values and one `ended`. The camera doesn't move. Handle labels are there from the first layout of a document with a saved camera and follow a live resize (the viewport's size is `onGeometryChange`'s, gap M4-a, adopted). Pinned: `draggingAHandleEditsItsValueAndNotTheCamera`, `handleLabelsAreRebuiltWhenTheLayoutReportsTheFirstSize`. Observed: 2026-10-07 PASS: both handles dragged (plate 5→10.7 mm, fillet 4.4 mm); each drag printed `changed` values and exactly one `ended` (harness log).
- [ ] **V10 Resize and displays.** Resizing the window live shows no stretched or blank frames, and picking stays
  accurate after a resize (handle labels follow the resize at once: the viewport's size is `onGeometryChange`'s, gap M4-a, adopted; pinned `aResizedWindowResizesTheViewport`). Moving between a Retina and a 1× display keeps lines crisp. Starting the harness in a
  narrow window (drag it narrow, quit, relaunch) frames the whole bracket, not clipped at the sides. Pinned:
  `aSceneShownBeforeTheFirstDrawIsFramedOnceTheViewHasASize`. Observed:
- [ ] **V11 Grid steps.** Zooming in and out switches the grid between 1, 10 and 100 mm, and the label follows. Pinned:
  `gridSpacingStepsWithZoom`. Observed:

## Group VC — viewport input on MetalUI C7

**Status: PASS** (2026-10-09: VC1–VC8 pass, user). Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`); MetalUI's own
group Y covers the platform side (trackpad phases, real mouse buttons, every cursor).

The `viewport-input` branch merges before this group is run: the tests pin the model only, and the view glue in
`ViewportView+Parts.swift` `surface(model:)` has no test through a window yet (gap M6-e is adopted: a `MetalUITesting`
window can drive it, and a press on the viewport already runs through it in `CanvasTypingFocusWindowTests`). That
glue is the tap declared inside the primary drag, the secondary drag deferring the face menu to release, the scroll
delta's sign, `.pointerStyle(model.cursor?.pointerStyle)`, the located `.contextMenu` overload, and `pressed()`
(the text-focus release) firing on release rather than on press. Run this group first after the merge, in this
order: VC3, VC4, VC5, then VC1's scroll sign, then the rest. A failure there is a bug in that glue (or in MetalUI
C7), not in the model.

Run `swift run ViewportHarness` (VC7 also with `HARNESS_PICK=1`) with a trackpad and a three-button mouse; VC8 runs
`swift run MetalCreatorApp` on a saved bracket. Clicks and menu choices print to the terminal.

- [ ] **VC1 Scroll zoom.** Two-finger scroll over the part zooms toward the point under the pointer: that point
  stays put. When the fingers lift the zoom stops at once (no glide). A wheel mouse zooms in steps of about 10%;
  spinning it fast stays smooth, and the hover tint catches up just after the wheel stops.
  Scrolling one way zooms in and the other way out; note which way feels wrong, if one does (the sign is
  `ViewportModel.scrolled(by:at:phase:)`). Pinned: `ScrollZoomTests` (`aRunOfWheelStepsSettlesOnce`),
  `scrollEventsMapToZoomPhases`. Observed: 2026-10-09 PASS (user, release ViewportHarness).
- [ ] **VC2 Pinch.** Pinching out zooms in about the point where the pinch began, and pinching in zooms out; a hard
  pinch-in holds instead of springing back. A twist does nothing. Pinned: `PinchZoomTests`. Observed: 2026-10-09 PASS (user, release ViewportHarness).
- [ ] **VC3 Right and middle drags.** Middle-drag pans with the pointer, whatever is held. Right-drag orbits about the
  point under the pointer (on the view cube, it orbits like a cube drag) and opens no menu. A right click that
  doesn't move opens the face menu on release. Right-drag on a handle's knob orbits and leaves the value alone.
  Middle-drag, ⌘-Tab away before releasing, release, come back: a primary drag orbits at once and the closed hand
  goes. Pinned: `ButtonDragTests`, `theRightButtonOrbitsAndTheMiddleButtonPans`. Observed: 2026-10-09 PASS (user, release ViewportHarness); the stationary right-click opened the face menu (Show producing node chosen, harness log).
- [ ] **VC4 Clicks.** A click on a face or an edge prints `clicked` with it; on empty space `clicked: nil`. A press
  dragged more than a few points and brought back prints no click (the camera keeps the orbit). A click on a view-cube
  face still animates to it, and a click on a handle's knob prints nothing. Pinned: `aClickReportsThePickAtItsLocationAndLeavesTheCameraAlone`,
  `aDragThatComesBackToItsStartIsNotAClick`, `aClickOnAHandleKnobOrTheCubeReportsNoPick`. Observed: 2026-10-09 PASS (user, release ViewportHarness): face clicks printed their faces, empty space `clicked: nil` (harness log).
- [ ] **VC5 The menu is for the face under the press.** Hover a face, scroll-zoom so another face comes under the
  still pointer, and right-click without moving: the menu is for the face under the pointer now (Look At turns to
  it). Right-click the view cube: no face menu. Pinned: `theMenuIsForTheFaceUnderThePressNotTheLastHover`,
  `noFaceMenuOverTheViewCubeOrWithoutAPointer`. Observed: 2026-10-09 PASS (user, release ViewportHarness).
- [ ] **VC6 Modifiers mid-drag.** Hold Shift, then drag: it pans. Hold ⌥, then drag up: it zooms in. Switch to another
  app with Shift held, release Shift there, come back and drag: it orbits (no stale Shift). Pinned:
  `aPrimaryDragTakesItsModeFromItsOwnModifiers`. Observed: 2026-10-09 PASS (user, release ViewportHarness).
- [ ] **VC7 Cursors.** A closed hand while a primary, right or middle drag orbits or pans, and while dragging the view
  cube; the arrow for a ⌥-drag zoom, a handle drag and over the cube's buttons. With `HARNESS_PICK=1` the pointer is a
  crosshair over the viewport, and a hand while a drag navigates. In the app, "Pick edges in view…" shows the
  crosshair; Done or Cancel brings the arrow back. Pinned: `CursorTests`, `theViewportShowsACrosshairOnlyWhilePicking`.
  Observed: 2026-10-09 PASS (user, release ViewportHarness).
- [ ] **VC8 Framing in the model area (app).** Open a saved bracket with no saved camera (or press F): the part sits
  in the middle of the area right of the graph panel and left of the inspector, not under either. Dock the panel at
  the bottom and press F: the part is centred above the panel. Right-click a face ▸ Look At: the face is centred in
  the same area. With either dock, after F click ▶, then ▲, then a cube face and a cube corner, then drag the cube:
  the part turns in place, centred in the area, never swinging under the inspector or the bottom panel. With the
  pointer off the window (over the menu bar), press + and −: the part stays centred. Pinned:
  `ModelAreaFramingTests`. Observed: 2026-10-09 PASS (user, release MetalCreatorApp).

## Group GI — graph panel and app input on MetalUI C7

**Status: IN PROGRESS** (2026-10-09: GI-1 and GI-3 pass, user). Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`); MetalUI's own
group Y covers the platform side (trackpad phases, momentum, every cursor).

The tests pin the model and the conversions from MetalUI values only. The view glue has no test through a window yet
(gap M6-e is adopted: a `MetalUITesting` window can drive it; the canvas typing and the graph's keys already do, group CT):
`GraphCanvas`'s `.gesture`, `.onScrollWheel` and `.pointerStyle` lines,
`GraphPanel`'s opaque backdrop and `PanelResizeHandle`'s `.pointerStyle`. Run GI-4, GI-1 and GI-6 first: a
failure there is a bug in that glue (or in MetalUI C7), not in the model.

Run `swift run MetalCreatorApp` on a saved bracket, with a trackpad and a wheel mouse; GI-8 also runs
`swift run GraphPanelPreview`.

- [ ] **GI-1 Scroll pans.** Two-finger scroll over the graph canvas pans it in every direction, the nodes following
  the fingers; a flick glides to a stop. A wheel mouse pans up and down a step at a time. Nothing else moves: the
  viewport doesn't zoom and the inspector doesn't scroll. Flick, then move the pointer off the canvas mid-glide, onto
  the viewport and then onto the node library: record whether the glide stops and whether the library scrolls
  (gap GI-b, answered by C16-1). Pinned: `aWheelStepPansTheCanvasByItsDelta`, `aTrackpadScrollPansAndItsGlideKeepsPanning`,
  `scrollEventsMapToCanvasPhases`. **Observed:** 2026-10-09 PASS (user: "pan and pinch both work well").
- [ ] **GI-2 ⌘-scroll zooms about the pointer.** Hold ⌘ and scroll over a node: the node stays under the pointer as
  the canvas zooms. One way zooms in, the other out; note which way feels wrong, if one does (the sign is
  `EditorModel.scrolled(by:at:modifiers:phase:)`'s, the viewport's too). Flick with ⌘ held: the zoom stops when the
  fingers lift, with no glide, and the canvas doesn't pan either, even if ⌘ is let go during the glide. Start a plain
  scroll, then press ⌘ part-way: it keeps panning until the fingers lift. The zoom stops at 25% and 300%. Pinned:
  `commandScrollZoomsAboutThePointer`, `aZoomScrollsGlideIsIgnored`, `aZoomsGlideIsIgnoredOnlyUntilItsMomentumEnds`,
  `aTrackpadScrollZoomsOrPansAsItBegan`, `aScrollThatBeganElsewhereIsTakenUpAsItIsNow`, `theScrollZoomStaysInRange`,
  `aScrollEventZoomsAboutItsLocalPoint`. **Observed:**
- [ ] **GI-3 Pinch.** Pinch out over a node: the canvas zooms in about the point where the pinch began; pinching in
  zooms out, and a hard pinch-in holds at 25% instead of springing back. A pinch over the viewport still zooms the
  viewport, not the canvas. Pinned: `CanvasPinchTests`. **Observed:** 2026-10-09 PASS (user: "pan and pinch both work well").
- [ ] **GI-4 The panel's chrome takes the pointer.** Over the graph panel's header (between its buttons), its padding
  and, while one shows, the refusal line under the canvas: scroll, ⌘-scroll and pinch, and nothing moves (before this
  plan the viewport beneath zoomed); click there, and no face is picked or highlighted in the viewport and the
  selection doesn't change; hover there after hovering a face, and the viewport's hover highlight goes. The header's
  buttons still work. Scroll over the node library: its list scrolls and the canvas doesn't. Pinned: none (view
  glue). **Observed:**
- [ ] **GI-5 Modifiers come from the press.** Shift-click two nodes: both are selected. Press on a third with ⇧ held,
  let go of ⇧, then release: it is added too. Click a node without ⇧ right after: only it is selected. ⇧-drag on
  empty canvas box-selects; ⌥-drag a node duplicates it; press on a node, then hold ⌥ before moving: it duplicates.
  Hold ⇧, ⌘-Tab to another app, let go of ⇧ there, come back and click a node: a plain click. Pinned:
  `PressModifierTests`, `modifierChangesAreNeitherClaimedNorTracked`,
  `theCanvasGestureReadsThePressModifiersFromItsValues`, `anOptionDragThroughTheGestureDuplicates`. **Observed:**
- [ ] **GI-6 Cursors.** Middle-drag the canvas: a closed hand from the press until the release, also when the pointer
  leaves the panel mid-drag (since multi-select a plain drag on empty canvas box-selects, MS-3); a click shows none.
  Moving nodes, dragging a wire and box selection keep the arrow. Hover the dock's inner edge: a left-right resize
  cursor docked left, an up-down one docked at the bottom, kept while dragging it. Pinned: `CanvasCursorTests`,
  `theLeftDocksEdgeIsAColumnResizeAndTheBottomDocksARowResize`. **Observed:**
- [ ] **GI-7 The palette.** Open the palette (Space) over the canvas, then scroll or pinch over the canvas outside
  it: it closes. Open it again and scroll over the palette itself: the canvas doesn't move and the palette stays.
  Pinch over the palette: nothing moves (neither the canvas nor the viewport) and it stays open.
  Pinned: `aScrollThatMovesTheCanvasClosesThePalette`, `aPinchClosesThePalette`, `PaletteOverlayWindowTests` (`aScrollOverItDoesNotReachTheCanvasOrTheViewport`,
  `aPinchOverItMovesNothingAndItStaysOpen`). **Observed:**
- [ ] **GI-8 Keys unchanged, and the preview.** Over the canvas, + and − still zoom it (not the viewport), F frames
  the graph's selection (MS-6; before multi-select it framed the viewport), Tab and Space open the palette, and
  Delete, ⌘C, ⌘V and ⌘D work after a canvas click. Then in
  `swift run GraphPanelPreview`: GI-1, GI-2, GI-3, GI-5 and GI-6's canvas half behave the same. Pinned:
  `AppInputTests`, `KeyCommandTests`. **Observed:**

## Group M5 — the graph panel and inspector (M5)

**Status: IN PROGRESS** (2026-10-07: V7, V9 pass; V5 labels confirmed). Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`).

Run `swift run GraphPanelPreview`.

- [ ] **M5-1 Dracula colours.** Headers are comment-blue (Number), green (Rectangle), purple (Extrude), pink
  (All Edges), orange (Fillet), cyan (Output). Header text is dark (`#282a36`). Body text is near-white, hint text
  blue-grey. Pinned: `PaletteTests`. **Observed:**
- [ ] **M5-2 Selection outline.** Click Extrude: it gets a 2-pt outline in *purple*, its own header colour, and no
  glow. Click Fillet: the outline is orange. Pinned: `selectionOutlineIsTheNodesOwnHeaderColour`. **Observed:**
- [ ] **M5-3 Glass panels.** The panel and inspector are translucent dark with a faint 1-pt light hairline and rounded
  corners, over a blur of the viewport (gap C10-a, adopted with MetalUI C21; checks C21-1 to C21-3). **Observed:**
- [ ] **M5-4 Wires.** Wires are smooth curves leaving outputs forwards and entering inputs forwards, coloured by the
  source socket (green from Rectangle, purple from Extrude, pink from All Edges). Socket dots use the same colours.
  Pinned: `WireGeometryTests`, `wiresRunBetweenTheirSocketAnchors`. **Observed:**
- [ ] **M5-5 Docks.** Press Left: the graph becomes a column flowing top to bottom, inputs on top edges and outputs
  on bottom edges, the layout a mirror (x↔y) of the bottom dock. Press Bottom: it flows left to right again with
  every node back where it was. Press Hide: the panel goes and a "Show graph" button appears at the bottom left.
  Press Tab (even with an inspector field focused): the panel returns to the last side. Hide again and click "Show
  graph": same. Pinned: `DockTests`, `theHiddenPanelLeavesAShowButton`; the Tab shortcut is this check only.
  **Observed:**
- [ ] **M5-6 Pan, zoom, hit testing.** Middle-drag the canvas (or scroll with two fingers): it pans (since
  multi-select a plain drag on empty canvas box-selects, MS-3). Press + three times with the pointer over a node:
  the node stays under the pointer. Click a socket's edge at that zoom and drag: a cyan wire follows the pointer.
  Pinned: `HitTestTests`, `MiddlePanTests`. **Observed:**
- [ ] **M5-7 Wiring.** Drag Rectangle's output onto Extrude's profile input: a wire is made (it replaces the old one).
  Drag Number's output onto Extrude's profile: nothing connects, Extrude shakes (6 points right, 6 left, home in a
  fifth of a second; check C10-2), and "A number can't connect to a profile input." shows under the canvas for about two seconds.
  Drag from Extrude's wired profile input onto empty canvas: the wire is removed; ⌘Z brings it back.
  Pinned: `WiringTests`. **Observed:**
- [ ] **M5-8 Box select and ⌥-drag.** Hold ⇧ and drag on empty canvas: a cyan box selects what it touches. Hold ⌥
  and drag a selected node: translucent ghosts follow, and on release copies appear there with their wires; ⌘Z
  removes them in one step. Pinned: `PointerTests`. **Observed:**
- [ ] **M5-9 Palette.** With the pointer over the canvas press Space: a glass palette opens at the pointer with the
  field focused. Type "t", press ↓ twice and ↑ once: the highlight moves down two rows and back one, while the field
  keeps focus (the arrows are window keymap actions, gap M5-h). Press Return: the highlighted node is added there
  and selected. Open it again and type a space: it goes into the field (no second palette). Escape closes it.
  Pinned: `SearchPaletteTests`, `KeyCommandTests`, `paletteArrowsAreKeymapActionsOnlyWhileThePaletteIsOpen`; the
  routing through a focused field is this check only. **Observed:**
- [ ] **M5-10 Inspector.** Select Rectangle: header in green with "Rectangle", Size sliders, a segmented XY/XZ/YZ
  plane picker and a 3×3 anchor grid; Document Parameters below. Drag the Width slider, release, then press ⌘Z
  once: width returns to where the drag started. Select Fillet: an EDGES section reads "All Edges · 12 edges" in
  pink, a "Show handle in view" toggle that starts On, and a "Pick edges in view…" button. Select All Edges: its
  EDGES row reads "12 edges". Drag Radius above 10: Fillet's badge turns to a red ✕ and hovering it shows the message.
  Select Extrude: a Distance/Symmetric segmented control, the Distance slider and a "Reverse direction" toggle that
  starts Off (no Direction menu, spec Errata (M3)).
  Add a Transform (palette): its Move row has three fields; type 5 into the middle one and the node row reads
  "0 mm, 5 mm, 0 mm". Add a Graph Parameter: its menu lists Width; choose it and the menu shows Width.
  Add a Grid Points: its Total field is empty, showing "Not set", and the node row reads "—". Type 6 and press
  Return: the row reads "6". Empty the field and press Return: it's "Not set" again. Click empty canvas and press ⌘Z: 6 comes back.
  Pinned: `InspectorTests` (`anOptionalInputStartsUnsetAndCanBeCleared`), `CoalescingTests`. **Observed:**
- [ ] **M5-11 Keys stay with fields.** Click into the Width number field, type "75" and press Delete: the digit is
  deleted, not the node. Press Return: Width becomes 75 mm. Pinned: design (`Window.onInput` fallback),
  `mappedKeysAreRunAndClaimed`. **Observed:**
- [ ] **M5-12 A canvas press gives the keys back.** Edit the Width number field (type "70", Return), then click the
  Extrude node on the canvas and press Delete: Extrude is deleted (not a character in the field). Press ⌘Z: Extrude
  comes back (the graph's undo, not the field's). Press Space over the canvas: the palette opens. Pinned:
  `aCanvasPressReleasesTextFocusOncePerPress`; the focus release itself is this check only (gap M5-g). **Observed:**
- [ ] **M5-13 Tab over the canvas.** With the inspector showing its fields (any node selected, or none: Document
  Parameters is always there), move the pointer over empty canvas and press Tab: the add-node palette opens at the
  pointer with its field focused. Escape, move the pointer onto the inspector and press Tab: focus moves to the next
  inspector field and no palette opens. Pinned: `tabIsAKeymapActionThatOpensThePaletteOnlyOverTheVisibleCanvas`; the
  routing ahead of focus traversal is this check only (gap M5-b). **Observed:**

## Group M6 — the app (M6)

**Status: NOT RUN.** Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`).

Run `swift run MetalCreatorApp` (or `swift run MetalCreatorApp path/to/file.mcgraph`).

- [ ] **M6-1 The bracket from scratch (spec §7.2 steps 1–4).** In an empty window, using only the palette (Space or
  Tab over the canvas), the inspector and the Document Parameters: add `Width` = 60, `Wall` = 6 and `Hole count` = 4
  (integer); build the rounded plate, the Grid Points → Circle Ø5 → Extrude → one subtract Boolean, the L-flange
  (Rectangle on XZ, extruded, unioned), the Fillet R3 on Edges by Direction(Z) ∩ Edge Filter(convex), and an Edges by
  Tag rule on the fillet's solid feeding a Chamfer 0.5 into an Output. Select the Chamfer, press "Pick edges in view…":
  only the filleted solid shows, with a pink banner. Click the plate's top outline edges (they turn pink), press Return.
  Every node's badge is green. Pinned headless: `theBracketIsBuiltPickedSavedReopenedReparameterisedAndExported`.
  **Observed:**
- [ ] **M6-2 Exports (spec §7.2 steps 5–6).** File ▸ Export STEP… and Export STL… offer "<Output name>.step/.stl".
  Open the STEP in FreeCAD or Fusion: the geometry matches (holes, flange, fillets, chamfer). Load the STL in a slicer:
  it's accepted as manifold. Set Width to 90 and Hole count to 6: the fillet and chamfer stay on the intended edges, no
  badge turns yellow or red, and both exports work again. Pinned: `expectExports`. **Observed:**
- [ ] **M6-3 Files.** Save (⌘S) asks where for a new document, then the top bar reads the file's name. Change a value:
  "— Edited" appears; Save clears it. Orbit and press ⌂ ▸ Set Home View, save, quit, and reopen the file
  (`swift run MetalCreatorApp file.mcgraph` and File ▸ Open…): the same graph, camera and home view come back. With
  unsaved changes, New and Open ask "Discard unsaved changes?"; Cancel keeps the document, and a later New asks again.
  Pinned: `AppModelFileTests`.
  **Observed:**
- [ ] **M6-4 Keys and focus.** **Automated, no manual step** (`ViewportKeyRoutingWindowTests`, `PaletteKeyRoutingWindowTests`,
  through the app's real window): "f", "+" and "-" pressed with an inspector field focused leave the viewport alone, and a
  press on the viewport gives the keys back; with the pointer over the viewport + and − zoom it and F frames it; over the
  graph canvas + and − zoom the graph and F frames the graph's selection, not the viewport (spec 2026-10-09 §3: this
  line used to say the viewport frames); the open palette's search field takes "f+". **By hand:** the same on a
  physical keyboard (+ is ⇧= on a US layout). Pinned: `AppInputTests` (the mapping). **Observed:**
- [ ] **M6-5 Menu bar and chords (what is left).** **Automated, no manual step** (`EditMenuRoutingWindowTests`): the Edit menu
  is titled by the step ("Undo Edit Note") and its Undo and Redo run; ⌘Z and ⇧⌘Z undo and redo one step each over the
  canvas and over the viewport; with a node selected and the pointer over the canvas, ⌘C, ⌘V and ⌘D copy, paste and
  duplicate it (the standard Copy and Paste items don't swallow the keys) and do nothing over the viewport. **By hand:**
  ⌘N, ⌘O, ⌘S, ⇧⌘S, ⌘E and ⇧⌘E run New, Open…, Save, Save As…, Export STEP… and Export STL…. **Observed:**
- [ ] **M6-6 A typed value isn't lost.** Type 75 into Width without pressing Return, then click the viewport: Width
  becomes 75 (one ⌘Z undoes it). Type 50 into a node's field and click another node on the canvas: the first node gets
  50, the second is unchanged. Type a value and press Tab: it's committed. Type 80 into Width without Return and
  press ⌘Z (and, separately, the top bar's Undo): Width goes back to its previous value, ⇧⌘Z brings 80 back, and
  clicking elsewhere afterwards changes nothing. Pinned: `PendingEntryTests`, `aViewportPressCommitsATypedInspectorValue`,
  `undoAndRedoCommitATypedValueFirst`; the focus-loss path is this check only (`NumberEntry`'s `@State` draft
  isn't reachable from a test). Type "abc" into Width and press Tab: the field shows Width's value again, not
  "abc"; type Width's current value and press Tab: the field shows it formatted as before. **Observed:**
- [ ] **M6-7 Layout.** The viewport fills the window; the top bar, graph panel and inspector float over it as glass
  (a blur of the viewport under the theme's tint, gap C10-a, group C21). The view cube sits at the top-left of the uncovered area, right of the panel; the triad at its
  bottom-left and "mm · grid" at its bottom-right, clear of the panels. Press Bottom, then Hide, then "Show graph":
  the cube, triad and label move with the panels. Drag the panel's inner edge (the faint strip): it resizes, within
  limits, and the cube follows. Pinned: `theViewportOverlaysMoveOutFromUnderThePanels`,
  `theDockedPanelIsLaidOutToTheModelsWidth`. **Observed:**
- [ ] **M6-8 Preview.** Preview ▸ Selected node, select the Extrude of the holes: only the four hole cylinders show.
  Select the Edge Set Op: the bracket before filleting shows with the four fillet edges pink. Select nothing: the
  viewport is empty. Preview ▸ Final: the whole bracket again. Still in Final, select the fillet's Edge Set Op and the
  chamfer's Edges by Tag: their edges are drawn over the finished part (M6-16). Orbit, pan the graph canvas and drag
  the panel edge: the part doesn't flicker or reload. Pinned: `SceneTests`,
  `aRuleSelectedInFinalPreviewGlowsOnItsOwnShownSolidAndAddsNoGuide`,
  `panningTheCanvasOrSettlingTheCameraDoesntRebuildTheScene`.
  **Observed:**
- [ ] **M6-9 Handles.** Select the flange's Extrude: a purple arrow with "8 mm" starts on the flange profile; drag it
  and the flange thickens live; release and ⌘Z undoes the whole drag in one step. Select the Fillet: an orange radial
  handle "R 3 mm" sits at a fillet edge; turn "Show handle in view" off and it goes. The plate's Extrude (distance wired
  from Wall) shows no handle. Select the holes' Extrude (Symmetric, 20 mm): its arrow starts at the hole profile's
  centre and the knob sits on the far cap, 10 mm out; drag it and the knob stays under the pointer while the distance
  grows twice as fast. Change a value, ⌘Z it, then click a knob without moving: ⇧⌘Z still redoes it and ⌘Z has
  nothing new to undo. Pinned: `HandleTests`, `draggingAHandleEditsItsInputAsOneUndoStep`,
  `aHalfScaleHandlesKnobTracksThePointer`, `aHandleClickWithoutMovingRecordsNothing`. **Observed:**
- [ ] **M6-10 Face menu.** Right-click a face: Look At animates to face it. Select Edges of Face adds a selected
  Edges by Tag node wired from the part's last feature (⌘Z removes it). Show Producing Node selects the node that made
  the face and scrolls the graph to it, showing the panel if it was hidden. Pinned: `PickingTests`,
  `showProducingNodeSelectsItAndScrollsTheGraphToIt`. **Observed:**
- [ ] **M6-11 Pick mode.** On the Chamfer, press "Pick edges in view…": clicking a picked edge again unpicks it,
  Escape cancels with nothing changed, and Done writes the picks as one undo step. Right-click a face while picking:
  Select Edges of Face adds its edges to the pick. Open the palette (Space over the canvas) and press "Pick edges in
  view…": the palette closes. Known: if the palette is opened *during* a pick, Escape and Return go to the banner's
  Cancel and Done (button shortcuts run before the palette's keys). Pinned: `PickingTests`. **Observed:**
- [ ] **M6-12 A broken part.** Set the Fillet radius to 30: the Fillet's badge turns red, the bracket is drawn ghosted
  (its last good shape), and Export STEP… says "“<Output name>” can't be exported" with the reason, without opening a
  save panel. Set it back to 3: the part is solid again. Pinned: `anErrorUpstreamShowsTheLastGoodResultAsAGhost`,
  `anOutputWithoutAResultSaysWhy`. **Observed:**
- [ ] **M6-13 Themes (spec §6.6).** The app opens in Dracula, matching the §6.6 table as M4 and M5 drew it. View ▸
  Theme lists Dracula (checked), Alucard and Nord. Choose Alucard: at once, with no reload or flicker of the part, the
  background turns cream; the glass panels, node bodies, headers, sockets, wires, badges and inspector text take
  Alucard's colours; MetalUI's own controls (buttons, sliders, fields, menus) turn light; and the viewport repaints
  the part's shading, its edges, the grid, the handles, the triad and the view cube with its face names. The checkmark
  moves to Alucard. Hover a cube face (the focus colour), pick edges (the selection colour) and break the fillet (the
  error badge): every role has its Alucard colour and all text reads. Choose Nord, then Dracula: Dracula looks exactly
  as at launch. Save, choose New and reopen the file: the theme stays (it is the app's, not the document's), and the
  `.mcgraph` file holds no theme. Quitting forgets the choice until the Themes milestone. Pinned: `ThemeTests`,
  `ThemeStoreTests`, `ThemeRenderTests`, `ViewportPaletteTests`, `theViewportDrawsTheChosenThemeAcrossDocuments`,
  `theWindowRepaintsInTheChosenTheme`. **Observed:**
- [ ] **M6-14 The triad follows a dock resize.** With the graph panel docked at the bottom, drag its top edge up as far
  as it goes, then down as far as it goes, and release each time without moving the pointer over the viewport
  afterwards: the X, Y and Z letters stay at their axes' tips (never above or below the drawn triad), and
  "mm · grid" stays at the bottom-right of the uncovered area. Repeat docked at the left, dragging its right edge both
  ways. Pinned: `theTriadsLettersStayOnItsAxesWhenTheDockResizes`, `aModelAreaThatMovesOnlyTheTriadRedraws`.
  **Observed:**
- [ ] **M6-15 Dragging a Fillet radius past its maximum (spec Errata, Kernel: invalid blends).** On the bracket, select
  the Fillet and drag its Radius slider above the largest size that works: the badge turns to a red ✕ and hovering it
  shows "Radius N mm is too large for the selected edges (max ≈ X mm).", N the radius dragged to and X a size from the
  part (a message without a maximum is wrong). The drag stays responsive (a refused radius searches for the maximum
  on every step, so the badge may trail the slider by a fraction of a second); dragging back below X clears the error
  and shows the part again. Repeat with the Fillet's radius handle in the viewport (spec §7.2): past the maximum, the
  same message. Pinned: the maximum in the message: `UnbuildableBlendTests`, `InvalidBlendTests`; the drag's feel is
  this check only. **Observed:**
- [ ] **M6-16 A selected rule's edges over the Final part.** With the bracket open in Preview ▸ Final, select the
  fillet's Edge Set Op: its four edges (the flange's vertical corners, as in M6-8) show pink, as thick as a selection
  glow, over the finished part. R3 rounds those corners away, so the pink lines float just outside the rounded corners
  (the part has no edge of its own there to cover). Select the chamfer's Edges by Tag too: the plate's top outline is
  pink over the chamfered part. Orbit: the pink lines stay on their edges, with no flicker or shimmer, and any piece
  the part hides in front of it shows as a faint pink line through the part. Shaded (View menu) keeps them. Click and
  right-click on a pink line in free space: nothing is selected and no face menu opens. Press F with a rule selected:
  the view frames that rule's edges. Deselect: the lines go. Preview ▸ Selected node with one rule selected: the
  bracket before the feature, edges pink, with no extra lines. View ▸ Theme ▸ Alucard: the lines take its selection
  colour. Pinned: `SceneGuideTests`, `ViewportGuideTests`, `GuideRenderTests`. **Observed:**

## Group C10 — MetalUI C10's controls and looks (Adopt C10)

**Status: NOT RUN.** Plan `2026-10-09-adopt-c10.md`. The tests pin the models, the keyframes read at injected times, the
spinner's still frame and the gradient's pixels. Since the test-harness adoption (plan `2026-10-12-adopt-test-harness.md`,
gaps M6-e and M7-b) the shake's motion and the slider's undo pairing are also driven through the app's real window and
its clock (`RefusalShakeWindowTests`, `InspectorSliderWindowTests`); a real window is still needed for the spinner's
turning and for how things look. Run `swift run MetalCreatorApp`, and `swift run GraphPanelPreview`
for C10-5.

- [ ] **C10-1 Glass panels.** The top bar, graph panel and inspector are the theme's translucent fill with a faint 1-pt
  hairline and rounded corners; the viewport shows through blurred (MetalUI C21, group C21). Switch
  View ▸ Theme to Alucard and Nord: each panel takes that theme's glass colour (light in Alucard). In the theme editor change
  the Glass role's colour and opacity: every panel follows. Pinned: `GlassFillTests`. **Observed:**
- [ ] **C10-2 Refusal shake.** Drag Number's output onto Extrude's profile input: Extrude jumps 6 points right, 6 left and
  settles, in about a fifth of a second, crisp and not bouncy; the message shows under the canvas for about two seconds.
  Do it twice in a row, quickly: it shakes twice. Refuse Extrude, then another node: only the second shakes. Pan the
  canvas during a shake: the node keeps shaking at its new place and stops at rest. Pan a refused node out of sight and
  back: it does not shake. Drag a node normally: no shake. Pinned: `RefusalShakeTests` (the keyframes at injected times, the
  per-node count, a refused node drawn at rest). **Automated** (`RefusalShakeWindowTests`, fed through
  `EditorModel.connect`, not a pointer drag): in the app's window a refused node is 6 points out at 0.05 s, 6 across at
  0.15 s and home at 0.25 s, only that node moves, and a second refusal shakes again. **By hand:** the look (crisp, not
  bouncy), the message for two seconds, panning during a shake, a refused node scrolled out of sight and back, a normal
  drag. **Observed:**
- [ ] **C10-3 Evaluating spinner.** Make a node slow (a Boolean or a large-radius fillet on a dense part) and edit it:
  its badge shows a small spinner of twelve spokes turning steadily (MetalUI sets its period), then the time in ms. The
  spinner fits the header and reads on every header colour (value, profile, solid, selection rule, feature, output) in
  Dracula and in Alucard. Select the busy node: the inspector header's badge shows the same spinner, readable on its
  background (its colour is MetalUI's control accent, not the old status grey: accepted, user decision 4). While it
  turns, panning the canvas stays smooth; note the frame rate (a spinner redraws the whole window each frame, PERF-b).
  Pinned: `StatusBadgeRenderTests` (the still frame), `statusBadges`. **Observed:**
- [ ] **C10-4 Slider undo.** Select a node with a slider (Extrude's Distance): drag the slider, then ⌘Z once: the whole drag
  is undone and the value returns to what it was before the press. Drag it again twice with nothing in between: two ⌘Z. Use a
  document parameter's slider the same way. Click the slider's track without moving: one undo step (or none if the value
  did not change). Focus the slider and press ← three times: each press is its own step. Pinned: `SliderEditingTests` (the
  model). **Automated** (`InspectorSliderWindowTests`): a drag on the inspector's real slider is one "Change Width" undo
  step and two drags are two. **By hand:** a document parameter's slider, a click on the track without moving, and ←
  three times. **Observed:**
- [ ] **C10-5 Window gradient.** `swift run GraphPanelPreview`: the window behind the panels fades from a lighter blue-grey
  at the top to near-black at the bottom, smoothly, with no banding or seam at the panels' edges. In the app, the viewport
  behind the panels shows the same gradient. Pinned: `WindowBackgroundTests`. **Observed:**

## Group EP — editor polish: the floating palette and the node library

**Status: NOT RUN.** Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`).

Run `swift run MetalCreatorApp` (EP-1–EP-9, EP-11, EP-12) and `swift run GraphPanelPreview` (EP-10).

- [ ] **EP-1 The palette floats at the pointer.** Dock the graph at the bottom. With the pointer over the canvas,
  near its bottom-left, press Tab: the palette opens with its bottom-left corner at the pointer, reaching up over the
  viewport, every row and the search field visible, nothing clipped by the panel's edge. Escape. Move the pointer
  near the canvas's right end (under the inspector) and press Space: it opens to the pointer's left, fully visible,
  over the inspector. Dock left and press Tab near the canvas's top-left: its top-left corner is at the pointer. The
  graph panel never moves or resizes while it is open. The palette is MetalUI's `anchoredOverlay` (gap EP-b): at the
  window's edge it is flush with it (no margin). Resize the window with the palette open: it stays inside. Pinned:
  `PaletteOverlayWindowTests` (`itOpensWithItsTopLeftCornerAtThePointerWhateverTheViewportHasDrawn`, `itFlipsUpAtTheBottomEdgeAndOnlyThere`,
  `itFlipsLeftAtTheRightEdgeAndUpAtTheBottom`, `resizingTheWindowWhileOpenKeepsItInside`),
  `thePaletteIsPaintedOverEverythingWhereItWasPlaced`. **Observed:**
- [ ] **EP-2 The palette's keys and rows.** Open it with Space: ten rows show and the caption says how many more.
  Press ↓ twelve times: the rows scroll to keep the highlight in view; ↑ scrolls back. Type "ex": the rows narrow
  and the palette keeps its size and place. Type "f+": they go into the field (the viewport neither frames nor
  zooms). Press Return: the node is added where the pointer was when the palette opened (not at the palette's
  corner) and selected; ⌘Z removes it in one step. Pinned: `theRowsScrollToKeepTheHighlightInView`,
  `theNodeItAddsLandsAtThePressPoint`. **Automated** (`PaletteKeyRoutingWindowTests`): Space over the canvas opens
  the palette with the search field focused, "f+" go into the field (the viewport neither frames nor zooms), Return adds a
  node and selects it, ⌘Z removes it in one step, Esc closes the palette and adds nothing. **By hand:** the rows' scrolling
  and where the node lands. **Observed:**
- [ ] **EP-3 Closing the palette.** Open it, then click empty viewport: it closes (and the viewport takes the
  click). Open it, click a top-bar button: it closes. Open it, click the canvas: it closes. Open it, right-click or
  middle-click the canvas or the inspector: it closes. Open it and click its glass padding or caption: it stays open
  and nothing under it reacts. Open it over the inspector (near the window's right edge) and scroll over it: the
  inspector doesn't scroll. Open it and click into an inspector field, or right-click the canvas (its context menu
  opens): it closes, the field has the focus, the menu opens. Escape closes it. **Automated** (`PaletteOverlayWindowTests`:
  `aPressIntoATextFieldClosesItAndTheFieldGetsFocus`, `aRightClickThatOpensAContextMenuClosesItAndTheMenuStillOpens`,
  `theRightAndMiddleButtonsOutsideCloseItToo`, `aPressOnTheViewportClosesIt`, `aPressOnTheCanvasClosesItAndSelectsWhatItHit`,
  `aPressOnItsOwnGlassStaysOpenAndNothingBeneathReacts`, `escapeClosesItAndLeavesTheSelectionAlone`).
  **By hand:** the looks, and the scroll over the inspector. **Observed:**
- [ ] **EP-4 The library's place.** A new window shows the library, captioned "Nodes" above its "Search nodes" field:
  docked at the bottom, a column at the canvas's left edge; docked left, a strip across the canvas's top. It lists
  Value, Profile, Solid, Selection, Feature and Output, each under a header in that category's node-header colour, and
  scrolls when it doesn't fit. Press Library in the header: it goes and the canvas takes its room; press it again: it's
  back. Hide it, save, and reopen the file: it's still hidden, and the top bar never showed "— Edited" for it. Pinned:
  `LibraryViewTests`, `itIsShownByDefaultAndItsVisibilityIsSavedButNotAnEdit`. **Observed:**
- [ ] **EP-5 Click to add.** Pan and zoom the canvas, then click Extrude in the library: an Extrude appears in the
  middle of the visible canvas, selected. Click it a few more times: each lands near the middle, wholly in view, none
  overlapping, and once there's no free room in view the next lands in the middle anyway. ⌘Z removes them one by one.
  Click a row with a slight trackpad wobble: it still adds (no ghost appears). Pinned:
  `aClickAddsTheTypeCentredInTheVisibleCanvasAsOneStep`, `aClickedTypeIsNudgedOffTheNodesAlreadyThere`,
  `aClickedTypeStaysInViewWhenTheCentreIsCrowded`, `aClickThatMovesUnderTheThresholdStillAddsAtTheCentre`.
  **Observed:**
- [ ] **EP-6 Drag to add.** In both docks, drag Fillet from the library onto the canvas and let go: a Fillet lands
  with its top-left corner where you let go, selected; ⌘Z removes it. While dragging, a flat copy of the row follows
  the pointer (its top-left corner at the pointer), over the canvas, the viewport and the inspector, with no shadow.
  Drag a type and let go over the library itself, the viewport, the inspector, or outside the window: nothing is
  added and the ghost goes. Dragged out of the window it stays MetalUI's own drag (no system drag image, nothing in
  another app reacts). Pinned: `LibraryDragTests`, `aRowsGestureIsAZeroDistanceDragInWindowPoints`,
  `theDragGhostIsDrawnAtThePointerOnlyWhileDragging`, `aDraggedLibraryTypeIsPaintedOverTheWindow`; the gesture in a
  scrolling list is this check only. **Observed:**
- [ ] **EP-7 Hover help.** Rest the pointer on Extrude in the library: after about a second a tooltip reads "Extrude:
  profile, distance, mode, reversed → solid". Search "fil": only Selection ▸ Edge Filter and Feature ▸ Fillet stay (the
  palette's matches for "fil"); clear the field: everything is back. Pinned: `hoverHelpNamesInputsThenOutputs`,
  `theSearchIsThePalettes`. **Observed:**
- [ ] **EP-8 Themes.** View ▸ Theme ▸ Alucard: the library's background, headers and text, and the palette's glass,
  rows and caption, all take Alucard's colours at once; no glow or shadow anywhere. Pinned:
  `theLibraryRedrawsInTheChosenTheme`, `aSectionHeaderIsItsCategorysHeaderColour`, `theLibraryRasterizesNothing`.
  **Observed:**
- [ ] **EP-9 Still quick.** With the library shown, drag a node around the §7.2 bracket's graph, drag a library type
  across the window, and scroll the library: it feels as it did before the library (PERF-b still rebuilds the whole
  window; the library's `List` builds only the rows in view). **Observed:**
- [ ] **EP-10 The preview.** In `GraphPanelPreview` (its window keeps one size), EP-1's placement holds in both
  docks, and the library works as in EP-4–EP-7 with the preview's nine node types. **Observed:**
- [ ] **EP-11 Nodes go under the library.** Dock the graph left with the library shown and type "out" in its
  search field. Pan the canvas so a node slides up under the library strip: the node disappears at the canvas's top
  edge and the strip's search field, headers and rows stay whole on top of it. Dock at the bottom and pan a node left
  under the library column: the same at the canvas's left edge. Hide the library and pan a node up past the panel's
  header: it disappears at the canvas's edge, never over the header or the glass padding (gap LF-a, fixed in MetalUI
  0b400b4). Pan the canvas right and down by more than a node's size, then drag a node to the canvas's top-left
  corner, wholly inside it: it draws whole, header and body, not only a slice at its right or bottom (gap LF-b, fixed
  in MetalUI 9ad2254). Pinned: `aNodeUnderTheLibraryStripIsHiddenByIt`,
  `aNodeUnderTheLibraryColumnIsHiddenByIt`, `aNodeAboveTheCanvasNeverCoversTheHeader`,
  `aNodeAtANegativeCanvasPositionDrawsWhole`. **Observed:**
- [ ] **EP-12 The header at the minimum width.** Drag the dock's edge to its narrowest (240 points) with the library
  shown: the 28 pt header's title, Library button and the dock and hide buttons do not overlap or get cut off, and each
  can still be pressed. **Record what gives way first** (the title, or a button). Pinned: `GraphPanelLayout`'s header
  height only; the crowding itself is this check only. **Observed:**

## Group P — the packaged app (packaging)

**Status: NOT RUN.** Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`).

Run `scripts/package-app.sh` first; it ends with `==> Wrote …/dist/MetalCreator.app`. How-to: `docs/packaging.md`.

- [ ] **P1 Finder launch, moved.** Copy `dist/MetalCreator.app` to `~/Applications` in Finder and double-click it
  there. The window opens in Dracula, as with `swift run MetalCreatorApp`. Wire a Rectangle into an Extrude and the
  Extrude into an Output, then File ▸ Export STEP…: the file is written and opens in a STEP viewer
  (FreeCAD or any other; without one, `head -c 12` on it prints `ISO-10303-21`). In Activity Monitor,
  select MetalCreator ▸ ⓘ ▸ Open Files and Ports: no path starts with `/opt/homebrew`. Pinned headless:
  `scripts/verify-app.sh` (the self-test with Homebrew unreadable) and `SelfTestTests`. **Observed:**
- [ ] **P2 The document type.** Save a graph as `test.mcgraph` and choose File ▸ Get Info on it in Finder: Kind reads
  "MetalCreator Graph" and "Open with" names MetalCreator. Double-click it: MetalCreator opens and shows that graph
  (MetalUI C8 delivers the file; checks AS-6 and AS-7 cover the double-click and the Dock drop in depth). Pinned:
  `AppBundleInfoTests.itOwnsAndExportsTheMcgraphType`, `itNeedsNoDocumentClassAndDeclaresNoURLScheme`. **Observed:**
- [ ] **P3 Another Mac (optional).** On a second Apple-silicon Mac with macOS 27 and no Homebrew, unzip a copy made
  with `ditto -c -k --keepParent dist/MetalCreator.app MetalCreator.zip`. Gatekeeper refuses the ad-hoc app at first;
  Control-click ▸ Open (or System Settings ▸ Privacy & Security ▸ Open Anyway) opens it, and P1's export works.
  **Observed:**
- [ ] **P4 Developer ID (optional, needs your identity).**
  `METALCREATOR_SIGN_IDENTITY="Developer ID Application: …" scripts/package-app.sh` passes; `codesign -dv
  dist/MetalCreator.app` shows your TeamIdentifier and `flags=0x10000(runtime)`, and the verify step says dyld printed
  no load list. Then notarize by hand (`docs/packaging.md`): `spctl --assess --type execute --verbose
  dist/MetalCreator.app` reads "accepted, source=Notarized Developer ID". **Observed:**

## Group AS — the app shell on MetalUI C8

**Status: NOT RUN.** Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`, its AS1–AS10).

Run `swift run MetalCreatorApp` for AS-1 to AS-5 and AS-8 to AS-10, and `scripts/package-app.sh` first for AS-6 and AS-7. The
model's side of each check is pinned headless (`AppModelCloseTests`, `WindowChromeTests`, `AppModelOpenURLTests`,
`TitleBarClearanceTests`, `TopBarClearanceRenderTests`, `TitleBarClearanceWindowTests`, `WindowDragWindowTests`,
`SketchWindowDragWindowTests`, `SaveChangesAnswerTests`); what MetalUI's window, menu and
Finder do with it is these checks only (gap M6-e is adopted: `TestWindow.requestClose()` and `presentedAlert` could drive
the window half; no test does yet). The window drag is pinned only as far as the platform being asked
(`TestWindow.windowDrags`, MetalUI C22's `performWindowDrag`); that AppKit then moves the window is AS-5.

Product decisions behind these checks (the user approved the recommended default of each on 2026-10-09/10): (1) the
hidden title bar ships with MetalUI C22's window drag (amended 2026-10-12 by the C22 plan `2026-10-12-adopt-c22`, User
decision 3, approved by the user: merged before AS-5) and stays only if AS-5 shows the window drags; if it doesn't, the
one `windowStyle` line (that plan's Task 3 commit) is reverted alone; (2)
a Finder open of the file already open does nothing; (3) a typed but uncommitted inspector value counts as a change when
a Finder open arrives; (4) the top bar keeps the name and "— Edited"; (5) close and quit share one alert; (6) an open
onto edited work asks "Discard unsaved changes?". Gap C8-a was reported to the MetalUI session on 2026-10-10 and is fixed by C22.
The window drag's own decisions (which regions drag, whether a double click zooms) are in the C22 plan's "User decisions"
and are recorded here once the user has answered them: the written default is the top bar's empty space and the strip above it,
and a double click does nothing.

- [ ] **AS-1 Close with unsaved changes.** In an empty window add a node, then press the close button. A sheet asks "Do
  you want to save the changes to “Untitled”?" with Save, Don't Save and Cancel; Return is Save, Esc is Cancel. Cancel:
  the window stays, the change is still there, and pressing ⌘W asks again. Save: the save panel opens (Untitled.mcgraph);
  cancelling that panel keeps the window; choosing a folder saves and closes the window and the app ends. Reopen,
  change a value, close, Don't Save: the app ends and the file on disk is unchanged. Make the file read-only on disk,
  change a value, close, Save: an alert says the save failed and the window stays. Press the close button twice
  quickly: one sheet. With nothing changed (or right after a save) the window closes at once. Type 75 into a number
  field without pressing Return, then close: the sheet appears. **Observed:**
- [ ] **AS-2 Quit with unsaved changes.** Change a value, then press ⌘Q (and, separately, Dock icon ▸ Quit and the
  MetalCreator menu ▸ Quit): the same sheet. Cancel keeps the app; Don't Save quits; Save writes the file, then quits.
  While the sheet is up, ⌘Q and ⌘W open no second sheet. With no changes ⌘Q quits at once. **Observed:**
- [ ] **AS-3 Title and edited dot.** The Window menu and Mission Control name the window "Untitled", then the file's
  name after a save or an open. The close button shows AppKit's edited dot after a change and loses it after a save or
  an undo back to the saved state; New resets the name. The top bar still reads the name and "— Edited". **Observed:**
- [ ] **AS-4 Proxy icon.** Spec §6.1's window shows the document's file in the title bar. The title bar is hidden now (plan
  `2026-10-12-adopt-c22`): record whether AppKit draws the title or the proxy icon at all (expected: neither, and the Window
  menu still names the document, `representedURL` is still set; the top bar names it). **Observed:**
- [ ] **AS-5 The top bar under the window buttons, and dragging the window by it.** (The live test of the hidden title bar,
  gap M6-c, and of MetalUI C22's `WindowDragGesture`, gap C8-a: `windowStyle: AppLayout.windowStyle` in
  `Sources/MetalCreatorApp/main.swift`. MetalUI's own WD1–WD7 ask the same of its demo.) The three window buttons sit over the
  glass top bar's left end, the document name starts clear of them (8 pt past the zoom button), and nothing overlaps at the
  minimum window width (1000 × 640). Enter a sketch (Edit sketch on a Sketch node): the toolbar starts clear of the buttons too.
  Enter full screen (⌃⌘F): the buttons leave and the content moves back to the bar's left edge; leave full screen and it clears
  them again. **Drag the window by the gap between the name and the Preview picker, by the document's name, and by the strip
  above the bar (also in the row beside and between the window buttons): the window moves with the pointer from the first few
  points, follows it all the way and stays where it is dropped.** Press and release in the gap without moving: nothing moves
  and the viewport is not clicked. Right-click the gap: the window doesn't move. Double-click the gap and the strip: record
  whether the window zooms (expected: no). Drag the window with a model in the viewport: the camera doesn't move. Pinned
  headless, up to the platform being asked to move the window: `WindowDragWindowTests`, `SketchWindowDragWindowTests`,
  `TitleBarClearanceWindowTests`. **Observed:**
- [ ] **AS-6 Finder double-click (packaged app).** Copy `dist/MetalCreator.app` to `~/Applications`. Double-click a saved
  `.mcgraph` in Finder: MetalCreator launches and shows that graph, with no "cannot open files" alert. With the app
  running and unchanged, double-click another `.mcgraph`: it replaces the document. After a change, double-click
  another: the "Discard unsaved changes?" question appears; Cancel keeps the document, Discard Changes opens the file.
  Double-click the file that is already open, changed or not: nothing happens (it is not reloaded). Type a value into
  an inspector field without pressing Return, then double-click another file: the question appears. (MetalUI has not
  measured Finder either: its AS9.) **Observed:**
- [ ] **AS-7 Dock drop, `open`, and the command line.** Drag a `.mcgraph` onto the Dock icon, running and not running:
  it opens. Drag two files at once: the last one stays open. `open -a ~/Applications/MetalCreator.app file.mcgraph`
  opens it. `swift run MetalCreatorApp file.mcgraph` and `swift run MetalCreatorApp relative/path/file.mcgraph` (from another
  directory than the file's) open it once (not twice), and a path that doesn't exist shows an alert. **Observed:**
- [ ] **AS-8 Controls stay controls under the drag.** Click Undo, Redo, the Preview picker and Export: each works, and the window
  doesn't move. Press on each of them and drag 40 points away: the window doesn't move (record what the control does). Press
  in the glass's padding just below the buttons, or in a gap between two buttons, and drag: the viewport orbits and the window
  doesn't move (by design these places are not handles: User decision 1). Start a drag just under the bar, on the viewport: it orbits as before.
  Pinned: `aPressDragOnABarControlNeverAsks`, `thePaddingBelowTheControlsIsNotAHandle`, `aDragBelowTheBarStillOrbitsTheViewportAndDoesNotAsk`.
  **Observed:**
- [ ] **AS-9 The sketch toolbar drags too.** In a sketch, drag the window by the "Sketch" label, by the gap before Finish and by
  the strip above the bar, over its whole 22 points (the top 12 are the margin, the lower 10 lie over the toolbar's glass, whose backdrop has a
  drag gesture of its own; the strip is drawn above it): it moves. Press and drag from a tool button, Construction, Delete and Finish: it doesn't. Make the
  window its smallest (1000 wide): record how small the gap before Finish gets (the strip still drags). Pinned:
  `SketchWindowDragWindowTests`. **Observed:**
- [ ] **AS-10 The edges of a drag.** Drag the window by the bar and release outside the window, over the Dock and over the menu bar:
  the window ends where you let go, and the pointer, hover highlights and cursors are normal at once; a click and a drag in the
  viewport work on the next try. Switch away with ⌘-Tab mid-drag and back: nothing is stuck. Drag across to a second display, if
  there is one. In full screen drag the strip: nothing moves and nothing breaks (MetalUI's WD6). Drag, then undo a change from the
  Undo button: the document and the window are fine. **Observed:**

## Group S4 — the Sketch and Plane from Face nodes (S4)

**Status: NOT RUN.** S4 adds no views; this checks that the two new nodes reach the running app.

Run `swift run MetalCreatorApp`, with the preview mode set to Selected node.

- [ ] **S4-1 The new nodes in the palette.** Open the add-node palette over the canvas and search "sketch", then
  "face": Sketch and Plane from Face are listed. Add both. Sketch draws with inputs `plane` and `references` and
  outputs `profiles` and `measurements`; select it: its badge is a warning, "Draw a closed shape in the sketch to make
  a profile.", and the viewport shows nothing. Plane from Face draws with input `solid` and output `plane`; select it:
  its badge is an error until a solid is wired. Wire an Extrude's solid into it and select it again: the error reads
  "Pick a face for this plane to sit on." Nothing crashes, Undo removes each node, and Save then Open keeps both.
  Known (S5): exposed-dimension sockets aren't drawn, and neither node has inspector controls of its own. Pinned:
  `theBuiltInsAreTheSliceAndTheSketcherNodesInSixCategories`, `aNewSketchHoldsAnEmptySketchOnXYAndAsksForAShape`,
  `aMissingUnreadableOrStalePickIsAPlainError`, `aSketchSettingRoundTripsThroughAFile`. **Observed:**

## Group TH — themes: custom themes, `.mctheme` files and the theme editor

**Status: NOT RUN.** Run `swift run MetalCreatorApp`. Your own themes are saved in
`~/Library/Application Support/MetalCreator/Themes`; move that folder aside first to start clean, and back afterwards.

- [ ] **TH-1 The editor.** View ▸ Theme lists Dracula, Alucard and Nord, then Edit Themes…. Choose it: a glass panel
  opens at the top right below the top bar, over the inspector, as tall as the window allows, and lists every role
  under its group with its hex and a colour well; it scrolls. Dracula's name field and Dark controls toggle are disabled and
  a line says built-ins are read-only. Drag or scroll on the panel: the viewport neither orbits nor zooms. Done (or
  Escape) closes it. Dock the graph at the bottom (Bottom) and open the editor again: it ends a margin above the graph
  panel, which stays whole; drag the panel's top edge up and down: the editor follows. On the Chamfer, press "Pick
  edges in view…", then open the editor: the first Escape cancels the pick (the banner's Cancel runs first) and the
  editor stays open; a second Escape closes it. Pinned:
  `theEditorFloatsAtTheTopRightBelowTheTopBarAndFillsTheHeight`, `theEditorStopsAboveAGraphPanelDockedAtTheBottom`.
  **Observed:**
- [ ] **TH-2 Duplicate, rename, dark.** Duplicate: "Dracula Copy" is shown and View ▸ Theme lists it after a divider.
  Type "Midnight" in the name field (F, + and − type, the viewport doesn't frame or zoom) and press Return: the
  editor's menu and View ▸ Theme say "Midnight". Type "nord" and press Return: "There’s already a theme called “nord”."
  and the field shows "Midnight" again. Turn Dark controls off: the window and its buttons turn light. Pinned:
  `ThemeEditorModelTests`. **Observed:**
- [ ] **TH-3 Colours.** Click a role's colour well: MetalUI's colour panel opens. Drag in
  its square: the role's colour changes as you drag, on the panels and in the viewport (try Selection, Solid nodes,
  Shading). Glass, Glass hairline and Edges offer opacity, others don't. With VoiceOver on, move to a role's well: it
  reads the role's name (e.g. "Selection"), then "colour well" and its value. Quit and relaunch: Midnight is shown,
  with your colours. Pinned: `theColourBindingReadsAndWritesTheRole`, `manyQuickEditsKeepTheLastColour`. **Observed:**
- [ ] **TH-4 Export and import.** Export… offers "Midnight.mctheme"; save it to the Desktop and open it in a text
  editor: small JSON, every role as `#rrggbb`. Change `"selection"` to `"pink"` and save as `bad.mctheme`; Import…
  it: "“bad.mctheme” couldn’t be imported. ‘selection’ isn’t a colour like #ff79c6." Import `Midnight.mctheme`:
  "Midnight 2" is shown. Pinned: `ThemeImportExportTests`. **Observed:**
- [ ] **TH-5 Delete and launch.** Delete… asks first; Cancel keeps it, Delete removes it and Dracula is shown. With
  two custom themes, press Delete… on one, choose the other from View ▸ Theme, then press Delete: the first is
  removed, the one shown stays. Choose Nord, quit and relaunch: Nord is shown. Put a file named `junk.mctheme`
  containing "nope" in the themes folder and relaunch: the app starts, and Edit Themes… says “junk.mctheme” was
  skipped and why. Pinned: `aDeleteConfirmationStaysWithItsTheme`, `filesThatCantBeReadAreReported`,
  `theRememberedCustomThemeIsShownAtLaunchAndAGoneOneFallsBackToDracula`. **Observed:**
- [ ] **TH-6 MetalUI's controls follow the theme.** In each built-in and in a custom theme, the top bar's buttons, the
  Preview and Export menus, the inspector's fields and sliders, and the editor's own controls are drawn in the theme's
  colours (Dracula: node-body grey buttons, purple accent), not MetalUI's blue defaults. Pinned:
  `metalUIsControlsTakeTheThemesTokens`. **Observed:**

## Group S5 — the sketch editor in the viewport (S5a)

**Status: NOT RUN.** Run `swift run MetalCreatorApp`. Add a Sketch, wire its `profiles` into an Extrude (10 mm) and
that into an Output. Select the Sketch.

- [ ] **S5-1 Entering.** The inspector shows "Edit sketch". Press it: the camera turns to look straight down at XY,
  orthographic; the ground grid gives way to a grid on the sketch plane; the top bar shows the sketch toolbar (Sketch,
  Select, Line, Arc, Circle, Point, Dimension, Construction, Delete, Finish) and the inspector "Nothing drawn yet. Pick
  Line (L), Arc (A) or Circle (C).", the CONSTRAIN buttons (all dimmed), DIMENSIONS and CONSTRAINTS. The pointer is a
  crosshair. **Observed:**
- [ ] **S5-2 Drawing a rectangle.** Press L and click four corners, then click the first corner again: each line is
  cyan while it can move; the rubber band follows the pointer; a near-horizontal or near-vertical line snaps and the
  readout drops. The last click closes the loop on the first point. Press Esc: the chain ends. The Extrude shows a
  ghosted box under the sketch. **Observed:**
- [ ] **S5-3 Inference and ⌘.** Draw a nearly horizontal line holding ⌘: it doesn't snap (gap S5-a is adopted; C16-2 checks the
  still-pointer half). **Observed:**
- [ ] **S5-4 Constraints and dimensions.** Choose Select, click two lines (both turn green); the inspector's
  Perpendicular, Parallel and Equal buttons are enabled, the rest dimmed with a tooltip saying what to select. Press D,
  click the bottom line, then empty space: "Length d1" appears with its value. Type 80 in its value field and press
  Return: the rectangle and the extrusion follow. Add dimensions until the readout says "Fully constrained": the lines
  turn the foreground colour. Add a conflicting constraint: the readout and the conflicting rows turn red, and Remove
  on the extra one fixes it. **Observed:**
- [ ] **S5-5 Dragging.** With Select, drag a free corner: the sketch follows live and stays constrained; the extrusion
  updates once, on release; one ⌘Z undoes the whole drag. A drag on empty space pans (S5-9); right-drag and middle-drag
  pan, scroll zooms. **Observed:**
- [ ] **S5-6 Exposing.** Turn on "Expose as input" for d1, then Finish (⏎): the Sketch node on the canvas shows a `d1`
  input with "80 mm". Wire a Number into it: the part follows the Number. Edit sketch again, rename d1 to `width`: the
  wire moves to `width`. Renaming it `plane` is refused in words. **Observed:**
- [ ] **S5-7 Keys stay where they belong.** While sketching, click into a dimension's name field and type "lad":
  the letters go into the field, the tool doesn't change. Click the Sketch node on the graph canvas (it is the graph's
  selection) and press ⌫, then fn-⌫ (or ⌦ on an extended keyboard), with nothing selected in the sketch: no graph node
  is deleted and sketch mode stays. Select a line and press fn-⌫: the line is deleted. Press Esc twice with nothing in
  progress: sketch mode ends and the top bar comes back. **Observed:**
- [ ] **S5-8 The chrome is not the sketch.** With Line active, click in the gaps between the toolbar's buttons, on
  the inspector's "DIMENSIONS" label and on its readout, and scroll over both: nothing is drawn, no rubber band
  follows the pointer under the panels, and the view doesn't zoom. Choose Select, select a line and click a gap in the
  toolbar: the selection stays. Right-click a ghosted face: no menu opens (Look At would turn the camera, S5-9).
  **Observed:**
- [ ] **S5-9 The camera stays on the sketch plane.** While sketching: the view cube, its ◀ ▲ ▼ ▶ ⌂ buttons and its
  View menu are gone. Drag on empty space (any tool), right-drag and middle-drag: each pans, the view never turns.
  Scroll and pinch zoom toward the pointer. A click where the cube was draws there. With Select, a drag on a point
  still moves the point. Pan away and press F: the sketch is framed again, still face-on (a lone circle away from the
  origin is framed whole). Press Edit sketch and scroll at once, during the turn: the view still ends face-on. In a new
  document (Sketch → Extrude → Output), edit the sketch and draw a closed rectangle: the extrusion appears and the
  camera stays face-on. Finish (⏎): the cube and its controls are back, the camera hasn't moved, and a drag on empty
  space orbits again. **Observed:**
- [ ] **S5-10 The pointer readout.** Press L and click once: a small glass chip (no shadow) sits centred just above
  the pointer and reads the line's length and angle, e.g. "24.5 mm · 30.0°" (counter-clockwise from the sketch's +x,
  0 to under 360°); near-horizontal, it reads the snapped values ("… · 0.0°"). Move the pointer just under the top
  bar: the chip flips below the pointer, never under the bar's glass; next to the graph panel or the inspector: it
  stays inside the uncovered area, never under them. Middle-drag and scroll with a line in progress: the chip and the
  rubber band follow the pointer. Esc, the second click of a circle, leaving the view, or moving onto the toolbar or
  inspector: the chip goes. Circle after the centre: "⌀ 20.0 mm". Arc: "R 12.0 mm" after the centre, then
  "R 12.0 mm · 90.0°" after the start; nearly a full turn reads "360.0°". Point: the pointer's position, "12.0, 8.5"
  (over an existing point, that point's position, though a click there adds nothing). Select and Dimension: none.
  Finish: none. Select, then drag the free end of a lone line: the chip follows the pointer and reads the line's length
  and angle as solved (a dimensioned line keeps its length however far you drag); an arc's start or end: "R … mm · …°";
  a rectangle's corner, a circle's centre or a free point: its position. Release: the chip goes. **Observed:**

## Group S5b — the sketch editor's tools and inference (S5b)

**Status: NOT RUN.** Run `swift run MetalCreatorApp`. Add a Sketch, wire its `profiles` into an Extrude (10 mm) and
that into an Output, select the Sketch and press "Edit sketch".

- [ ] **S5b-1 Trim and Extend.** Draw two crossing lines. Press T and click one line's end beyond the crossing: that
  span goes, one ⌘Z brings it back. Choose Extend and click near the free end of a short line that points at another
  line: it grows to meet it. Extend a line that meets nothing: the inspector says "There is nothing to extend Line 1
  to." and nothing changes. Pinned headless by `ModifyToolTests`. **Observed:**
- [ ] **S5b-2 Fillet.** Draw a rectangle, choose Fillet: the inspector shows "Click a corner where two lines meet."
  and Radius "5 mm". Click a corner: it rounds, with a radius dimension. Type 500 in Radius and click another corner:
  "Radius 500 mm is too large for this corner (max ≈ …)." and nothing changes. F still frames the sketch. Pinned by
  `FilletToolTests`. **Observed:**
- [ ] **S5b-3 Mirror.** Draw a construction line (X) and a shape beside it. With Select, click the shape's lines,
  choose Mirror and click the construction line: a mirrored copy appears; drag an original corner: its copy follows,
  mirrored. With nothing selected, Mirror says "Select the geometry to mirror first." Pinned by `MirrorToolTests`.
  **Observed:**
- [ ] **S5b-4 Pattern.** Draw a small circle and a point beside it; select the circle, choose Pattern, set Instances
  to 6 and click the point: six circles around it. With Select, select one circle, choose Pattern again and click a line: copies along it,
  Spacing apart (type 15).
  Instances "1" is refused in words. Pinned by `PatternToolTests`. **Observed:**
- [ ] **S5b-5 3-point arcs.** Press A twice: "3-Point Arc ✓". Click a start, an end, then move the pointer: the arc
  bends through it, the readout shows the chord, then "R … mm · …°"; click: the arc is drawn. A third click in line
  with the ends draws nothing. Press A again: back to the centre arc. Pinned by `ThreePointArcTests`. **Observed:**
- [ ] **S5b-6 Inference and glyphs.** With Line, move over an existing line: the rubber band's point jumps onto it and
  a green "Point on" chip sits below right of the pointer; click there and drag the line away with Select: the point
  stays on it. Over a point: "Coincident". From an arc's end, draw along its tangent: "Tangent", and the line stays
  tangent when the arc is dragged. Near the right or bottom of the view, the chip moves left or up. Pinned by
  `InferenceTests`, `InferenceGlyphTests`. **Observed:**
- [ ] **S5b-7 Double-click to edit.** Finish the sketch. Double-click the Sketch node on the graph canvas: sketch mode
  opens as with "Edit sketch". Two clicks too slow for the system's double-click speed, or a double click on another node, only
  select. While sketching, draw a line's first point and double-click the Sketch node: nothing changes (the line in
  progress, the selection and the view stay). The system's double-click speed decides (gap S5-b is adopted; C16-3 checks
  it). Pinned by `DoubleClickTests`, `SketchDoubleClickTests`, `CanvasDoubleClickWindowTests`.
  **Observed:**
- [ ] **S5b-8 The toolbar fits.** At the default window size, every tool (Select … Pattern), Construction, Delete and
  Finish are visible in the top bar, none clipped. Not pinned (a toolbar's width against the window's is measured only
  by eye). **Observed:**

## Group M7 — measure and record: canvas culling, resizing, smoothness

**Status: NOT RUN.** Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`).

The canvas builds only the nodes and wires that can show (`EditorModel.drawnNodes`, a margin of
`EditorModel.cullingMargin` points past every edge), and the numbers in `docs/verification/performance.md` are
headless cold frames with no display link. These checks are what only the real window can show. Run
`swift run -c release MetalCreatorApp` (release: a debug MetalUI draws about 45× slower, gap PERF-a) and build a graph
of about 50 nodes, like the benchmark's (`FiftyNodeGraph`): a row of Rectangle → Extrude → All Edges → Fillet → Output,
wired, then copied and pasted until there are ten rows, spread out so the graph is several canvases wide and tall.
Save it; M7-1 to M7-4 use it, and M7-4 also the §7.2 bracket.

- [ ] **M7-1 Panning and zooming, both docks.** Docked left, pan quickly in circles with a two-finger scroll, then scroll
  with ⌘ to zoom all the way out and back in, quickly, several times; then dock at the bottom and repeat. No node or
  wire pops in late, flickers or is missing at the canvas's edges, and a wire between two nodes both out of view
  still crosses the view where it should. Zooming out past half size, the nodes' rows go and come back at the same
  zoom; headers, titles, sockets and wires stay, and clicking a node or dragging a wire between sockets still works
  there. Pinned: `CanvasCullingTests` (`nodesWhollyOutsideTheDrawnRectAreNotDrawn`,
  `aWireCrossingTheViewWithBothEndsOutsideIsDrawn`, `theNodesInViewStillPaint`, `aZoomedOutNodeDrawsWithoutItsRows`).
  **Observed:**
- [ ] **M7-2 A refused wire at the edge.** Pan so that a node straddles the canvas's right edge (then its bottom
  edge). Drag a wire from an incompatible socket onto it: it shakes, whole where it shows, with nothing cut off or
  missing, and settles back. Pinned: `theNodesInViewStillPaint`. **Observed:**
- [ ] **M7-3 Resizing.** Dock left with nodes below the window's bottom edge (pan up until some rows are just out of
  view). Enter full screen (⌃⌘F, or the green button): the nodes the taller panel uncovers appear at once, without
  moving the pointer. Leave full screen, then click the green button's Zoom (⌥-click) and drag the window's corner
  quickly larger and smaller; dock at the bottom and widen the window past nodes off its right end. Every uncovered
  node and wire appears; none stays missing until the next pan. Pinned: `aGrownWindowRebuildsTheCanvasWithWhatItUncovers`,
  `aNewSizeReachesObserversOneTaskAfterTheDraw`, `aBiggerWindowDrawsMore`. **Observed:**
- [ ] **M7-4 Smoothness.** Pan the 50-node graph (zoom 1) and orbit the bracket with the panel shown: both feel
  smooth, no stutter. Zoomed all the way out, panning may hitch (PERF-b, recorded in performance.md): note whether
  it does. Optionally confirm with Instruments' Animation Hitches or Core Animation FPS template, attached to the
  release app, and write the frame rate here. **Observed:**

## Group MS — multi-select (sub-project A)

**Status: PENDING.** Plan `2026-10-09-multi-select.md`, spec `2026-10-09-selection-groups-comments-design.md` §3 and
its Errata (A: multi-select). The tests pin the model; these check the gestures and keys through a real window (gap
M6-e is adopted: the graph's keys and the Edit chords are driven in groups CT and M6, the gestures not yet). Run `swift run MetalCreatorApp` on a saved bracket, docked left, then MS-8 docked
at the bottom too.

- [ ] **MS-1 Clicks.** Click a node, then ⌘-click two more: all three are selected; ⌘-click one of them again: it
  alone is deselected. ⇧-click a selected node: it stays selected. Click one of several selected nodes: only it stays
  selected. ⌘-click and ⇧-click empty canvas: nothing changes; a plain click there clears. Pinned:
  `MultiSelectPointerTests`. **Observed:**
- [ ] **MS-2 Drags.** Select three nodes, then drag one of them: all three move, and one ⌘Z puts them back. ⌘-drag a
  selected node: all move and all stay selected. ⇧- or ⌘-drag an unselected node: it joins and everything moves. ⌥-drag
  one of the three: three ghosts follow and three copies land, selected, as one undo step; ⌥-click without moving:
  nothing is copied. Pinned: `commandDragMovesTheSelectionAndKeepsIt`, `aModifiedDragOnAnUnselectedNodeAddsItAndMovesEverything`,
  `optionDragCopiesTheWholeSelectionOnlyOnceItMoves`. **Observed:**
- [ ] **MS-3 Box select and pan** (the user's Gate G answer (b), 2026-10-09). Select a node, then drag on empty
  canvas over two others: a box selects exactly those two (the first is dropped) and the canvas doesn't move; a plain
  drag over nothing clears the selection. ⇧-drag a box over two unselected nodes: they join the selection. ⌘-drag a
  box over one selected and one unselected node: they swap. Start a ⇧-box and let go of ⇧ just before the button: the
  box still adds (nothing selected before is lost). Grow a ⌘-box over a node, then shrink it away: the node is as it
  was. Middle-drag from empty canvas, then from a node: the canvas pans with a closed hand, nothing is selected or
  moved, and the viewport behind the panel doesn't move; two-finger scroll pans too. Hold the middle button, click a
  node, keep moving: the pan stops and doesn't jump. Pinned: `BoxSelectModeTests`, `MiddlePanTests`. **Observed:**
- [ ] **MS-4 ⌘A and Esc.** Click the canvas, ⌘A: every node is selected. Click into an inspector number field, ⌘A:
  the field's text is selected and the canvas selection doesn't change; the same in the open palette's search field.
  Esc with the palette open closes it and keeps the selection; Esc again clears the selection. Start dragging a wire
  and press Esc with the button still held: the wire vanishes, and releasing over a socket connects nothing (record
  whether the Esc arrives during the drag at all). ⌥-drag ghosts then Esc: they vanish. ⇧-box then Esc: the selection
  is as before the box. With Pick edges in view under way, Esc cancels the pick and keeps the selection. Drag a node
  and, with the button still held, press ⌘A and → : nothing changes, and after the release one ⌘Z puts the node back.
  Pinned: `SelectionKeyTests`, `aNudgeDuringAMoveKeepsItOneUndoStep`. **Observed:**
- [ ] **MS-5 Arrows.** Select two nodes, click empty canvas with ⇧ (so no field has focus), press → three times:
  they move 3 points right, and ⌘Z three times puts them back step by step. Hold ⇧→ for a second: they glide right
  10 points per repeat, and one ⌘Z undoes the whole hold. Docked left, ↓ moves them down the screen. In a focused
  inspector field the arrows move the caret instead. Pinned: `NudgeTests`. **Observed:**
- [ ] **MS-6 F.** Select a node far off screen, put the pointer over the graph canvas and press F: the canvas pans and
  zooms so it is centred with a margin. With nothing selected, F frames every node. With the pointer over the
  viewport, F frames the part as before; in a focused inspector field F types. Pinned: `FramingTests`,
  `AppInputTests.fFramesTheGraphOverItsCanvasAndTheViewportElsewhere`. **Observed:**
- [ ] **MS-7 Panel hidden.** Hide the panel (Tab with the pointer off the canvas), then ⌘A and Delete: no node is
  deleted (show the panel to check); arrows move nothing. Pinned: `selectAllDoesNothingWhileThePanelIsHidden`,
  `withNothingSelectedOrThePanelHiddenTheKeyGoesOn`. **Observed:**
- [ ] **MS-8 Draw order.** Overlap three nodes, select the two at the back: they draw above the third, and a click
  where all three overlap selects the topmost drawn one. Docked at the bottom too. Pinned:
  `selectedNodesDrawLastAndAreHitFirst`. **Observed:**

## Group NF — naming: face picks on merged faces

**Status: NOT RUN.** Plan `2026-10-09-naming-face-picks.md`. The tests pin the behaviour; this checks that the two new
warnings read well where they appear.

- [ ] **NF-1 The two warnings.** Trigger both in `swift run MetalCreatorApp` and read each in the node's status badge
  and in the inspector: they wrap, aren't cut off, and say what to do. (1) Plane from Face's merged-pick warning:
  a Plane from Face on a face a union merged (S5c's New sketch on face, once it lands; before that, a document saved
  by a test, since the app can't pick a face yet), then unmerge it so the choice is a guess (a pick made before
  positions were recorded). (2) Edges by Tag's ambiguous-pick warning: a hole rim picked on a merged side, then a
  change after which two parts each have a rim. Record which of the two you could reach (the second needs both operands to have a rim after an edit; if you can't
  get there, write that, the tests pin both). Pinned:
  `aPlanePickWithoutAPositionWarnsOnceTheFaceHasComeApart`, `aGuessBetweenOperandsIsReportedNotSilent`.
  **Observed:**

## Group CM — canvas comments (sub-project B)

**Status: PENDING.** Plan `2026-10-09-comments.md`, spec `2026-10-09-selection-groups-comments-design.md` §7 and its
Errata (B: comments). The tests pin the model and the headless frames; these check the gestures, keys, menu and the
inspector's text field through a real window (gap M6-e is adopted: the typing, the note box and the Undo are driven in group
CT, the rest not yet). Run `swift run MetalCreatorApp`
on a saved bracket, docked at the bottom; CM-9 docks left.

- [ ] **CM-1 Add Note.** Put the pointer over the canvas and press ⌘⇧N: a muted 160 × 100 note reading "Note"
  appears with its top-left under the pointer and is selected (ringed, with a small square handle at its bottom-right
  corner). ⌘Z removes it, ⇧⌘Z brings it back. Right-click empty canvas: the menu offers Add Note and Frame Selection
  (greyed with nothing selected); Add Note puts a note where you clicked. Pinned: `CommentCreationTests`. **Observed:**
- [ ] **CM-2 Frame Selection.** Select two or three nodes and press ⌘⇧C (and again from the right-click menu): a
  muted frame titled "Frame" appears around them, 24 points clear of the nodes on every side with a title bar above,
  and is the only thing selected. With nothing selected ⌘⇧C does nothing and the menu item is greyed. ⌘C alone still
  copies. Pinned: `frameSelectionPadsTheBoundsAndAddsATitleBarAndSelectsTheFrame`,
  `frameSelectionIsDisabledWithNothingSelected`. **Observed:**
- [ ] **CM-3 Draw order and hits.** Make a frame around two wired nodes with a note overlapping one of them. The frame
  is behind the wires, the wires are behind the note, the note is behind the nodes. Click a node inside the frame: the
  node is selected. Press on empty space inside the frame and drag: a box starts (the frame is not grabbed). Press on
  its title bar or its 6-point inner edge: the frame is grabbed. A press anywhere on the note grabs it. Overlap two
  notes and select the lower one: it comes to the front. Pinned: `CommentHitTests`, `CommentRenderTests`.
  **Observed:**
- [ ] **CM-4 Frames carry their nodes.** Drag the frame by its title bar: the frame and the nodes whose centres were
  inside move together and one ⌘Z puts them all back. Drag one node out past the frame's edge: it is no longer
  carried. Drag a frame over other nodes: only the nodes it held when the drag began come along. Select a frame and
  press → : it nudges with its nodes. Delete the frame: the nodes stay. ⌥-drag a frame: a copy lands without the
  nodes. Pinned: `CommentMoveTests`, `CommentEditingTests`. **Observed:**
- [ ] **CM-5 Resize.** Select a note: drag its bottom-right handle: the top-left stays put and the size follows the
  pointer; it stops at 80 × 40. The same for a frame, whose nodes stay where they are. One ⌘Z undoes the whole drag.
  An unselected note's corner grabs the note instead. Zoom out to 25%: **record whether the 12-canvas-point handle
  (3 screen points) can still be grabbed** (User decision 12). Pinned: `CommentResizeTests`. **Observed:**
- [ ] **CM-6 Selection and clipboard.** Box-select over a note and a node: both are selected. A box drawn wholly
  inside a frame, among its nodes, selects the nodes and not the frame; a box crossing its edge or title bar selects it
  too. ⌘A selects every node and comment. ⌘C and ⌘V paste copies of notes and frames, offset down and right and
  selected; ⌘D duplicates; ⌘X cuts (one ⌘Z brings the cut items back); Delete removes selected comments with selected
  nodes in one step. Drag a node while a note is also selected: both move. Pinned: `CommentSelectionTests`,
  `CommentEditingTests`, `CommentMoveTests`. **Observed:**
- [ ] **CM-7 Inspector.** Select one note: the inspector shows a text box and seven accent swatches. Type two lines
  (Return makes a line break), then click empty canvas: the note shows both lines and one ⌘Z removes the edit. Type
  again and press ⌘↩: the text commits at once (gap CM-a, closed by MetalUI C9; Return alone still breaks the line);
  click away and the text commits. Select another comment while typing: the text lands
  on the note it was typed into. Pick an accent: the note re-tints at once, in each of the three themes. Select one
  frame: a title field and the swatches; Return commits "Front plate"; clearing it and pressing Return refuses with
  "A frame needs a title." and the old title returns. Select two comments: "2 comments selected". Pinned:
  `CommentInspectorTests`. The field losing focus commits the text; through the window only the canvas editor's focus loss is driven
  (`clickingIntoTheInspectorsBoxCommitsTheCanvasEditFirst`, group CT), not this box's own (gap M6-e is adopted), so only the
  model-level commit is pinned here, and **record whether clicking away from the text
  box, not only onto the canvas, commits it.** **Observed:**
- [ ] **CM-8 Saving.** Save with notes and frames, close, reopen: they are where they were, with their text, titles and
  accents; ⌘Z has nothing to undo. Open a file saved before comments: it opens unchanged. Editing a note marks the
  document edited. Pinned: `CommentFileTests`. **Observed:**
- [ ] **CM-9 Docked left.** Dock the panel left: comments are drawn transposed with the nodes, a frame still surrounds
  the same nodes, and Add Note, Frame Selection, moving and resizing behave as at the bottom (resize follows the pointer
  as drawn). Pinned: `CommentSelectionTests`, `CommentResizeTests`, `CommentCullingTests`. **Observed:**
- [ ] **CM-10 Cost.** Paste a few hundred notes (⌘V repeatedly) and pan, then zoom all the way out: panning is as smooth
  as with the same number of nodes, and the notes and frames cast no shadow. Pinned: `CommentCullingTests`,
  `eachCommentIsAFewRects`. **Observed:**

## Group CT — typing on the canvas (Comments typing plan)

**Status: PENDING (what only a person can judge).** Plan `2026-10-10-comments-canvas-typing.md`, spec
`2026-10-09-selection-groups-comments-design.md` §8 and its Errata (B: typing on the canvas). The tests pin the model and
the headless frames, and since the test-harness adoption (plan `2026-10-12-adopt-test-harness.md`, gap CT-c) they also
drive the double click, the focus and the keys through the app's real window: `CanvasNoteTypingWindowTests`,
`CanvasTitleTypingWindowTests`, `CanvasTypingKeysWindowTests`, `CanvasTypingFocusWindowTests`, `CanvasTypingUndoWindowTests`. A clause marked
**Automated** below has no manual step; what stays is how it looks and what the real machine does. Run
`swift run MetalCreatorApp` on a saved bracket with a note and a frame; CT-5 docks left.

- [ ] **CT-1 A note (the look).** Double click a note: a white-backed editor appears exactly over it, with the caret
  visible in it, and the note's text is in it, the caret at its end and nothing selected (gap CT-b, adopted: C25-2; ⌘A
  selects it all). Type two lines, press ⌘↩: the note shows the old text and both lines after it. **Automated, no manual step:** the editor lies over
  the note with focus in it the moment it appears, Return breaks the line and commits nothing, ⌘↩ commits as one undo
  step, Esc cancels, clicking away commits (`CanvasNoteTypingWindowTests`). Pinned: `CommentTypingTests`,
  `CommentDoubleClickTests`, `CommentEditorRenderTests`. **Observed:**
- [ ] **CT-2 Ending an edit (what is left).** **Automated, no manual step:** for a note, Esc closes the editor and the
  note keeps its old text with nothing to undo, ⌘↩ commits, Return breaks the line and the editor stays open, a click on
  empty canvas commits (one ⌘Z), and so does a press on the 3D viewport (`CanvasNoteTypingWindowTests`,
  `CanvasTypingFocusWindowTests`); for a frame's title, Return commits, Esc cancels, a click away commits
  (`CanvasTitleTypingWindowTests`). **By hand:** type and click another node: it commits (one ⌘Z). Type and click the
  inspector's accent swatch and **record what happens** (through the headless window the accent changes and the edit stays
  open with its draft until the next canvas press: decision D4, `anAccentSwatchPressChangesTheAccentAndLeavesTheEditOpenWithNothingLost`).
  Type, then ⌘S: the saved file has the text. Pinned: `CommentTypingTests`. **Observed:**
- [ ] **CT-3 A frame's title (what is left).** **Automated, no manual step:** a double click on the title bar opens a
  focused one-line field over the bar with the title in it; Return commits (one ⌘Z undoes it); Esc cancels; clearing it
  and pressing Return shows "A frame needs a title." and keeps the old title; dragging the title bar moves the frame and
  the nodes inside it as one undo step (`CanvasTitleTypingWindowTests`). **By hand:** paste text containing a line break:
  it becomes a space. A double click on the frame's edge band or its inside starts no edit. Pinned: `CommentTypingTests`,
  `CommentDoubleClickTests`. **Observed:**
- [ ] **CT-4 The graph's keys stand aside (what is left).** **Automated, no manual step** (`CanvasTypingKeysWindowTests`):
  with an editor focused, Delete deletes characters and no node; arrows move the caret and no node; Space and F type; ⌘A
  selects the text; ⌘⇧N adds no note, ⌘G, ⌘D and ⌘⇧C do nothing to the canvas; Tab does not open the add-node palette;
  afterwards, with the pointer over the canvas and nothing focused, Delete acts again, and with the pointer over the
  viewport it does not (User decision 1). (Starting an edit makes the comment the whole selection, so "nodes selected
  while an editor is focused" cannot arise.) **By hand:** ⌘C, ⌘X and ⌘V use the text, not the canvas's clipboard; over
  the canvas also the arrows, ⌘A, F and Space act again and Tab opens the palette; over the inspector's empty space they
  do not (**record it**). Pinned: `GraphPanelInputTests`, `SelectionKeyTests`, `NudgeTests`. **Observed:**
- [x] **CT-5 Both docks.** **Automated, no manual step:** docked bottom and docked left (which draws both transposed)
  the editor lies exactly over the note and over the title bar, and ⌘↩, Return and Esc behave the same
  (`CanvasNoteTypingWindowTests`, `CanvasTitleTypingWindowTests`, each run for both docks). Pinned:
  `CommentEditorRenderTests`, `CommentTypingTests`.
- [ ] **CT-6 Zoom (the look).** At 25 %, 100 % and 300 % (⌘-scroll, or the header buttons) repeat CT-1 and CT-3: typing
  works, and a click inside the editor places the caret under the pointer (the editor is drawn under a scale effect).
  **Record** whether the title field is usable at 25 % and whether the text is soft at 300 % (MetalUI divergence 106: text
  under a scale effect is resampled). **Automated:** at 0.5× and 2× the editor is scaled as the note is and lies over it
  (`theEditorFollowsTheCanvasZoom`). Pinned: `CommentEditorRenderTests`. **Observed:**
- [ ] **CT-7 Themes.** In each of the three built-in themes the editor's background, text and focus ring are readable
  over the note's tint and the title bar's tint, and Esc or ⌘↩ returns to the themed note. **Observed:**
- [ ] **CT-8 Undo (what is left).** **Automated, no manual step:** edit a note, ⌘Z gives the old text and ⇧⌘Z the new,
  one step each, over the canvas and over the viewport (`EditMenuRoutingWindowTests`, `CanvasTypingUndoWindowTests`); while an
  editor is open and focused, ⌘Z undoes the typing in the field and leaves the document alone (the measured answer,
  pinned: MetalUI's field keeps ⌘Z before the app's command, KF-C; decision D2). **By hand:** the same keys on a physical
  keyboard. **Observed:**
- [x] **CT-9 Inspector and canvas together.** **Automated, no manual step** (`CanvasTypingFocusWindowTests`): with a note
  selected the inspector shows its text; double click the note and type, and the inspector shows the old text until the
  edit commits; clicking into the inspector's box commits the canvas edit first and loses nothing; in the box, ⌘↩ commits
  and Return breaks the line (gap CM-a). Pinned: `CommentTypingTests`, `CommentKeysTests`.
- [ ] **CT-10 Focus (what is left).** **Automated, no manual step** (`CanvasTypingFocusWindowTests`): double click a note,
  double click another note, then a frame's title bar, without clicking elsewhere between: each edit commits and the next
  has the focus in its field (and Tab opens no palette, `tabOpensNoPalette`). **By hand:** the caret is visible
  in each new field, and Tab in an editor moves focus to the next control. Pinned: `CommentDoubleClickTests`.
  **Observed:**
- [ ] **CT-11 Inert chrome (gap CT-a).** While a note is being edited, press the graph panel's header gap, the glass
  padding and an empty area of the inspector. **Record** whether the editor stays open (the expected, documented
  behaviour: User decision 2) and what the next canvas press does. **Automated:** a press on the panel's glass padding
  leaves the editor open and focused, typing continues, and the next canvas press commits
  (`CanvasTypingFocusWindowTests`); **by hand:** the header gap and the inspector's empty area. **Observed:**
- [ ] **CT-12 Groups and saving.** Enter a group, double click a note there and type, then leave the group with ⌘↑: the
  text is in the definition's note. Save, quit, reopen: the text persists, the edit marked the document edited, and ⌘Z
  has nothing to undo. Pinned: `CommentTypingTests`. **Observed:**

## Group GR — groups: the editor (C2)

**Status: PENDING.** Plan `2026-10-09-groups-editor.md`, spec `2026-10-09-selection-groups-comments-design.md` §6 and
its Errata (C2). The tests pin the model and the frames; these check the gestures through a real window. Run
`swift run MetalCreatorApp` on a saved bracket, docked at the bottom, then GR-2 and GR-4 docked left too. Group the
plate and its extrude (select both, ⌘G) first.

- [ ] **GR-1 Look.** The group node has a header in its accent (purple) titled with the definition's name, and two
  rings around it, a thick one and a thin one inside. Change the accent in the inspector: header and rings follow.
  Switch the theme (View ▸ Theme): they follow. Select it: the outer ring thickens. Pinned: `GroupLookTests`.
  **Observed:**
- [ ] **GR-2 Entering and leaving.** Double-click the group node (two quick clicks): the panel shows its inside,
  framed, nothing selected, the header reads "Graph › Group" and Group Input and Group Output flank the nodes. Click
  "Graph" in the header: back out. Select the group node and press ⌘↓: in again, with the pan and zoom you left; ⌘↑:
  out. Pan and zoom inside, go out and in: they are as you left them; the top level's are too. Select the group node
  and press "Edit Group" in its inspector: in. Group something inside and go in twice: "Graph › Group › Group 2", and a
  click on "Group" goes up one level. ⌘↓ with a plain node selected does nothing. Pinned: `EditorLevelTests`,
  `EditorGroupEntryTests`. Order (plan decision 14): a double-click selects the group node, then opens it, so the
  selection clears on entry; on a Sketch node the node is selected first and the sketch opens second. **Observed:**
- [ ] **GR-3 Editing inside.** Inside, move a node, wire two nodes, add one from the library and one with Space, delete
  one: each is one ⌘Z. Add an Output node: "An Output node can't go in a group." Select everything and press Delete:
  Group Input and Group Output stay. ⌘C and ⌘V inside: the nodes copy, the boundary nodes don't. The part in the
  viewport follows every edit. ⌘Z until the group itself is undone while inside: the panel falls back to the top
  level. Pinned: `EditorLevelTests`, `EditorGroupClipboardTests`, `EditorLevelReviewTests`. **Observed:**
- [ ] **GR-4 The + sockets.** Inside, drag from a node's output onto Group Output's "+": a new output appears on Group
  Output named after the socket, wired, and the group node outside has it too; one ⌘Z removes both. Drag from Group
  Input's "+" onto an unwired input: a new input, wired, with the target's default, unit, range, access and optional
  (Errata (C2)); one ⌘Z removes it. Drag the wire from the node's socket to the "+" instead of the other way: the same.
  Drag an output onto Group Input's "+": the hint appears and nothing changes. Pinned: `ExposeSocketTests`.
  **Observed:**
- [ ] **GR-5 The inspector.** Select the group node: name, accent, "Used 1 time", Edit Group, Make Unique, Ungroup, and
  its inputs. Rename it (Return, or click away): its nodes and the library follow. Duplicate it (⌘D): "Used 2 times".
  Make Unique on the copy: it is named "<name> 2" and the original is "Used 1 time". Ungroup: its nodes come back
  selected. Inside, select Group Output: its sockets are listed; rename one (the wire outside follows), move one up
  and down, remove an unwired one. Remove a wired one: the message names the group node and nothing changes. Pinned:
  `EditorGroupInspectorTests`. **Observed:**
- [ ] **GR-6 The library.** The library ends with a "Groups" section listing each definition. Click one: another
  instance appears in view. Drag one onto the canvas: it lands where dropped. Search for part of a name: the list
  filters. Inside a group, click that group's own row: "A group can't contain itself." Delete both group nodes of a
  definition: its row offers Delete, which removes it (⌘Z brings it back). Pinned: `LibraryGroupsTests`.
  **Observed:**
- [ ] **GR-7 The viewport inside.** With Final preview, enter the group: the whole part stays. Switch to Selected node
  and click an inner node: its solid shows alone; click a node nothing reads (add one and wire only its input): it
  shows too. Select a Fillet or Extrude inside: its handle appears, and dragging it edits the definition as one ⌘Z;
  with two instances, both parts change. Pick edges in view on a rule inside: Done writes the rule, the Fillet works,
  and the second instance's Fillet works too. Showing another level during a pick cancels it. "Edit sketch" on a
  Sketch node inside says it can't yet. Open a sketch on the top level, then press ⌘↓ on a group node, or click a
  breadcrumb: nothing happens. Pinned: `GroupViewportTests`. **Observed:**
- [ ] **GR-8 Clipboard.** Select the group node, ⌘C, Ungroup (the definition goes), ⌘V: the group node returns with its
  definition. Copy it, enter the group, edit something inside, go out and ⌘V: a second definition "<name> (imported)"
  appears, as it was copied; the node already there still uses the edited one. ⌘V again: another node using the same
  "(imported)" definition, no third one. Rename the definition and paste a copy made before: no new definition.
  Pinned: `EditorGroupClipboardTests`, `GroupMergeTests`.
  **Observed:**
- [ ] **GR-9 Inner states.** Inside, set an Extrude's distance to -1: its header shows the error badge, and out on the
  top level the group node fails with "<name> › Extrude: …". Fix it: both clear. A node inside that nothing reads and
  that fails shows its badge and leaves the group node alone. Pinned: `InspectedLevelTests`, `EditorLevelTests`.
  **Observed:**
- [ ] **GR-10 Refusal caption.** Make any edit that is refused (for example drag a wire from a number into an Extrude's
  profile). The red message appears under the graph panel and the canvas ends above it: the bottom nodes are not covered
  by it. Wait for it to go (about 2 seconds) and the canvas grows back. With the message showing, drag a node type from
  the library and drop it on the message: nothing is added; drop it just above the message, on the canvas: the node is
  added (and the message goes, because an edit went through). Make a refusal with a long message (a sketch with a long
  error) and note whether it wraps over the bottom canvas row. Pinned: `PanelPlacementTests`, `LibraryDragTests`,
  `RefusalShakeTests` (the 16 pt line height is a constant; this check is the only measurement of a real caption line).
  **Observed:**
- [ ] **GR-11 Breadcrumb tooltips.** Inside a group two levels deep, hover each crumb in the header and wait for its
  tooltip. Only the crumb for the level just outside the one shown reads "Back to <name> (⌘↑)"; every other crumb reads
  "Back to <name>" with no shortcut (the top "Graph" crumb included when it is two levels out). At the top level no
  tooltip names ⌘↑. Press ⌘↑ and confirm it goes out one level, as the tooltip said. Pinned: `BreadcrumbRenderTests`.
  **Observed:**

## Group S5c — the sketch editor's links to the model and the viewport (S5c)

**Status: NOT RUN.** Run `swift run MetalCreatorApp`. Add a Rectangle wired into an Extrude (20 mm) into an Output, so
there is a box, then a Sketch (select it, "Edit sketch").

- [ ] **S5c-1 Project an edge.** In a sketch on the XY plane, press P ("Project ✓") and click one of the box's top
  edges: a purple line appears on the plane (nothing highlights the edge under the pointer while you aim: only faces
  highlight, a known gap, see Errata (S5c); a click takes the edge whose pixels it lands on). In the graph, the Sketch
  node now has a wire into `references` from the box's Extrude. The tool stays on Project after the click (click a
  second edge without pressing P again). One ⌘Z removes the line, the wire and the stored pick together. The purple line
  is real geometry: draw a closed shape that uses it and the fill appears. Draw a line ending on the purple line: "Point
  on" appears and the point stays on it when you drag. Change the Rectangle's width in the graph and the purple line
  follows. Pinned: `ProjectToolTests`, `SketchProjectTests`. **Observed:**
- [ ] **S5c-2 Project a face, and what can't be projected.** Press P and click the box's top face: all four of its edges
  project. Click a vertical edge: the inspector says "That edge can't be projected: it is perpendicular to the sketch
  plane, so it projects to a point." and nothing changes. Click a side face: only what projects appears, and the inspector
  says what was left out. Click the same edge twice: "That edge is already projected." Pinned: `SketchProjectTests`.
  **Observed:**
- [ ] **S5c-3 One part per sketch.** Add a second box, project an edge of the first in the sketch, then an edge of the second:
  "This sketch already projects from another part. Project from one part per sketch." Wire the Sketch's profiles into
  the first box's Extrude and try to project one of that box's edges: "That part is made from this sketch, so its edges
  can't be projected into it." Nothing is stored either time. Pinned: `SketchProjectTests`. **Observed:**
- [ ] **S5c-4 New sketch on face.** Finish the sketch. Right-click the box's top face: the menu reads Look At, Select Edges
  of Face, New Sketch on Face, Show Producing Node. Choose New Sketch on Face: a Plane from Face and a Sketch appear in the
  graph beside the box's Extrude, wired; the sketch is open, the view looks straight at the top face, and drawing works.
  One ⌘Z removes both nodes and leaves sketch mode. A side face of the box offers the same item; a cylinder's curved face
  does not. While a sketch is open, the right-click menu is empty. Nothing previews yet: the new Sketch feeds nothing, so
  wire its `profiles` into an Extrude to see a solid (the nodes are placed 240 and 480 points to the right of the producer
  and a little below, and may overlap nodes already there). Finish the new sketch without wiring it on, then press
  "Edit sketch" on it: it opens again. Pinned: `NewSketchOnFaceTests`. **Observed:**
- [ ] **S5c-5 Dimension labels.** Draw a rectangle and dimension it (D, then each side): each dimension shows a small glass
  label with its value ("60 mm") standing off its line. A circle's diameter and an arc's radius label sit on the curve's
  upper right and middle; an angle between two lines sits at their corner. Expose a dimension ("Expose as input"): its label
  reads "width = 60 mm". Make one a reference: "(40 mm)" in grey. Add a conflicting dimension: the label is red. The
  labels follow pans and zooms, and typing a new value in the inspector changes the label. Clicking a label picks what is
  under it. Pinned: `DimensionLabelTests`, `OverlayLabelTests`. **Observed:**
- [ ] **S5c-6 Labels and the camera** (gap S5-c). Open a sketch with dimensions: the labels appear after the camera has
  turned onto the plane, not during the turn. Pan and zoom: they stay on their dimensions with no lag you can see, and
  stay legible in the other themes. Note whether panning a sketch with many labels (20 or more) stays smooth. **Observed:**
- [ ] **S5c-7 Region fill.** Draw a closed shape: a faint green fill appears inside it, under the lines and points. A shape
  with a hole (a circle inside a rectangle) is filled around the hole; a small circle inside the hole is filled again.
  Open the shape (delete a line): the fill goes. Construction geometry is never filled. Drag a corner: the fill follows live.
  The fill never blocks a click: clicking inside it selects what is under the pointer, or clears the selection. Pinned:
  `RegionFillTests`, `RegionTriangulatorTests`, `OffscreenRenderTests.anOverlayFillTintsThePixelsItCoversAndNoOthers`.
  **Observed:**
- [ ] **S5c-8 Review follow-ups.** With Circle, click a centre, then move the pointer over an existing line while sizing the
  circle: the rubber band doesn't jump onto the line and no chip appears. Click a centre on a line: "Point on" appears and
  the centre stays on the line. Pinned: `SnapAndTangentCoverageTests`. **Observed:**

## Group NU — named undo steps

**Status: PENDING.** Plan `2026-10-10-named-undo.md`, spec `2026-10-09-selection-groups-comments-design.md` §7 and its
Errata (B: comments), parent spec §6.1. The tests pin the names on the model (`UndoTitleTests` pins the titles and that the
top bar draws them); these check what a person reads in the real menu bar and window. Run `swift run MetalCreatorApp` on a
saved bracket.

- [ ] **NU-1 Edit menu.** Open the Edit menu with nothing edited: the items read "Undo" and "Redo", both greyed. Press
  Cmd+Shift+N (Add Note) and open Edit again: "Undo Add Note" is enabled and "Redo" is greyed. Press Cmd+Z and open Edit:
  "Undo" greyed, "Redo Add Note" enabled. Pinned: `theTitlesNameTheStepsAndFollowUndoAndRedo`. **Observed:**
- [ ] **NU-2 Top bar.** The top bar's buttons read the same as the menu at every step of NU-1 ("Undo Add Note", then
  "Redo Add Note"), and the row stays on one line at the default window width, with the name not clipped. Make the
  window narrower: **record what the bar does when "Undo Resize" and "Redo Delete" no longer fit.** Pinned:
  `theTopBarDrawsTheTitle`. **Observed:**
- [ ] **NU-3 Each kind of edit.** After each edit below, the Edit menu reads as given. Add a node from the palette: "Undo Add
  <the node's type>". Drag a node: "Undo Move". Press an arrow key a few times: "Undo Move" (one step). Wire two sockets:
  "Undo Connect"; drag the wire off its input: "Undo Disconnect". Change an inspector slider by dragging it: "Undo Change
  <the input's label>" (one step for the whole drag). Select nodes and press Delete: "Undo Delete"; Cmd+X: "Undo Cut";
  Cmd+V: "Undo Paste"; Cmd+D: "Undo Duplicate". Pinned: `EditorUndoNameTests`. **Observed:**
- [ ] **NU-4 Comments.** Add Note: "Undo Add Note". Type in its inspector and click away: "Undo Edit Note". Frame Selection:
  "Undo Add Frame". Retitle the frame: "Undo Edit Frame". Drag a note: "Undo Move". Drag its handle: "Undo Resize".
  Delete it: "Undo Delete". Pinned: `editingNotesAndFrames`, `movingResizingAndDeletingComments`. **Observed:**
- [ ] **NU-5 Groups.** Cmd+G on two nodes: "Undo Group". Rename the group in the inspector: "Undo Rename Group" (the name you
  typed is not in the menu). Inside, drop a wire on Group Output's +: "Undo Add Output Socket". Make Unique: "Undo Make
  Unique". Cmd+Shift+G: "Undo Ungroup". Pinned: `groupUngroupAndMakeUnique`, `groupDefinitionEditsEachHaveTheirOwnName`,
  `groupSocketsAreExposedMovedAndRemoved`. **Observed:**
- [ ] **NU-6 Viewport.** Drag a handle in the viewport: "Undo Drag Handle" (one step). Pick edges in view and press Done:
  "Undo Pick Edges". Right-click a face, Select Edges of Face: "Undo Select Edges of Face"; New Sketch on Face: "Undo New
  Sketch on Face". Pinned: `AppUndoNameTests`. **Observed:**
- [ ] **NU-6b Sketch editor.** In a sketch, draw a line, a circle and an arc, add a constraint, type a dimension value,
  rename a dimension to something long ("Plate width"), Expose it, trim, fillet with a radius you typed, mirror and pattern:
  the menu reads "Undo Add Line", "Add Circle", "Add Arc", "Add Constraint", "Change Dimension", "Rename Dimension"
  (never the name you typed), "Expose Dimension", "Trim", "Fillet" (no radius), "Mirror" and "Linear Pattern"/"Circular
  Pattern" (no count). Drag a point: "Undo Move Point". Pinned: `SketchStepNameTests`, `aRenamedDimensionNeverReachesTheMenu`.
  **Record whether any name reads badly or is too coarse (for example "Delete" for an entity and for a constraint).** **Observed:**
- [ ] **NU-7 Typed value.** Type a new number into an inspector field without pressing Return and open the Edit menu: it
  names the step before the typed value (the value commits when Cmd+Z runs). **Record what it reads and whether that
  surprises you.** Pinned: `anInputEditIsTitledByTheInputsLabel`. **Observed:**
- [ ] **NU-8 Files.** Save, close and reopen: the Edit menu reads plain "Undo" and "Redo" (names are not saved). New does the
  same. Pinned: `aNewDocumentStartsWithPlainTitles`. **Observed:**

## Group FA — final-review follow-ups (app, viewport, docs)

**Status: NOT RUN.** Plan `2026-10-10-followups-app.md`. Run `swift run MetalCreatorApp`. The tests pin the models and the
renderer's buffers; these check what a real window shows.

- [ ] **FA-1 A moved plane.** On a box (Rectangle, Extrude, Output), right-click its top face and choose New Sketch on
  Face; the sketch opens on the face's plane. While it is open, change the Extrude's distance in the graph: the plane
  moves with the face, the camera looks at it again (animated) and the sketch stays open, drawn on it. Then delete the
  wire into the Sketch node's `plane`: one alert, "The plane lost its result", saying that nothing is wired into
  "plane" now, and the sketch stays open on the last plane; further edits raise no second alert. Pinned:
  `SketchPlaneFollowTests`. **Observed:**
- [ ] **FA-2 Handle labels after Open.** Save a document with the camera moved, quit, reopen it, and select an Extrude
  at once, before touching the viewport: its "10 mm" label stands beside the knob. Resize the window while it is
  selected: the label follows the knob. Pinned: `handleLabelsAreRebuiltWhenTheDrawRecordsTheFirstSize`. **Observed:**
- [ ] **FA-3 Scroll or pinch during a camera move.** Zoom with the wheel or a pinch and press F (or click a view cube
  face) in the middle of it: the next scroll or pinch step continues from what is on screen, with no jump when the
  animation would have finished. Pinned: `aScrollEventStopsAnAnimationStartedMidScroll`,
  `aPinchEventStopsAnAnimationStartedMidPinch`. **Observed:**
- [ ] **FA-4 A sketch orbit stays smooth.** In a sketch, orbit is locked to the plane, so pan and zoom the sketch with a
  dashed construction line and the grid on: the grid, the dashes and the points draw exactly as before, and a pan or zoom
  is no slower. Leave the sketch: the faint region fill goes. Pinned: `RendererCacheTests`. **Observed:**
- [ ] **FA-5 A colour drag.** Duplicate a theme, open Edit Themes… and drag a colour picker's selection around
  continuously: the window recolours smoothly with no stutter. Stop dragging, wait a second, quit and reopen: the last
  colour is kept. Drag again and quit at once (⌘Q): the colour is still kept. Pinned: `ThemeColorDragTests`,
  `ThemeColorPreviewTests`. **Observed:**
- [ ] **FA-6 A file arrives while an alert is up.** With the Save / Don't Save question up (edit, then ⌘W), or after a
  failed Open, double-click a `.mcgraph` in Finder: the alert on screen stays as it is and nothing opens behind it. Press
  OK, double-click again: it opens. Pinned: `AppModelOpenURLTests`. **Observed:**
- [ ] **FA-7 The command line.** In the packaged app (`scripts/package-app.sh`), running
  `MetalCreator.app/Contents/MacOS/MetalCreator --help` prints the usage and exits 0; `--info-plist ٢٦` is a usage error
  (exit 64). Pinned: `LaunchCommandTests`. **Observed:**

## Group PA — patterns: Place, the shortcut nodes and the Patterns library (7a-2)

**Status: NOT RUN.** Plan `2026-10-10-7a-place.md`. Run `swift run MetalCreatorApp`. The tests pin the nodes, the kernel and the
naming; these check what a real window shows. Build a plate (Rectangle on a plane at z = −6, Extrude 6) and a Grid Points
(4 × 3, 15 mm) wired into Points to Placements for the checks below.

- [ ] **PA-1 The library.** Open the node library: a "Patterns" section sits between Feature and Output, holding Place,
  Points to Placements, Hole Pattern, Boss / Pin Pattern, Slot Pattern and Pattern Feature, with the Feature colour on
  their headers. Typing "hole" in the add-node palette finds Hole Pattern. **Observed:**
- [ ] **PA-2 Holes.** (Spec §5 wants each shortcut documented as Place + Boolean underneath in its inspector help; until User decision 9 (b) is chosen this check is where it is stated: Hole Pattern gives the same part as a Place and a Boolean wired by hand.) Wire the plate and the placements into a Hole Pattern and an Output: twelve Ø5 holes cut from the top
  face down. In the inspector switch Mouth to Counterbore, then Countersink: the holes gain the step, then the cone; Through
  all cuts right through whatever the depth. Wire a Series (start 3, step 1, count 3) into `diameter`: the first three holes are 3, 4 and 5 mm and the rest repeat 5 mm. **Observed:**
- [ ] **PA-3 Bosses and slots.** The same plate with a Boss / Pin Pattern (draft 5°, tip fillet 1): twelve pins standing up from
  the face, leaning in, with rounded tips. Slot Pattern: twelve slots with rounded ends running along X; turn the placements
  with Points to Placements' direction (1, 0, 0) and the tools turn with them (on a side face, cutting or growing along X).
  **Observed:**
- [ ] **PA-4 Misses.** Raise Grid Points' spacing until holes fall off the plate: the Hole Pattern shows a warning badge
  reading "N of 12 holes miss the part." and the rest of the holes stay cut; the same for bosses ("bosses") and slots.
  **Observed:**
- [ ] **PA-5 A pick follows its instance.** Pick the rim of one hole (the Fillet's "Pick edges in view…") and fillet it. Change
  the spacing, the diameter, the depth and the row count: the fillet stays on the same hole. Add a column: the fillet stays on the
  same *position in the list* ({4}), which is now another hole, with no warning (User decision 7). Lower
  the count so that hole is gone: Edges by Tag shows "Instance {n} no longer exists, so the edge picked on it isn't selected."
  and nothing else is filleted. **Observed:**
- [ ] **PA-6 Too many.** Set Grid Points to 50 × 50 into a Hole Pattern: the Points to Placements node reads "Patterns are
  limited to 2,000 instances." and nothing hangs. **Observed:**
- [ ] **PA-7 The old bracket.** Open a bracket saved before this track (Grid Points → Transform → Boolean holes): it opens and
  evaluates exactly as before, no warnings. **Observed:**
- [ ] **PA-8 A pick inside a group.** Select the plate, the grid, Points to Placements and a Hole Pattern and Group them; enter the group, add an Edges
  by Tag and a Fillet inside it, and pick a hole's rim in the viewport (the pick is written relative to the level). Change the
  grid's count so that hole is gone: the warning names the instance, then raise it again and the fillet returns on the same
  position. Leave the group: the result is unchanged. **Observed:**
- [ ] **PA-9 The Hole Pattern node on the canvas.** The node has about ten sockets: it reads clearly at normal zoom, its labels
  ("Counterbore diameter", "Countersink angle") are not clipped, the Patterns header (the Feature colour, User decision 2) reads as
  a Feature-family node, and the inspector's sections are in a sensible order. **Observed:**
- [ ] **PA-10 A projected rim.** In a Sketch wired to the Hole Pattern's result, Project (P) the rim of one hole: the circle
  appears and a dimension on it holds. Lower the grid's count so that hole is gone: the sketch warns "Projected edge 1 was
  picked on instance {n}, which no longer exists. Its constraints are ignored." and projects no other hole's rim. **Observed:**


## Group TR — data trees (7a-1)

**Status: NOT RUN.** Plan `2026-10-10-7a-trees.md`, spec `2026-10-10-patterns-trees-design.md` §2 and §4's tree nodes. Run
`swift run MetalCreatorApp`. The tests pin the models, the messages and that the views draw; these check what a real window
shows. Build the graph first: Series (count 24) into Partition (size 8) into Number-in nodes such as Rectangle `width`.

- [ ] **TR-1 Library.** Open the node library: a "Lists & Trees" section sits between Feature and Output, in the Value
  colour, listing Branch by Path, Flatten, Graft, List Item, Partition, Path Mapper and Tree Statistics. Search "path": both
  Path nodes show. Pinned: `theLibraryTitlesTheCategory`, `theBuiltInsAreTheSliceTheSketcherAndTheTreeNodesInSevenCategories`.
  **Observed:**
- [ ] **TR-2 Socket tooltips.** With the graph above evaluated, rest the pointer on Partition's output dot for a second: the
  tooltip reads "Tree 3 × 8". The dot of the wired input on the node after it says the same. A dot carrying one item or a plain
  list shows nothing at all when you rest on it: no bubble, not even an empty padded one (MetalUI shows a bubble for any help
  text, so such a dot declares none). **Record whether the tooltip appears over a dot this small.** Look at the colour too: the
  dots of the tree nodes (`any` sockets) and the wires leaving them are drawn in the Value colour; **record whether a wire from
  a tree node is hard to tell from a number wire** (if it is, that is a product question, not a bug). Pinned:
  `theSocketsOfATreeShowItsShape`, `onlyADotThatCarriesATreeDeclaresATooltip`. **Observed:**
- [ ] **TR-3 The Data section.** Select Partition: the inspector ends with a "Data" section, "Tree out  3 × 8" and a "Show
  paths" button. Press it: three rows, `{0}`, `{1}`, `{2}`, each "8 items"; it reads "Hide paths" now, and the list stays open
  while you select another node and come back. Undo is not enabled by it. Change the size to 5: "5 branches: 5, 5, 5, 5, 4" and
  the list follows. Select Series: no Data section. Make 60 branches (Series count 120, Partition size 2): the list stops after 50
  rows and ends with "and 10 more". Pinned: `thePathListOpensAndClosesAndIsNotAnEdit`, `aLongPathListIsCutShort`. **Observed:**
- [ ] **TR-4 Path Mapper.** Add a Path Mapper after Partition: its Rule row shows `{A} → {A}` in a text field. Type
  `{A} → {(i)}` and press Return: the table is transposed (the tooltip says "Tree 8 × 3"); the Edit menu says "Undo Change Path
  rule". Click away instead of pressing Return: the rule is kept. Type `{A;B} → {B;A}`: the table is
  transposed again, as 8 × 3 (a source with one letter more than the tree has levels of branches names items; User decision 2).
  Type `{A;B;C} → {A}`: the node's badge shows an error and its tooltip reads "The rule's source {A;B;C} names 3 levels, but
  this tree (3 × 8) has 1 level of branches. Write the source with 1 level, like {A}, or with 2, like {A;B}, to name items too." Type
  `{A} → {C}`, then `{A`, then `{A} → {A/0}`: each names its failing part. The rule's text field should fit the inspector at
  its default width: no clipped text at either end, a long rule scrolls inside the field instead of widening the panel.
  Pinned: `PathRuleTests`, `PathMapperNodeTests`, `typingARuleStoresItAsOneNamedUndoStep`. **Observed:**
- [ ] **TR-5 A rule that matches some branches.** On a 2 × 3 × 2 tree (Partition twice), `{A;A} → {A;A}` gives a ⚠ badge, "The
  rule matched 2 of 6 branches; the other 4 stay where they were." and the data is unchanged. Type `{0;B} → {B;0}`: the badge
  adds "1 of them shares a branch with the results, so their items are mixed in." Pinned:
  `aRuleMatchingSomeBranchesWarnsAndKeepsTheRest`, `aLeftBranchThatSharesAPathWithAResultSaysSo`. **Observed:**
- [ ] **TR-6 Broadcasting.** Wire Partition's tree into a Rectangle's `width` (Series from 1), the Rectangle into an
  Extrude and that into Output: 24 boxes appear, and the Extrude's output tooltip reads "Tree 3 × 8". Wire a plain Series of 8
  into `height`: each row pairs with it item by item. Wire a tree of another depth (Partition twice) into `height`: a ⚠ badge
  names both shapes, once. Pinned: `aFlatListAppliesToEveryBranch`, `differentDepthsWarnWithBothShapes`. **Observed:**
- [ ] **TR-7 Boolean and branches.** Subtract an Extrude of a 3-row hole tree from a plate: three plates appear, one per row,
  each with its own row of holes. Pinned: `eachRowOfHolesCutsItsOwnCopyOfThePlate`. **Observed:**
- [ ] **TR-8 Old files.** Open a bracket saved before this change (format 5): it opens with every pick holding and no warning;
  save it, and the file says `"formatVersion" : 6`. An older build refuses the new file. Pinned: `TreeFileTests`. **Observed:**
- [ ] **TR-9 List Item and Branch by Path.** Add a List Item after Partition (3 × 8): with the "Item path" field empty and
  index 1 it gives one item per row. Type `{1;2}` into Item path and press Return: it gives that one item and the index no
  longer matters. Type `{1}`: the node's badge says the path has 1 index but an item of this tree (3 × 8) needs 2. Type
  `{1;99}`: "No item {1;99}: {1} has 8 items." Clear the field: the index is used again. Add a Branch by Path with `{2}`: the
  third row. Pinned: `anItemPathTakesTheOneItemAtThatPath`, `anItemPathOverridesTheIndex`, `aBlankItemPathMeansUseTheIndex`,
  `aMissingBranchOrItemInAPathSaysHowManyThereAre`, `aMissingBranchSaysHowManyThereAre`. **Observed:**

## Group PL — patterns: the layouts, trees of placements and previews (7a-3)

**Status: NOT RUN.** Plan `2026-10-12-7a-layouts.md`, spec `2026-10-10-patterns-trees-design.md` §3, §6, §8 and its Errata (7a-3). Run
`swift run MetalCreatorApp`. The tests pin the nodes, the naming, the overlay's lines and the file; these check what a real window
shows. Build a plate (Rectangle 120 × 80 on a plane at z = −8, Extrude 8) and an Output for the checks below.

- [ ] **PL-1 The library.** Open the node library: the "Patterns" section opens with Linear Pattern, Grid Pattern, Circular Pattern,
  Curve Pattern and Face Pattern, then Place, Points to Placements and the shortcuts. Typing "ring" in the add-node palette finds
  Circular Pattern. **Observed:**
- [ ] **PL-2 Triads.** Add a Grid Pattern (4 × 3, 10 mm) and select it with nothing wired to it: a small x (red), y (green) and z (cyan)
  triad appears at each of the 12 placements, each axis a little under half the distance to the next. Change the counts and the
  spacing in the inspector: the triads follow at once. Select another node, or two nodes: they go. Right-click on a triad, click on
  it, press F and drag the view: it never picks, opens a face menu or changes what F frames. **Observed:**
- [ ] **PL-3 How they read.** Do the triads read at the default zoom, on a dark and a light theme (View ▸ Theme ▸ Alucard)? Set a Grid
  Pattern to 40 × 50 (2,000 placements): the view stays smooth. **Record whether the axes are too small or too big** (the 40% rule is
  a guess). Then select a Hole Pattern's Circular Pattern so that its triads sit on the plate's top face and look from below and from
  inside the plate: they are drawn through the solid, never faded (User decision 13). **Record whether that reads or clutters**, and
  so whether depth-aware guides are wanted. **Observed:**
- [ ] **PL-4 Rings and per-ring sizes.** Circular Pattern (radius 15, count 4, rings 2, radius step 10, count step 4) into a Hole Pattern
  on the plate (through all), with a Series (6, step −2, 2 values) into a Graft into `diameter`: the inner ring has four Ø6 holes and
  the outer eight Ø4. Pick the rim of one outer hole (Fillet ▸ Pick edges in view…) and fillet it. Set rings to 3: the fillet stays
  on the same hole. Set rings to 1: the Edges by Tag rule warns "Instance {1;3} no longer exists, so the edge picked on it isn't
  selected." (use the path of the hole you picked) and nothing else is filleted. Turn the start angle: the holes and the fillet turn
  together. **Observed:**
- [ ] **PL-5 Pattern on Face.** Right-click the plate's top face: the menu offers Look At, Select Edges of Face, New Sketch on Face,
  **Pattern on Face**. Choose it: a Face Pattern appears beside the Extrude, wired from it and selected, its triads fill the face and
  a dashed outline runs round it, 3 mm inside the edge. Switch Stagger on: every second row moves half a pitch. Raise the margin to
  12: the outer columns and rows go. Undo: both the node and the wire go in one step ("Undo Pattern on Face"). Right-click a side
  face of a cylinder: no Pattern on Face. **Observed:**
- [ ] **PL-6 Holes in the face.** Drill the plate first (a Hole Pattern, Ø20, through) and use Pattern on Face on its top: no placement
  stands within the margin of the hole, and the dashed outline circles the hole. **Record how the outline looks at the hole** (it is
  a mitred guide; the placements are exact). **Observed:**
- [ ] **PL-7 Vents.** Face Pattern (spacing 14 × 12, stagger, margin 6) into a Slot Pattern (8 × 3, through all): staggered vents run
  across the plate, clear of the edge and of the bolt holes. Pick the rim of one vent (Fillet ▸ Pick edges in view…) and fillet it,
  then raise the margin by a few millimetres so some vents drop: the fillet stays on the same vent, or, if that vent has gone, the
  Edges by Tag rule warns naming its path (`{row;column;0}`) and nothing else is filleted. Make a bolt hole bigger: the same.
  **Record which of the two happens to the vents beside the dropped ones** (it must be neither a different vent nor a neighbour).
  **Observed:**
- [ ] **PL-8 Curve and Linear.** Edges by Direction (X) on the plate into a Curve Pattern (count 5): five triads along each of four
  edges, facing along the edge. A Rectangle into a Curve Pattern's `profile`: placements round the outline. A Linear Pattern
  (count 6, spacing 8) into a Hole Pattern: a row of holes. **Observed:**
- [ ] **PL-9 A Boolean over a tree.** Wire a Grid Pattern into Place and Place into a Boolean's `tools` (subtract from the plate): one
  plate per row, each with its row of copies cut, as for any tree (spec §2). Flatten between Place and the Boolean: one plate with every
  copy cut. **Record whether this is the surprise it may be** (a Hole Pattern over the same grid cuts every hole at once). **Observed:**
- [ ] **PL-10 Tree display.** A Grid Pattern's output dot reads "Tree 3 × 4" on rest; the inspector's Data section lists `{0}` to `{2}`
  with 4 items each. A Linear Pattern's reads as a plain list. **Observed:**
- [ ] **PL-11 Old files and groups.** Open a bracket saved before this track: it opens with every pick holding and no warning. Group a
  Hole Pattern fed by a Grid Pattern and enter the group: Pattern on Face says it can't be made inside a group yet. **Observed:**
- [ ] **PL-12 A list on a layout.** Wire a Series into a Grid Pattern's `spacingX`: the node refuses with "Grid Pattern takes single
  values, not lists: wire one value into each input, or pick one out of the list first with List Item." and shakes. Put a List Item
  between the Series and the socket: it works. The same for Circular Pattern's `radius`. **Observed:**

## Group VA — variation and culling (7a-3 part B)

**Status: NOT RUN.** Plan `2026-10-12-7a-variation.md`, spec `2026-10-10-patterns-trees-design.md` §4 and §6. Run
`swift run MetalCreatorApp`. The tests pin the nodes, the generator and the naming; these check what a real window shows. Build a
plate (Rectangle 60 × 40 on a plane at z = −6, Extrude 6) and a Grid Points (4 × 3, 15 mm) into Points to Placements into a Hole
Pattern (Ø5, depth 6) into an Output; then put the nodes below between Points to Placements and the Hole Pattern.

- [ ] **VA-1 The library.** The "Patterns" section ends with Cull Pattern, Cull Index, Cull by Region, Random Reduce, Random Values and
  Jitter after Pattern Feature (the layouts come first in the section). Typing "cull" in the add-node palette finds three.
  Pinned: `thePatternsSectionHoldsThePatternNodes`. **Observed:**
- [ ] **VA-2 Cull Pattern.** The Pattern row shows `1 0` in a text field: every other hole is gone. Type `1 1 0` and press Return: every
  third is gone. Type `1 2`: the badge reads "“1 2” isn't a pattern. Use 1 to keep an item and 0 to cull it, like 1 0 1." The
  Edit menu names each change ("Change Cull pattern"). A long pattern scrolls inside the field. Set Scope to Overall with the
  placements in rows (Partition by 4): the mask runs on from one row into the next. Pinned: `CullPatternNodeTests`,
  `VariationSettingTests`. **Observed:**
- [ ] **VA-3 Culled tooltips and the Data section.** With Cull Pattern selected, rest on its output dot: the tooltip reads "Tree 6, culled".
  The inspector's Data section lists `{}` with 6 items. **Record that the section shows no gaps (a culled branch's missing
  indices are not listed).** Pinned: `theShapeSaysCulled`. **Observed:**
- [ ] **VA-4 Cull Index.** Type `1, 4` into Cull Index's field: holes 1 and 4 are gone and the others have not moved. Type `{2}`: the
  same as `2`. Type `{0;3}`: the badge reads "{0;3} has 2 indices, but an item of this tree (12) needs 1. Write it like {0}." Type `{}`: the badge
  reads "“{}” names the whole tree. To cull everything, use Cull Pattern with 0." Type `{9}`: the badge reads
  "{9} names nothing in this tree." and the holes are unchanged. Pinned: `CullIndexNodeTests`. **Observed:**
- [ ] **VA-5 A pick follows its hole through a cull.** Fillet the rim of one hole (pick it in the viewport). Cull another hole with
  Cull Index: the fillet stays on the same hole, which has not moved, with no badge. Cull the filleted hole itself: Edges by Tag
  reads "Instance {n} no longer exists, so the edge picked on it isn't selected." and nothing else is filleted. Clear the cull: the
  fillet returns. Pinned: `CulledPickTests`. **Observed:**
- [ ] **VA-6 Cull by Region.** Add a Vector (0, 0, 0) and a Cull by Region with Reference "Point", Keep "Outside or beyond" and
  distance 12: the holes nearest the middle are gone. Switch Keep: only they remain. Switch Reference to Profile with nothing wired:
  the badge reads "Connect or set “profile”." Wire a Rectangle into `profile`: holes inside it stay. Its two sections (Region and
  Keep) fit the inspector without clipping. Pinned: `CullByRegionNodeTests`. **Observed:**
- [ ] **VA-7 Random Reduce.** Set Count 3, Overall, Seed 5: three holes are gone. Change the Seed: other holes go, and the badge never
  appears. Set it back to 5: the same three. Raise Count to 4: the same three and one more. Switch to Fraction 0.5, Per branch with
  the placements in rows (Partition by 4): half of each row. Pinned: `RandomReduceNodeTests`. **Observed:**
- [ ] **VA-8 Random Values.** Wire Random Values (min 4, max 6, Seed 5) with the Jitter's output in `shape` into the Hole Pattern's
  `diameter`: the holes differ in size, and a hole keeps its size when another is culled. Wire `integers` into a Cull Index's
  `indices`: no badge. Set min 0.2, max 0.8: `integers` has no socket result (a wire from it says it isn't produced). Pinned:
  `RandomValuesNodeTests`, `VariationPipelineTests`. **Observed:**
- [ ] **VA-9 Jitter.** Jitter (distance 1, turn 30) after the cull: the holes move a little, none out of the plate's plane, and the Seed
  re-rolls them without a badge. Selecting Jitter shows no preview triads (previews are the layout nodes' only); record that nothing
  shows. Pinned: `JitterNodeTests`. **Observed:**
- [ ] **VA-10 The same file twice.** Save the graph, quit, reopen it: the holes are exactly where they were (the seed is saved, nothing
  else is random). On a second machine, if there is one, the same file gives the same part. Pinned: `SeededRandomTests`.
  **Observed:**
- [ ] **VA-11 Undo.** Undoing a pattern or a path edit puts the previous mask back and the holes with it; the Edit menu names the step
  ("Change Cull pattern", "Change Cull indices"). Pinned: `VariationSettingTests` (the names and the undo; the menu text is human).
  **Observed:**
- [ ] **VA-12 A cull before Points to Placements.** Move the Cull Index to sit between Grid Points and Points to Placements (wire Grid
  Points into it and it into Points to Placements) and type `0`: the first point's hole is gone and the others stay where they are,
  exactly as when the cull came after Points to Placements. Fillet the rim of the fifth hole (index 4): it stays on that hole when you
  change the cull to `1`, and with the cull changed to `4` the badge reads "Instance {4} no longer exists, so the edge picked on it
  isn't selected." Pinned: `CulledPickTests` (both stages), `pointsToPlacementsKeepsACulledListsIndices`. **Observed:**
- [ ] **VA-13 Equal seeds.** Random Reduce (Count 3, Seed 0) and Random Values (Seed 0, wired into the Hole Pattern's `diameter`): the
  holes Random Reduce drops are not simply the smallest ones. Pinned: `withTheSameSeedTheItemsRandomReduceDropsAreNotTheSmallestRandomValues`.
  **Observed:**
- [ ] **VA-14 A cull in rows keeps `{row;column}`.** Replace Grid Points and Points to Placements with a Grid Pattern (4 × 3, 15 mm)
  wired into the Cull Index. Fillet the rim of the hole in the second row, third column (`{1;2}`), then type `1` into the Cull
  Index: the second column goes from every row and the fillet stays on the same hole. Type `{1;2}`: the badge reads "Instance {1;2}
  no longer exists, so the edge picked on it isn't selected." and nothing else is filleted. Type `{1}`: the whole second row is gone,
  the other rows have not moved, and the same badge appears. Pinned: `CulledTreePickTests`. **Observed:**
- [ ] **VA-15 Points to Placements in rows.** Put a Partition (size 4) between Grid Points and Points to Placements: the placements come
  out as three rows of four (the Hole Pattern's holes are `{row;column}`), and a Cull Index `{1;2}` between Partition and
  Points to Placements leaves every other hole where it was. Pinned: `aTreeOfPointsIsATreeOfPlacementsAtTheSamePaths`,
  `CulledTreePickTests` (`beforePlacements`). **Observed:**
- [ ] **VA-16 Cull by Region, Edges.** Reference Edges, wire All Edges of the plate into `edges`, Within 12 mm, Keep "Outside or
  beyond": the holes nearest the plate's rim go and the middle ones stay. Wire Edges by Tag on a hole pattern's rims instead (circles):
  the same node measures to them. Wire an edge set with a spline in it: the badge says how many of the edges it can't measure.
  Pinned: `CullByRegionNodeTests`. **Observed:**
- [ ] **VA-17 Cull by Region, Face.** Reference Face. **Record whether anything in the library can feed `faces`** (at the time of
  writing no node outputs a face set, User decision U18, so the socket cannot be wired from the window and the node reports the missing
  input). If a face-set node exists by now, wire a flat face's set to it: the distance is to the face's **plane**, so a flat face
  far to the side of a small face counts as near it (record that this surprises, as the Errata say; User decision U3). A curved face
  refuses with the count. Pinned: `theFaceReferenceCullsByDistanceToTheFacePlane`, `aCurvedFaceIsRefusedWithTheCount`. **Observed:**
- [ ] **VA-18 Cells three deep.** With Face Pattern (7a-layouts) on a face, wire its placements through Cull Pattern `1 0`: every vent
  stays (per branch, one item each). Set Scope to Overall: every other vent goes. Cull Index `1`: nothing goes; `{0;1}` removes
  one vent and the others have not moved; a pick on a vent follows it through that cull. Random Reduce (defaults) removes one vent.
  Pinned on a hand-made `{row;column;0}` tree: `CellTreeTests`, `CellTreePickTests`. **Observed:**

## Group C16 — MetalUI C16: click counts, cancellation, wheel latching and held modifiers (Adopt C16)

**Status: NOT RUN.** Plan `2026-10-12-adopt-c16.md`. Run `swift run MetalCreatorApp` with a trackpad, and a mouse with a middle
button for C16-5. The tests drive the real window with synthesized event sequences (`ViewportModifiersWindowTests`,
`ViewportCancelWindowTests`, `CanvasCancelWindowTests`, `ScrollLatchWindowTests`, `CanvasDoubleClickWindowTests`); these checks
are what a sequence cannot show: the feel of a glide, a real ⌘ key, the system's double-click setting, and the OS taking an
input away mid-gesture.

- [ ] **C16-1 A glide stays where it began.** (Completes GI-1.) Flick-pan the graph canvas hard and, while it glides, move the
  pointer onto the viewport, then the inspector, then (library shown) the node library's list: the canvas glides on to a stop
  at its usual rate; the viewport doesn't zoom, the inspector and the library don't scroll. Flick the library's list and move
  onto the canvas mid-glide: the list glides on and the canvas doesn't pan. Flick-zoom the viewport and move onto the canvas:
  the canvas doesn't pan. Pinned: `ScrollLatchWindowTests`. **Observed:**
- [ ] **C16-2 ⌘ over a still pointer.** (Completes S5-3.) In a sketch choose the Line tool and click a start point. Move the pointer
  so the rubber band snaps horizontal (the chip reads "Horizontal"), then hold ⌘ without moving the mouse: the chip goes and the
  band sits exactly under the pointer at once; let ⌘ go: the snap and the chip return. Hold ⌘ and click: the end lands unsnapped.
  Hold ⌘, ⌘-Tab to another app and back with ⌘ let go: the chip is back, not stuck off. ⇧ and ⌥ change nothing. Pinned:
  `commandOverAStillPointerSuppressesTheGlyphsAndReleasingBringsThemBack`, `ViewportModifiersWindowTests`. **Observed:**
- [ ] **C16-3 The system's double-click speed.** (Completes S5b-7.) In System Settings > Mouse set the double-click speed to its
  slowest: a slow double click on a Sketch node opens its sketch, on a note it edits the text, on a group node it enters; a pair
  of clicks slower than the setting only selects. Set it to its fastest: a quick double click still works and a medium one
  doesn't. Two clicks on two different nodes never open anything; ⇧- or ⌘-double-click only changes the selection; a triple
  click opens once. Pinned: `DoubleClickTests`, `CommentDoubleClickTests`, `CanvasDoubleClickWindowTests`. **Observed:**
- [ ] **C16-4 A pinch cut short.** Start a pinch on the graph canvas, ⌘-Tab away mid-pinch, come back and pinch again at the same
  spot: it zooms from the zoom the canvas has, with no jump back. Same on the viewport. Pinned: `aPinchCutShortByLosingKey…`
  in `CanvasCancelWindowTests` and `ViewportCancelWindowTests`. **Observed:**
- [ ] **C16-5 An input lost mid-drag.** Middle-drag the canvas (and, separately, the viewport), open Mission Control or a native
  menu while holding the button, release elsewhere and come back: at the first plain pointer move the closed hand is gone and
  the camera has settled. Do the same with a left drag of a node (a gap, VI-b, in MetalUI: record what you see; the drag ends
  by the next press or drag, see `aPrimaryPressOnTheSameElementLeavesTheLostDragToTheNextDragValues`). **Observed:**
- [ ] **C16-6 A scroll cut short.** ⌘-scroll the canvas and ⌘-Tab away mid-glide; come back: a plain scroll pans, a ⌘-scroll
  zooms, nothing is stuck ignoring a glide. Scroll the viewport and ⌘-Tab away mid-scroll: the next scroll zooms from where
  the camera is. Pinned: `keyLossDuringAZoomsGlideLeavesNothingIgnoredForTheNextScroll`, `aScrollCutShortByLosingKeySettlesTheCamera`.
  **Observed:**
- [ ] **C16-7 The panel's edge.** Drag the graph panel's inner edge, take the release away as in C16-5, come back and move the
  pointer: the panel doesn't follow it; a new drag of the edge starts from the panel's size. Pinned:
  `aPanelResizeWhoseReleaseWasLostEndsWhenAnotherElementIsPressed`. **Observed:**

## Group C21 — MetalUI C21: the glass blur (Adopt C21)

**Status: NOT RUN.** Plan `2026-10-12-adopt-c21.md`. Run `swift run MetalCreatorApp` on a Mac with a display, and open a document
with a visible model (File > Open on a saved bracket, or the demo). The tests pin what a frame holds (one material record per
panel, painted after the viewport's surface, under the theme's tint at the opacity `GlassStyle` computes: `GlassFillTests`,
`GlassBackgroundTests`, `ChipGlassTests`, `GlassBlursViewportTests`); these checks are what only a screen shows: whether the
blur is there and looks right over a moving viewport, how it reads at each thickness, how it costs (the system's Reduce
Transparency, C21-5, waits on MetalUI). **MetalUI's own checks BB1 to BB6 are unrun**, so a fault here may be MetalUI's: run the same thing in
MetalUI's demo (`METALUI_LOOKS_DEMO=1 swift run MetalUIDemo`, BB1 with a panel over the MetalView demo) before logging a gap. At
Dracula's 86% glass the blur is faint by design (the role says the panel hides 86% of what is behind it); to see it plainly,
lower the Glass role's opacity in the theme editor to about 40% for C21-1 and put it back.

- [ ] **C21-1 The blur over a moving viewport.** With the top bar, graph panel and inspector showing, orbit, pan and zoom the
  model: behind each panel the model, grid and gradient are blurred (soft, no edges), outside the panels the viewport stays
  sharp; the panel's colour is the theme's tint, with the hairline. No tearing, no ghost of an earlier frame and no one-frame lag
  between a panel and what it blurs (MetalUI BB2). Switch View > Theme to Alucard and Nord: the tint and the material go light in
  Alucard, and each panel follows. Lower the Glass role's opacity in the theme editor: the blur shows more, and every panel
  follows at once. Pinned: `GlassBlursViewportTests`, `GlassFillTests`. **Observed:**
- [ ] **C21-2 Thickness and legibility.** Look at each surface: the top bar, graph panel, inspector, theme editor, pick banner (start a
  pick), the Show graph button (hide the panel with Tab), the palette (Space over the canvas) and the sketch chips (draw a line in a
  sketch: the readout chip and an inference chip). Every text is easy to read over a busy part of the model; the palette is
  slightly stronger than the panels. Write down any surface that wants a thicker or thinner material (user decision 1 of the plan).
  Pinned: `eachSurfaceHasTheThicknessTheDecisionGaveIt`. **Observed:**
- [ ] **C21-3 Smoothness.** Orbit and pan with every panel showing, and again with the panels hidden (Tab, so no blur is drawn): the orbit
  stays as smooth with the blur as without (spec §9 risk "the cost of glass blur over a continuously redrawing
  `MetalView`"), also on a document with the 200-instance pattern. Note the GPU use in Activity Monitor for both. **Observed:**
- [ ] **C21-4 The sketch chrome is still opaque to the pointer.** In a sketch, click in the gaps between the toolbar's buttons and on
  an inspector label: nothing is drawn, the selection does not change, and the rubber band does not follow the pointer under the
  panel (the material paints and takes no pointer, so the backdrop still does). Pinned: none (a pointer test through a material is
  C21-4 alone). **Observed:**
- [ ] **C21-5 Reduce Transparency (waits on MetalUI).** MetalUI does not honour the setting (gap C21-b, sent to the
  MetalUI session 2026-10-12) and there is no stopgap here, so this check cannot run yet: the panels blur whatever System Settings >
  Accessibility > Display says. Run it once MetalUI provides `\.accessibilityReduceTransparency` and the app adopts it. **Observed:** n/a
- [ ] **C21-6 Glass over glass.** Open the palette over the graph panel, the theme editor over the inspector, and draw with a chip over a
  panel: the upper glass blurs the lower (blurred twice, MetalUI BB3), stays legible and has clean edges. **Observed:**
- [ ] **C21-7 Resize and docks.** Resize the window, move it between a Retina and a non-Retina display if you have one, drag the
  graph panel's inner edge, and switch the dock (Left, Bottom, Hide): the blur follows with no stale or stretched blur and no
  flash of an unblurred frame (MetalUI BB4). **Observed:**
- [ ] **C21-8 Small glass.** The Show graph button and the chips are small: each blurs only its own box (MetalUI divergence 247), so
  it reads as a soft frosted patch of the backdrop's average colour. Judge whether that reads as glass or as an odd flat patch; if
  odd, the chips can go back to the flat tint (user decision 3 of the plan). **Observed:**

## Group C25 — MetalUI C25: text selection and caret control (Adopt C25)

**Status: NOT RUN.** Plan `2026-10-12-adopt-c25.md` (gap CT-b). Run `swift run MetalCreatorApp` on a saved bracket with a note and a frame. The tests
drive the real window (`CanvasTypingSelectionWindowTests`: the opening selection, typing replacing and appending, the keys
publishing back) and the model (`CommentEditSelectionTests`); these checks are what a sequence cannot show: how the selection
looks, the feel of the caret, an input method composing, and the keys of a real keyboard. For C25-3 add an input source
(System Settings > Keyboard > Input Sources, for example Japanese Hiragana or Pinyin).

- [ ] **C25-1 A title opens selected.** Double click a frame's title bar: the field appears over the bar with the whole title
  highlighted (the selection colour is visible against the bar's tint, the text stays legible). Type a letter: it replaces the
  whole title and nothing else; keep typing: the letters append (the title is not selected again). Press Return: the frame
  has the new title; ⌘Z puts the old one back. Repeat docked left and at 25 % and 300 % zoom: the highlight lies exactly
  over the text. Pinned: `aTitleOpensWithAllOfItSelectedAndTypingReplacesIt`. **Observed:**
- [ ] **C25-2 A note opens with the caret at its end.** Double click a note with one line and with three lines: nothing is
  highlighted, the caret blinks after the last character (on the last line), and typing appends there. With a note whose
  text ends in a line break the caret is on the empty last line. An empty note opens with the caret at its start. Pinned:
  `aNoteOpensWithTheCaretAtItsEndAndTypingAppends`, `aNoteEndingInALineBreakOpensOnItsEmptyLastLine`. **Observed:**
- [ ] **C25-3 An input method composing (the feel).** With a composing input source, open a title (all selected) and start
  composing: the underlined marked text replaces the selection, and committing it (Space or Return as the input source
  does) leaves the composed text as the title; Return after that commits the title, and the first Return of a composition
  must commit the composition, not the title. In a note, compose at the end and mid-line (click first), then press ⌘↩.
  The model writes the selection only when an edit begins, so nothing can race a composition: **record** any caret jump,
  lost marked text or doubled character. **Observed:**
- [ ] **C25-4 Select all and the selection keys.** In a title and in a note: ⌘A highlights all of it and typing replaces it;
  ⇧← and ⇧→ extend from the caret, ⇧⌥← selects a word, ⌥← moves a word, ⌘← and ⌘→ go to the line's ends, Delete removes the
  selection, and a double click on a word selects the word. After each, typing acts on what is highlighted. **Record** a key
  that does something else. Pinned: `theKeysPublishWhatTheyDoBackToTheModel`, `aNoteIsSelectedAllByCommandAAndReplacedByTyping`.
  **Observed:**
- [ ] **C25-5 A click places the caret.** Open a title (all selected) and click inside its text: the highlight goes and the
  caret sits under the pointer; typing inserts there. Same in a note. Pinned: `aClickInsideTheEditorMovesTheCaretAndPublishesIt`.
  **Observed:**
- [ ] **C25-6 Every edit opens fresh.** Open a title, move the caret to the middle, press Esc; open it again: it is all selected
  again, not at the middle. Open a note, move the caret to the start, press ⌘↩, open it again: the caret is at the end. Pinned:
  `eachEditOpensFreshNotWhereTheLastOneEnded`. **Observed:**
- [ ] **C25-7 Undo inside the field.** Open a title, type a letter (it replaces the title), press ⌘Z while the field is focused:
  **record** what the field shows and where the selection is (MetalUI ends the open typing group when the selection is
  written at the edit's start; what ⌘Z restores is not documented yet, gap CT-d, so record it, don't judge it). Pass: then Esc,
  and the frame keeps its old title and the document has nothing to undo.
  **Observed:**
