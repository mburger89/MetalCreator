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
  - Shift-drag pans with the pointer (the stopgap modifier tracker).
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
  values and one `ended`. The camera doesn't move. Pinned: `draggingAHandleEditsItsValueAndNotTheCamera`. Observed:
- [ ] **V10 Resize and displays.** Resizing the window live shows no stretched or blank frames, and picking stays
  accurate after a resize. Moving between a Retina and a 1× display keeps lines crisp. Starting the harness in a
  narrow window (drag it narrow, quit, relaunch) frames the whole bracket, not clipped at the sides. Pinned:
  `aSceneShownBeforeTheFirstDrawIsFramedOnceTheViewHasASize`. Observed:
- [ ] **V11 Grid steps.** Zooming in and out switches the grid between 1, 10 and 100 mm, and the label follows. Pinned:
  `gridSpacingStepsWithZoom`. Observed:
