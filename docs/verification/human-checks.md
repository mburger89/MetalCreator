# Human checks

Checks an agent can't perform: each needs a person at an unlocked Mac with a real pointer. Tick the box and write
one line under **Observed** ("as expected", or what you saw). Each item names the test that pins the behaviour
headless, so a "looks wrong" report can become a failing test.

## Group V — the 3D viewport (M4)

**Status: NOT RUN.** Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`).

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
  - Shift-drag pans with the pointer (the stopgap modifier tracker). Known limit (gap 5): `held` modifiers can go stale if Shift is released while the window is inactive.
  - ⌥-drag up zooms in toward where the drag began.
  - + and − zoom toward the pointer.
  - F frames the part (with `HARNESS_SELECT=1`, the selected top face).

  Pinned: `shiftDragPansAndOptionDragZooms`, `keyZoomGoesTowardTheLastHoverPoint`, `fFramesTheSelectionBeforeEverything`. Observed:
- [ ] **V4 Hover.** The face under the pointer gets a faint cyan tint that follows the pointer without flicker or lag.
  After an orbit drag, a +/− zoom or a view-cube click with the pointer left still, the tint (and a right-click menu)
  is on the face under the pointer now, not the one before the move.
  Pinned: `hoverAsksThePickerOrTheCube`, `movingTheCameraUnderAStillPointerRepicks`,
  `idPassReportsTheFaceAndEdgeUnderChosenPixels`. Observed:
- [ ] **V5 View cube.**
  - TOP, FRONT, RIGHT and the other labels are readable on the faces turned toward you.
  - The region under the pointer turns cyan, and so does the region the camera looks straight from (FRONT after
    clicking FRONT). Pinned: `theCubeTintsTheRegionTheCameraLooksFrom`.
  - Clicking FRONT animates (about 250 ms, smooth) to a straight-on orthographic view.
  - Clicking an edge or corner gives a 45° or isometric view in the current projection.
  - Dragging the cube orbits.
  - ◀ ▲ ▼ ▶ rotate 90° to the adjacent face, and ⌂ goes home.
  - The View menu switches Perspective and Orthographic, Shaded and Shaded + Edges, and Set Home View makes ⌂ return there.

  Pinned: `ViewCubeTests`, `clickingTheCubeLooksAtTheRegionUnderThePointer`, `arrowsAndHomeAnimate`. Observed:
- [ ] **V6 Face menu.** Right-click a face: Look At, Select Edges of Face and Show Producing Node.
  - Look At animates to face that face, orthographic, framed on it.
  - The other two print the face's edges and the producing node.
  - Right-click empty space: no menu.

  Pinned: `ContextMenuTests`. Observed:
- [ ] **V7 Ghost.** `HARNESS_GHOST=1` draws the part desaturated at about 40% opacity, with the grid visible through it.
  It's one even layer: the far side, the hole walls and the back faces don't show through or darken it (the depth
  prepass). Speckles on the ghost would mean the prepass and colour pass disagree on depth: add `[[invariant]]` to
  the vertex position in `ViewportShaders` and compile with `MTLCompileOptions.preserveInvariance = true`.
  Pinned: ghost flags in `ghostsSelectionAndHoverReachTheFrame`. Observed:
- [ ] **V8 Selection.** `HARNESS_SELECT=1` shows the flange's top face and its edges glowing pink (#ff79c6). Edges stay
  pink in Shaded mode. Pinned: `edgeInstancesAreOnePerSegmentWithTheirPickID`. Observed:
- [ ] **V9 Handles.** A purple arrow handle at the plate top labelled "6 mm", and an orange radial handle at a fillet
  labelled "R 3 mm". Dragging a knob moves it along its axis, the label follows, and the terminal prints `changed`
  values and one `ended`. The camera doesn't move. Known symptom (gap M4-a): handle labels are missing on the first build of a document with a saved camera, and misplaced during a live resize, until the next rebuild. Pinned: `draggingAHandleEditsItsValueAndNotTheCamera`. Observed:
- [ ] **V10 Resize and displays.** Resizing the window live shows no stretched or blank frames, and picking stays
  accurate after a resize (known symptom, gap M4-a: handle labels are missing on the first build of a document with a saved camera, and misplaced during a live resize, until the next rebuild). Moving between a Retina and a 1× display keeps lines crisp. Starting the harness in a
  narrow window (drag it narrow, quit, relaunch) frames the whole bracket, not clipped at the sides. Pinned:
  `aSceneShownBeforeTheFirstDrawIsFramedOnceTheViewHasASize`. Observed:
- [ ] **V11 Grid steps.** Zooming in and out switches the grid between 1, 10 and 100 mm, and the label follows. Pinned:
  `gridSpacingStepsWithZoom`. Observed:

## Group M5 — the graph panel and inspector (M5)

**Status: NOT RUN.** Following MetalUI's convention (`../MetalUI/docs/verification/human-checks.md`).

Run `swift run GraphPanelPreview`.

- [ ] **M5-1 Dracula colours.** Headers are comment-blue (Number), green (Rectangle), purple (Extrude), pink
  (All Edges), orange (Fillet), cyan (Output). Header text is dark (`#282a36`). Body text is near-white, hint text
  blue-grey. Pinned: `PaletteTests`. **Observed:**
- [ ] **M5-2 Selection glow.** Click Extrude: it gets a 2-pt outline and a soft glow in *purple*, its own header
  colour. Click Fillet: the glow is orange. Pinned: `selectionGlowIsTheNodesOwnHeaderColour`. **Observed:**
- [ ] **M5-3 Glass panels.** The panel and inspector are translucent dark with a faint 1-pt light hairline and rounded
  corners (no blur yet, gap M5-c). **Observed:**
- [ ] **M5-4 Wires.** Wires are smooth curves leaving outputs forwards and entering inputs forwards, coloured by the
  source socket (green from Rectangle, purple from Extrude, pink from All Edges). Socket dots use the same colours.
  Pinned: `WireGeometryTests`, `wiresRunBetweenTheirSocketAnchors`. **Observed:**
- [ ] **M5-5 Docks.** Press Left: the graph becomes a column flowing top to bottom, inputs on top edges and outputs
  on bottom edges, the layout a mirror (x↔y) of the bottom dock. Press Bottom: it flows left to right again with
  every node back where it was. Press Hide: the panel goes and a "Show graph" button appears at the bottom left.
  Press Tab (even with an inspector field focused): the panel returns to the last side. Hide again and click "Show
  graph": same. Pinned: `DockTests`, `theHiddenPanelLeavesAShowButton`; the Tab shortcut is this check only.
  **Observed:**
- [ ] **M5-6 Pan, zoom, hit testing.** Drag empty canvas: it pans. Press + three times with the pointer over a node:
  the node stays under the pointer. Click a socket's edge at that zoom and drag: a cyan wire follows the pointer.
  Pinned: `HitTestTests`. **Observed:**
- [ ] **M5-7 Wiring.** Drag Rectangle's output onto Extrude's profile input: a wire is made (it replaces the old one).
  Drag Number's output onto Extrude's profile: nothing connects, Extrude jumps sideways and springs back (a brief
  wobble, gap M5-i), and "A number can't connect to a profile input." shows under the canvas for about two seconds.
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
