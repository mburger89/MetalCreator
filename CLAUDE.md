# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

MetalCreator is a node-based parametric CAD app for macOS built on MetalUI (`../MetalUI`, joined in M4).
The binding spec is `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md`; milestone
plans live in `docs/superpowers/plans/`. M0 (OCCT probe), M1 (graph engine), M2 (OCCT kernel), M3 (the 26 nodes), S3 (profile holes) and S4 (the Sketch and Plane from Face nodes) are done. S5a (the sketch editor in the viewport: sketch mode, drawing, constraints, dimensions, live solve) code is done; its human checks (group S5) are pending. S5b (trim, extend, fillet, mirror and pattern tools, 3-point arcs, point-on and tangent inference with glyphs, double-click to edit) code is done; its human checks (group S5b) are pending; S5c (Project, New sketch on face, dimension labels in the view, region fill) code is done; its human checks (group S5c) are pending. M4 (viewport) code is done; its human checks (group V in `docs/verification/human-checks.md`) are pending. M5 (graph panel and inspector) code is done; its human checks (group M5 in `docs/verification/human-checks.md`) are pending.
M6 (app shell) code is done; its human checks (group M6) are pending.
MetalUI C8 (the app shell: close and quit veto, window title and edited dot, open-document events) is
adopted, except the hidden title bar (gap M6-c, held for check AS-5); its human checks (group AS) are pending.
Editor polish (the floating add-node palette and the node library) code is done; its human checks (group EP) are pending.
Packaging (`scripts/package-app.sh`, `docs/packaging.md`) is done; its human checks (group P) are pending.
Multi-select polish (sub-project A of `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`) code is
done; its human checks (group MS) are pending.
MetalUI C10's looks and controls are adopted (plan `docs/superpowers/plans/2026-10-09-adopt-c10.md`; human checks group C10
pending): the inspector's sliders end an undo step with `Slider(onEditingChanged:)` (`EditorModel.sliderEditingChanged(_:)`),
a refused node shakes with `keyframeAnimator` (`RefusalShake`, `EditorModel.shakeCount(of:)`), an evaluating node's badge is
a `ProgressView`, the preview window's background is a `LinearGradient` (`WindowBackground`), and the glass panels keep the
theme's flat tint on purpose (no backdrop blur exists, gap C10-a).
Themes (custom themes, `.mctheme` files, the theme editor) code is done; its human checks (group TH) are pending. Each role is edited with MetalUI C10's `ColorPicker` (plan Task 11).
M7 (measure and record) code is done: spec §7.3's numbers are in `docs/verification/performance.md`, taken by the
release benchmarks in `Tests/CreatorAppTests/Bench` (`scripts/bench.sh`); `docs/metalui-gaps.md` opens with a summary
table of every gap, its MetalUI item and its status; its human checks (group M7) are pending.
Canvas comments (sub-project B of the same spec, §7: sticky notes and comment frames, plan `2026-10-09-comments.md`)
code is done; its human checks (group CM) are pending.
Typing on the canvas (spec §8: a double click on a note or a frame's title bar edits it in place; plan
`2026-10-10-comments-canvas-typing.md`; the graph's keys and text focus on MetalUI C9's key regions) code is done; its human
checks (group CT) are pending.
Groups C1 (model and evaluation, `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` §4–§5) is done.
Groups C2 (the editor, §6: entering a group, breadcrumbs, the + sockets, the group inspector, the library's Groups
section, the viewport and the clipboard inside groups) code is done; its human checks (group GR) are pending.
Named undo steps (plan `docs/superpowers/plans/2026-10-10-named-undo.md`) code is done; its human checks (group NU) are pending.
Final-review follow-ups (plans `docs/superpowers/plans/2026-10-10-followups-app.md`, `2026-10-10-followups-editor.md` and
`2026-10-10-followups-kernel.md`) code is done; the app track's human checks (group FA) are pending.

Module boundaries (dependency order):
- `CreatorGeometry`: value types (vectors, planes, profiles, bounds). Millimetres.
- `CreatorSketch`: the constraint sketch model, `SketchSolver` (numeric Levenberg–Marquardt with analytic Jacobians,
  DOF and minimal conflicts), `SketchRegions` and `SketchCommands`. Imports only `CreatorGeometry` and Foundation;
  never iterate a dictionary where order reaches output. Tests: `swift test --filter CreatorSketchTests`.
- `CreatorKernel`: the `Kernel` protocol, `Solid`, tagged topology tables, `FakeKernel` for tests (it refuses extruded holes that lie outside
  the outline's bounds, as OCCT refuses strays).
- `COCCT` + `CreatorOCCT`: the OpenCascade C shim and `OCCTKernel: Kernel` (topology tables, face tags carried through
  OCCT history, tessellation, STEP/STL export). **The only code that may touch OCCT.** Every C allocation has a
  `*_free`; no C++ exception crosses into Swift.
- `CreatorGraph`: graph model, sockets, broadcasting, `Evaluator` (cached, cancellable), commands and undo,
  `.mcgraph` files, `DocumentModel`. Depends on `CreatorSketch` for the `ConstantValue.sketch` setting. A node's sockets
  are `NodeRegistry.inputs(for:)`/`outputs(for:)`: `NodeDefinition.inputs(for:)`/`outputs(for:)` of its type
  (default: the static lists), or, for a group node, Group Input or Group Output, its definition's (the registry
  carries the document's definitions: `DocumentModel.registry`, `withGroups(_:)`). Every reader (the Evaluator,
  `connectionProblem`, the canvas, the inspector) asks the registry, so per-node sockets wire and gather like declared
  ones.
  - Undo names: every undo step carries a short English name (`UndoStack.Entry.name`), given where the edit is made:
    `DocumentModel.perform(_:at:coalescingKey:name:)` takes one of `UndoName`'s constants ("Add Note", "Move", "Delete");
    without one (or a blank one) the step is "Edit", so a forgotten name shows as "Undo Edit" and fails the test of its
    call site. A coalesced run keeps its first record's name. Names have no numbers and never include text the person
    typed (a note, a group's or dimension's name); an input is named by its fixed label ("Change Width"), a node by its
    type ("Add Box"). The sketch editor (graph-free) gives each `SketchCommit` a fixed `name` from `SketchStepName`
    ("Add Line", "Change Dimension", "Fillet"; `SketchEditorModel.commit` requires `named:`, `SketchCommit.init` and
    `EditorModel.edit` require `name:`), which `AppModel.storeSketch`
    passes through `UndoName.sketch(_:)`; `SketchCommit.description` ("Rename d1 to Plate width") holds typed text and
    numbers and is never a name. `DocumentModel.undoName` and `redoName` feed `AppModel.undoTitle` and `redoTitle`, which
    the Edit menu (`AppCommands`) and the top bar (`TopBar`) show as "Undo <name>" and "Redo <name>" (plain "Undo"/"Redo"
    with nothing to take back). Names are in memory only and not part of `.mcgraph`. Tests: `UndoNameTests`,
    `EditorUndoNameTests`, `SketchStepNameTests`, `AppUndoNameTests`, `UndoTitleTests`.
  - Groups (`Sources/CreatorGraph/Groups`): `GroupDefinition`s live in `GraphContent.definitions` beside the top-level
    graph (`DocumentModel.content`); a group node is type `group` with `NodeSetting.group`, and every `NodeRegistry`
    registers `group`, `groupInput` and `groupOutput` itself (`NodeRegistry.all`, the palette's list, leaves them out).
    Edits go through `GraphContent.apply`: graph commands on the top level, `.inDefinition(id, …)` (or
    `DocumentModel.perform(_:at:)`) inside a definition, plus `addDefinition`/`removeDefinition`/`setInterface`; it
    refuses a group inside itself (`GroupDependencies`), an Output node in a group and a stray or missing Group
    Input/Output, and (after the whole command) a socket removed or retyped while still wired. `GroupCommands`
    builds Group, Ungroup, Make Unique and the definition edits as `GroupEdit`s (one undo step). The Evaluator runs
    a group node's definition level by level (`Evaluator+Groups`): values pass through, inner nodes evaluate and
    cache under `NodeID.scoped(instance path + id)`, so their tags differ per instance and stay put when the
    definition is edited; inner messages read "Rib › Fillet: …". A pick stored inside a definition names faces as
    if the definition were the top level (`GroupScopes.identity`), and `EvaluationScope.naming` reads it as each
    instance's; Group, Ungroup and Make Unique rename every pick whose faces they move (`GroupScopes.renamingPicks`),
    so no pick drifts. Dirty state compares `DocumentModel.content` (definitions too).
    The editor's levels (`GraphContent.path(entering:)`, `existingLevels(_:)`, `relativeToLevel(_:levels:)`: a level is
    the group nodes entered from the top level, each by its ID in the graph before it) and
    `DocumentModel.inspectedLevel` (the level the panel shows, which `Evaluator.evaluate(…inspecting:)` evaluates
    whole, so `innerResults` has a state for every node there; a node asked for that way never changes its group
    node's result). `GroupCommands.exposeOutput/exposeInput` (the + sockets) and `GroupMerge` (the clipboard's
    definitions, merged by content) build one command each. `GroupNaming.plusSocket` ("+") is a reserved name.
- `CreatorNodes`: the 28 built-in node definitions (`BuiltInNodes.registry`: the slice's 26 plus Plane from Face and
  Sketch), UI-free: inspector sections and handles are data. Non-socket settings (`NodeSetting` in CreatorGraph:
  parameter, picks, showHandle, sketch, face, groupID, and `projection(reference)` per projected edge) live in
  `Node.inputValues`; `NodeRegistry.makeNode` seeds `defaultSettings` and sets `isOutput` for `.output`-category nodes.
- `CreatorStyle`: colour themes (spec §6.6, Dracula by default), the only place colour hex values are written.
  `ThemeColors` is a colour per role (never a hue); `ColorTheme` (not `Theme`: MetalUI exports one) has the built-ins
  `.dracula`, `.alucard` and `.nord` (read-only); `ThemeRole` names each role (`ThemeColors[role]`; the names are the
  `.mctheme` keys; `ThemeRoleTests` pins them to the stored properties). `@MainActor @Observable ThemeStore` holds
  `current`, `select(_:)` and the custom themes (`customs`: duplicate, rename, `setColor`, `setDark`, delete, import,
  export), saving each change to an injected `ThemeFolder` before showing it (`nil`: memory only, every test's; a colour
  picker's drag is the one exception: `previewColor` shows each sample and `saveColors()` writes once, driven by
  `ThemeEditorModel.dragColor` after `saveDelay` and by `flush()` on close, and a failed save puts the saved colours
  back; the folder skips a file named like a built-in in any case, and never writes an id that is not a file name), with
  injected `ThemePreferences` (`UserDefaultsThemePreferences` in the app). `ThemeFile` is the `.mctheme` format
  (version 1; missing roles are Dracula's, unknown ones ignored, a bad colour refused naming its role); custom themes'
  colours are always `quantized` (opacity to a byte) so a file round-trips exactly. `ColorTheme.controlTheme` maps
  roles onto MetalUI's control tokens. Editor and app views read `@Environment(ThemeStore.self) var themes:
  ThemeStore?` and draw `Palette(themes)` (Dracula without a store); the viewport draws `ViewportModel.theme`, which the
  app shell sets. Themes are app-level, never in `.mcgraph`. Tests: `swift test --filter CreatorStyleTests`.
- `CreatorViewport`: the 3D viewport on MetalUI's `MetalView`.
  - A host takes the primary pointer through `ViewportModel.tool` (`ViewportTool`: hover, clicks, and plain primary
    drags it claims, each with a `ViewportProjector` for screen → plane), and draws over the scene with
    `showOverlay(_:)` (`ViewportOverlay`: world-space lines and points in `OverlayTint` roles, dashed construction, and
    a `gridPlane` that replaces the ground grid). Navigation (right/middle drags, Shift/⌥ drags, scroll, pinch, the
    cube, handles) always stays the viewport's; the face menu offers only Look At while a tool is set. A tool's
    `navigation` (`ViewportNavigation`, default `.free`) of `.planar` locks the orientation: drags that would orbit
    pan, the cube and its controls are hidden, turning commands and the face menu do nothing (`showsViewCube`,
    `isPlanar`; the first scene's framing never runs, and input finishes an animation instead of freezing it); a tool's
    `framingBounds` is what F frames, and `ViewportProjector.modelArea` the area its on-screen chrome stays in.
    `lookAt(_ plane:framing:)` faces a plane, orthographic. A tool also takes the face or edge under a click it declined
    (`clickedModel`: the sketch editor's Project). `ViewportOverlay` also carries `fills` (`OverlayFill`: world triangles
    in the `.region` tint, one blended pipeline drawn under the lines, never in the ID pass) and `labels` (`OverlayLabel`:
    text anchored in world space, placed by `overlayLabels()` and drawn as MetalUI text over the surface, hidden while
    the camera animates: gap S5-c). The face menu adds New Sketch on Face (`ViewportEvents.newSketchOnFace`) on a flat
    face that has a normal, outside sketch mode.
  - `ViewportModel` (`@MainActor @Observable`, testable without a GPU) owns the camera, picking, the view cube,
    the context menu and handles. `ViewportRenderer`/`ViewportPicker` are the Metal side. `ViewportView` is the
    MetalUI glue. A `ViewportItem` with `isGuide` is no part of the scene: only its selected edges are drawn, after the
    solids and ghosts (faded where the part hides them), and it never frames, orbits, picks or opens the face menu
    (`ViewportRenderer+Guides`). The renderer keeps the triad's, the overlay's and the region fills' GPU buffers between
    frames: the overlay's key holds the grid's extent and the dashes' zoom, not the pose, so an orbit allocates none, and
    the fills' buffer is dropped once a frame has no fills (`RendererCacheTests`). `handleLabels()` reads the size through
    `observedViewSize`, as `overlayLabels()` does. Every scroll or pinch event stops a camera animation started mid-gesture.
  - It depends on Kernel, Geometry, CreatorStyle and MetalUI only, never CreatorGraph. The app shell turns graph outputs into
    `ViewportItem`s and `HandleSpec`s into `ViewportHandle`s.
- `CreatorEditor`: the graph panel and context inspector on MetalUI. `@MainActor @Observable EditorModel` holds all
  behaviour (selection, canvas transform, dock transpose, hit testing, wiring, clipboard, palette, inspector edits);
  views are thin MetalUI `Component`s. Depends on Graph/Kernel/Geometry, CreatorStyle and MetalUI — **not** on `CreatorNodes`.
  Its input (MetalUI C7 gestures, C9 key scoping, and the palette's stopgaps) lives only in `GraphPanelInput`. A double
  click on a node (two plain clicks on its body at most `EditorModel.doubleClickInterval`, 0.4 s as the groups spec's §6
  says, not macOS's 500 ms default, and `doubleClickSlop`, 4 points, apart, timed by the injectable `now`; gap S5-b)
  presses its first inspector button in `doubleClickActions` ("Edit sketch"; `nodeDoubleClicked(_:)`); the same pairing on
  a note or a frame's title bar, not its edge band (a `ClickTarget`, kept in `lastClick`), starts editing it in place
  (`beginEditing(_:)`). While a sketch is open the app ignores it (`AppModel.handle(_:)`'s guard).
  The canvas builds only what can show (`EditorModel.drawnNodes`, `drawnCanvasRect`: the visible canvas grown by
  `cullingMargin`, everything while unplaced), and below zoom `rowsMinimumZoom` draws nodes without their rows
  (`drawsNodeRows`); hit testing, selection and edits always see the whole graph. A
  `ForEach` over nodes keys them `id: \.id.rawValue`: MetalUI names elements by their id's description and drops a
  repeat (gap M7-a), and a `NodeID` prints only 8 hex digits. The window's size reaches the panel's placement through
  `ViewportModel.observedViewSize` (bumped one task after the draw records a new size, gap M4-a), never `viewSize`
  itself, so a resize rebuilds the canvas.
  The graph panel shows a level (`EditorModel+Levels`: `enteredGroups`/`levelPath`, `enterGroup(_:)`, `exitGroup()`,
  `goToLevel(_:)`, `breadcrumbs`, `refreshLevel()` after anything that undoes): `EditorModel.graph` is the level's
  graph, so every reader (hit testing, drawing, the inspector, selection) sees it, and every edit goes through
  `edit(_:coalescingKey:)`, which addresses `graphPath` (comments' edits too); the document's parameters stay on
  `rootGraph`. Each level keeps its own pan and zoom in the model (not saved), and changing level clears the selection.
  A group node's Edit Group, Make Unique and Ungroup are its inspector buttons (`InspectorAction`), carried out by
  `EditorModel.press`; a double click on a group node presses Edit Group through S5b's recogniser; ⌘↓/⌘↑ enter and
  leave. Group Input/Output draw a "+" socket (a `NodeShape` socket named `GroupNaming.plusSocket`); a wire between it
  and another socket exposes a socket (`EditorModel+Expose`). `GroupPanel` (`EditorModel.groupPanel`, `GroupPanelView`)
  is the inspector's definition part; the library's "Groups" section carries a group by the key `GroupLibraryEntry.key`
  through the library's one gesture. `NodeClipboard.definitions` carries the definitions copied group nodes use.
  The selection is `canvasSelection` (`CanvasSelection`: nodes and comments); `selection`
  is its nodes, and assigning it replaces the whole selection (selected comments too). Every gesture and key goes through
  `EditorModel+Selection` (`select(_:mode:)` with `SelectionMode`: none replaces, ⇧ adds, ⌘ toggles; `allItems`,
  `items(for:)`, `items(intersecting:)`, `positions(of:)`, `moveCommands(from:by:)`, `bounds(of:)`), the only members
  comments extend (spec 2026-10-09 Errata (A)).
  Canvas comments (`StickyNote`, `CommentFrame`, `CommentID`, `CanvasRect`: `Sources/CreatorGraph/Comments`) are per
  `Graph` (`stickies`, `frames`; a definition's inside has its own), saved sorted by ID and only when present (format 5,
  keys optional), edited by the four commands `setSticky`/`removeSticky`/`setFrame`/`removeFrame` (a set adds or
  replaces whole, so a move, resize or edit is one command), and never affect evaluation (`affectsResults` is false).
  A comment's `frame` is stored left-to-right like a node's position; the left dock draws the transpose of origin and
  size (`CanvasFlow.display(_:)`). Geometry is `CommentLayout` (computed, never measured); a frame holds the nodes whose
  drawn centres lie inside it (`EditorModel.members(of:)`, never stored), and a moved or nudged frame carries them
  (`carried(by:)`). Hits: `CanvasHit.note`/`.frame` (title bar and 6 pt edge band only)/`.resize` (the 12 pt
  bottom-right handle of a selected comment, begins `CanvasInteraction.resizing`); draw order frames, wires, notes,
  nodes with the selected last in each kind (`drawOrderFrames`, `drawOrderNotes`, culled as `drawnFrames`/`drawnNotes`).
  Add Note and Frame Selection are `addNote(atScreen:)`, `addNoteAtPointer()` and `addFrameAroundSelection()`, on ⌘⇧N,
  ⌘⇧C and the canvas's context menu (`CanvasMenuItem`); ⌘X cuts. The inspector's comment page is `CommentPage`
  (`CommentInspectorView`); text commits through `PendingEntry.textCommit`, on ⌘↩ (⌃↩ off macOS; `CommentKeys.commitsNote`, an
  `onKeyPress` on the box: MetalUI C9, gap CM-a), on focus loss or any model commit.
  Typing on the canvas: `EditorModel.commentEdit` (`CommentEdit`) is the comment being edited in place, `commentEditor`
  (`CommentEditor`) where its field goes (a note's rectangle, a frame's title bar, in display canvas points). Its draft
  rides the model's one `pendingEntry` (`EditorModel+CommentEditing`: `beginEditing`, `commentDraftChanged`,
  `commitCommentEdit`, `cancelCommentEdit`), so a canvas press, a selection or level change, hiding the panel, undo, save
  and export commit it, as one `setNoteText` / `setFrameTitle` step (the inspector's own paths), and a field typed into
  elsewhere (`notePendingEntry`) commits it first. `CommentEditorLayer` draws the field (`CommentEditorField`: a
  `TextEditor`, ⌘↩ commits, or a `TextField`, Return commits; Esc cancels; losing focus commits) under the canvas's own
  zoom and pan, as the sibling of `CanvasSurface`, the canvas's key region: never inside it, or the field's keys would
  reach the canvas's handler. Comment views draw no shadows and few rects (`StickyView`, `CommentFrameView`). Make Unique copies a definition's
  comments (`GroupCommands+MakeUnique`); Ungroup splices them into the level. ⌘A, arrows (one undo step per key-down run) and F act only while the
  panel shows; Esc closes the palette, then cancels a drag, then clears the selection.
- `CreatorSketchEditor`: the sketch editor (sketcher spec §8). `@MainActor @Observable SketchEditorModel` holds the
  sketch being edited, its live solve (`solve(_:dragging:)` per drag step), the tool and its stroke, the selection, and
  the inspector's rows; it is the viewport's `ViewportTool` (planar navigation; F frames the sketch) and builds its
  `ViewportOverlay` and the pointer readout (`pointerReadout`, while drawing or dragging a point; placed by
  `ReadoutChip`, drawn by its `PointerReadoutView`, which the app puts over the viewport, with the inference glyphs'
  `InferenceChip`). The command tools (Trim, Extend, Fillet, Mirror, Pattern) run `SketchCommands` on a click and show
  a refused command's message as `refusal`; their settings are `SketchToolOptions`. A click within the pick radius of
  a curve (not a point) holds a new point on it (point-on); a line leaving an arc's end snaps tangent; ⌘ suppresses
  both, never a shared point. Project (P) declines the plane click and takes the viewport's pick: the host resolves it
  (`events.projection`) into `ProjectionCandidate`s, each becomes a fixed `.projected` entity with a reference `edgeN`, and
  the commit's `projections` carry the picks to store. The overlay also carries a fill per closed region
  (`RegionTriangulator`, found again only when the sketch changes) and a read-only label per dimension
  (`SketchDimensionLabels`). Graph-free: every edit is
  a `SketchCommit` (the whole sketch, solved and remembered) through `events.committed`, which the host stores.
  Depends on CreatorSketch, CreatorViewport, CreatorKernel (Project's `EdgePick`), CreatorGeometry, CreatorStyle and
  MetalUI only. Its keys are toolbar
  button shortcuts (L, A (again: 3-point arc), C, D, T, P, X, ⌫, ⌦, ⏎, Esc; ⌦ and Esc are hidden buttons; Fillet has no
  key because F frames the sketch), which run before the graph panel's
  `onInput` keys; the Delete button and the hidden ⌦ one are never disabled, so ⌫ and ⌦ never fall through to deleting
  nodes (the graph's selection is the Sketch node being edited). Tests: `swift test --filter CreatorSketchEditorTests`.
- `CreatorApp` + `MetalCreatorApp`: the app shell, the only target joining Graph, Nodes, Viewport and the editors.
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
  and opens, saves and exports. Inside a group `AppModel` reads the level through `editor.graph`/`levelResults`: Selected
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
  (`AppModel.windowChrome`), the window keeps its standard title bar (`.hiddenTitleBar` waits for check AS-5, gap C8-a; `TopBar` already pads by
  `AppLayout.topBarClearance`, zero in a standard window), and
  `App.onOpenURL` is `AppModel.openRequested(_:)` (the path argument goes through `App.open(_:)`; a file that arrives while
  any alert is up is ignored).
  `MetalCreatorApp` is the executable (`OCCTKernel`). It makes the app's `ThemeStore` (`AppThemes.store()`: user
  defaults, `~/Library/Application Support/MetalCreator/Themes`) and its `ThemeEditorModel`, and opens the window on
  `AppWindowRoot`: `AppRoot` with the theme editor (`ThemeEditorDock`, a floating glass panel at the top right) over
  it, the store in the environment and `.theme(current.controlTheme)` for MetalUI's controls. View ▸ Theme is
  `ThemeMenu` (every theme, then Edit Themes…). `LaunchCommand` parses its command line: a file to open, or the
  headless `--help`, `--version`, `--self-test` (`SelfTest`: OCCT, STEP/STL export, MetalUI's shaders) and `--info-plist`.
  `AppBundleInfo` is the version's one source; the packaged `Info.plist` is generated from it, never edited.

Rules: keep OCCT behind `Kernel`; MetalUI gaps are logged in `docs/metalui-gaps.md` and fixed in MetalUI,
never worked around here. Graph links are kept canonically sorted by destination; result caching is keyed by node identity.
Edge/face IDs are OCCT map order. A circle edge's `direction` is its axis, so direction rules must also check `kind == .line`.
All OCCT work runs under `OCCTKernel.serialized` (process-wide lock) because OCCT shapes share geometry across solids and meshing mutates it; never call the shim outside it (tests included).
Edge picks (`EdgePick`) match by tag subsets per side, and a key that matches nothing is retried `EdgeKey.narrowed` (to the operand its edge runs along, so picks on faces a union merged survive the other operand changing); drift counts edges and runs (`EdgePick.runCount`, an optional key, so no format bump; a run is edges that continue each other end to end, ends within 1e-4 mm leaving that point in opposite directions to within 0.01 rad, so two edges meeting at a corner are two runs; a pick without one counts each recorded edge as a run) and warns only when both changed; a key that still matches nothing is split by operand (`EdgeKey.operandKeys`, for an edge between a merged face and a third operand's face) and warns when two operands both fit; selection rules never select seams. Segmented controls bind integer sockets (option index). File format is version 5 (2 added `.edgePicks`; 3 added `loop` on hole-wall side tags, written only when non-zero;
4 added the `.sketch` and `.facePick` settings; 5 added `definitions`, group definitions, optional on decode; canvas comments' `stickies` and `frames` keys, written only when present and optional on decode, are also under 5).
A `Segment2D.arc` with `end < start` runs clockwise (a sketch region's notch); the shim builds it reversed and
`length` is positive. Edges carry `EdgeInfo.curve` (`EdgeCurve`, lines and circles) for sketch projection; a
`FacePick` names faces by tag subset like `EdgePick`; one that matches nothing is retried per operand and ranked by the normal and centroid it recorded (optional keys, no format bump; `Topology.resolution(of:)`), and warns when it can only guess. The Sketch node solves on every evaluation from the stored
sketch's warm start (a constraint or dimension on a projected edge of the wrong kind is skipped and named in a warning,
like one on a suspended edge); the editor writes `Sketch.remember` back into the setting with every commit (S5a). Node readers
of sockets use `inputs(for: node)` (canvas shape and rows, inspector, handles), never the static `inputs`.
`Profile2D` is `outer` + `holes` (loop 0 = outer, n = hole n); `segments` is the outer loop only, so code that
rebuilds a profile must keep `holes` (copy it and change `plane`, don't re-init from `segments`). Side tags are
`.side(loop:segment:)` and `.side(segment:)` means loop 0; never match `.side` with one binding (`case .side(let s)`
binds the tuple and only warns). The shim orients hole wires against the outer wire; history `operand` on segment
records is the loop. Loft refuses profiles with holes, before it compares segment counts (`KernelError.loftWithHoles`).
Create nodes only with `NodeRegistry.makeNode`. Numbers in node and kernel messages use `Locale.messages` (defined in
CreatorKernel; `Double.display`, `Int.display` in CreatorNodes; `KernelError.userMessage` uses it too).
Shim errors: `cocct::user_error` / `set_error` messages are user-facing and unprefixed; any other OCCT exception is prefixed "occt: " by `guarded` and mapped to a generic sentence by `KernelError.plainReason`.
Every fillet and chamfer result is checked with OCCT's `BRepCheck_Analyzer` (`OCCTShape.isValid`) and never returned when
the check rejects it: the blend fails naming the largest size that works (`OCCTKernel.largestValidBlend`, spec Errata
(Kernel: invalid blends)). A blend OCCT can't build names one too, and a checker that itself throws
(`OCCTValidity.unchecked`) gives the generic message with no search (Errata (Kernel: largest size for blends OCCT can't
build)); a refused blend costs tens of milliseconds more than one that works (`BlendRefusalBench`,
`docs/verification/performance.md`).
MetalUI exports its own `Angle`: a file importing both MetalUI and CreatorGeometry writes `CreatorGeometry.Angle`.
The GPU structs in `Sources/CreatorViewport/Render` mirror the MSL in `ViewportShaders.swift`, and `GPUDataTests` pins their strides, so change both together.
The viewport's pointer input is MetalUI C7's (spec §9): its bindings live in `ViewportInputMap`, its behaviour in
`ViewportModel` (`dragChanged`/`dragEnded`, `click(at:)`, `contextMenuItems(at:)`, `scrolled(by:at:phase:)`,
`pinchChanged`, `cursor`), and `ViewportView` only forwards gesture values. Its keys stay window-wide stopgaps in
`ViewportKeyBindings` until MetalUI scopes keys to an element (C9).
Editor geometry is computed by `NodeLayout`, never measured; views are framed to it so
drawing and hit testing agree. Node positions are stored left-to-right; the left dock draws their transpose.
The graph panel's insides (header, node library, canvas) are computed by `GraphPanelLayout` and the palette's size
by `PaletteLayout`; the host says where the panel is in its window through `EditorModel.placement` (the app:
`AppModel.panelPlacement`, from `AppLayout` and the viewport's size; the preview: `PreviewLayout`, a fixed-size
window). The add-node palette floats over the window: the host draws `SearchPaletteOverlay` last (the app inside
`PaletteDock`, for the `Panel` key context), then `LibraryDragOverlay`, never inside the canvas. A library row is a
`PaletteEntryLabel` under one `DragGesture(minimumDistance: 0, coordinateSpace: .global)`
(`GraphPanelInput.libraryGesture(for:)`; not a `Button`, whose click would hold the drag off), and the model tells a
click from a drag (`LibraryDrag.threshold`); never MetalUI drag and drop (it becomes a system drag outside the
window). The library's visibility is `ViewState.showsLibrary` (an optional key: no format bump).
The graph canvas's pointer input is MetalUI C7's, turned into `EditorModel` calls by `GraphPanelInput`: one
`DragGesture(minimumDistance: 0)` for clicks and drags, whose `value.modifiers` the model reads (a `SpatialTapGesture`
has none, gap GI-a; a drag on empty canvas box-selects and never pans), a `DragGesture(minimumDistance: 0, button:
.middle)` (`middlePanGesture()` → `middleDragged`: pans, as the viewport's middle drag does; the user's Gate G answer
(b), 2026-10-09), `.onScrollWheel` (`scrolled(by:at:modifiers:phase:)`: pan, ⌘ zooms) and `MagnifyGesture`
(`pinchChanged`); the cursor is `EditorModel.canvasCursor` (a closed hand while a middle drag pans). Its keys and text
focus are MetalUI C9's: `CanvasSurface` is a `hoverKeyRegion` whose one `onKeyPress` runs the graph's keys
(`GraphPanelInput.keyPressed(_:)`), so with nothing focused they act where the pointer is, a focused field (the inspector's,
the library's, the canvas's comment editor) keeps every key wherever the pointer is, and a canvas press clears a field's focus.
The open palette's ↑/↓ (a keymap action, gap M5-h), its keys on `onInput` and its click-outside (gap EP-b) are the stopgaps
left in `GraphPanelInput`, and `install(on:)` chains onto the window's existing handlers.
The app installs the window's input through `AppInput`, never `GraphPanelInput.install(on:)` (only
`GraphPanelPreview` still uses it), because New and Open replace the document's `GraphPanelInput`.
App-shell input stopgaps live only in `AppInput`: the viewport's keys carry the `!Panel` key context (the graph panel
and the inspector contribute `Panel`), and over the graph canvas F, + and − are declined so the graph's own keys work
(F frames the graph's selection there). The
camera reaches `ViewState` only through `cameraSettled`/`homeChanged`, never per frame. Regular Polygon is
`typeVersion` 2 (`rotation`).

## Commands

```sh
swift build                                  # build the library
swift build -c release
swift test                                   # run all tests
swift test --filter CreatorGraphTests        # one test target (also CreatorOCCTTests, CreatorGeometryTests, CreatorKernelTests, CreatorViewportTests)
swift test --filter CreatorOCCTTests         # kernel conformance + naming stability (needs OCCT)
swift test --filter 'CreatorGraphTests.EvaluatorTests/wiredValuesFlowDownstream'   # one test
swift test --filter CreatorNodesTests        # node definitions through the real Evaluator (OCCT where geometry matters)
swift test --filter BracketAcceptanceTests   # the §7.2 bracket, headless
swift test --filter CreatorViewportTests   # viewport model, maths and the offscreen ID pass (needs a Metal device)
swift run ViewportHarness                  # dev window for docs/verification/human-checks.md group V
swift test --filter CreatorEditorTests       # editor model + headless render tests
swift run GraphPanelPreview                   # graph panel + inspector, for docs/verification/human-checks.md (M5)
swift run MetalCreatorApp [file.mcgraph]   # the app (docs/verification/human-checks.md, group M6)
swift test --filter CreatorAppTests        # app model, scene, handles, picking, files, export, input; AppAcceptanceTests runs §7.2 on OCCT
swift test --filter CreatorStyleTests      # colour themes: built-ins, roles, .mctheme files, the folder, ThemeStore
swift test --filter CreatorSketchEditorTests   # the sketch editor: tools, inference, constraints, dimensions, overlay
scripts/package-app.sh                     # dist/MetalCreator.app: release build, OCCT bundled, signed ad hoc, verified (docs/packaging.md)
scripts/verify-app.sh [path.app]           # re-check a packaged app: signature, no Homebrew links, self-test with Homebrew unreadable
swift run MetalCreatorApp --self-test      # the same headless checks, unpackaged
scripts/bench.sh [suite]                   # spec §7.3 benchmarks, release build; numbers go in docs/verification/performance.md
```

Benchmarks (`Tests/CreatorAppTests/Bench`) are Swift Testing suites that print `BENCH …` lines and assert no time; a
plain `swift test` skips them (`.enabled(if: Bench.isRequested)`), and one run in a debug build records an issue
instead of printing debug numbers (MetalUI draws about 45× slower in debug). Their fixtures (`BenchSamples`,
`BenchRenderer`, `FiftyNodeGraph`, the bracket) are checked in the default run. Measure release, on an idle Mac.

## Linting

SwiftLint is configured in `.swiftlint.yml` (each non-default setting is documented there). Run `swiftlint lint --strict` before committing; it must report zero violations. Prefer fixing the code over adding `swiftlint:disable` comments, and give any disable a reason.

## Toolchain constraints

- `swift-tools-version: 6.4`, `swiftLanguageModes: [.v6]` — full Swift 6 strict concurrency checking is on. Data-race violations are compile **errors**, not warnings. Shared mutable state needs an actor, `Sendable` conformance, or an explicit global-actor annotation; do not reach for `@unchecked Sendable` or `nonisolated(unsafe)` to silence a diagnostic without understanding it.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest. Keep new tests on Swift Testing.
- Local toolchain: Apple Swift 6.4, arm64 macOS.
- Swift 6.4 crashes in SILGen on a key path applied to an existential metatype (`BuiltInNodes.all.map(\.typeID)`); use a closure.
- OpenCascade 7.9 comes from Homebrew (`brew install opencascade`) and is linked from `/opt/homebrew/opt/opencascade`.
  Linker warnings about dylibs built for a newer macOS are expected.
- Adding a `ConstantValue` kind, or any change older readers can't decode, requires bumping `GraphFile.currentFormatVersion`.
