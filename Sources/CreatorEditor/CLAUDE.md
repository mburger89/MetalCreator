# CreatorEditor (the graph panel and inspector)

Notes for this module, moved from the root `CLAUDE.md` (which Claude Code loads in every session) so they load only when work touches this folder. The project-wide rules, commands and toolchain notes stay in the root file.

Editor polish (the floating add-node palette and the node library) code is done; its human checks (group EP) are pending.

Multi-select polish (sub-project A of `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md`) code is
done; its human checks (group MS) are pending.
MetalUI C10's looks and controls are adopted (plan `docs/superpowers/plans/2026-10-09-adopt-c10.md`; human checks group C10
pending): the inspector's sliders end an undo step with `Slider(onEditingChanged:)` (`EditorModel.sliderEditingChanged(_:)`),
a refused node shakes with `keyframeAnimator` (`RefusalShake`, `EditorModel.shakeCount(of:)`), an evaluating node's badge is
a `ProgressView`, the preview window's background is a `LinearGradient` (`WindowBackground`), and the glass panels kept the
theme's flat tint until MetalUI C21 gave materials a backdrop blur (next paragraph).

Canvas comments (sub-project B of the same spec, §7: sticky notes and comment frames, plan `2026-10-09-comments.md`)
code is done; its human checks (group CM) are pending.
Cable ties (wire bundling in the graph editor: spec `docs/superpowers/specs/2026-10-26-cable-ties-design.md`, plan
`docs/superpowers/plans/2026-10-26-cable-ties.md`) code is done; its human checks (group TIE) are pending.

Typing on the canvas (spec §8: a double click on a note or a frame's title bar edits it in place; plan
`2026-10-10-comments-canvas-typing.md`; the graph's keys and text focus on MetalUI C9's key regions) code is done; its human
checks (group CT) are pending. The field opens with a frame's title all selected and a note's caret at its end (MetalUI C25,
gap CT-b adopted by plan `2026-10-12-adopt-c25.md`; checks C25 pending). The canvas's node, wire and comment views skip their content while unchanged (MetalUI C14
slice 1, gap PERF-b partly fixed, plan `2026-10-13-adopt-c14.md`; checks C14 pending).

Groups C2 (the editor, §6: entering a group, breadcrumbs, the + sockets, the group inspector, the library's Groups
section, the viewport and the clipboard inside groups) code is done; its human checks (group GR) are pending.

- `CreatorEditor`: the graph panel and context inspector on MetalUI. `@MainActor @Observable EditorModel` holds all
  behaviour (selection, canvas transform, dock transpose, hit testing, wiring, clipboard, palette, inspector edits);
  views are thin MetalUI `Component`s. Depends on Graph/Kernel/Geometry, CreatorStyle and MetalUI — **not** on `CreatorNodes`.
  Its input (MetalUI C7 gestures, C9 key scoping, C16 click counts and cancellation, and the palette's stopgaps) lives only
  in `GraphPanelInput`. A double click on a node (a plain second click on its body that the platform counts 2:
  `DragGesture.Value.clickCount`, so the user's double-click speed decides, not a time of ours; gap S5-b) presses its first
  inspector button in `doubleClickActions` ("Edit sketch"; `nodeDoubleClicked(_:)`); the same on a note or a frame's title
  bar, not its edge band (a `ClickTarget`, kept in `lastClick` by the first click), starts editing it in place
  (`beginEditing(_:)`). While a sketch is open the app ignores it (`AppModel.handle(_:)`'s guard).
  The canvas builds only what can show (`EditorModel.drawnNodes`, `drawnCanvasRect`: the visible canvas grown by
  `cullingMargin`, everything while unplaced), and below zoom `rowsMinimumZoom` draws nodes without their rows
  (`drawsNodeRows`); hit testing, selection and edits always see the whole graph. A
  `ForEach` over nodes keys them `id: \.id.rawValue` (the whole UUID; a `NodeID` prints only 8 hex digits, and before
  MetalUI C20 a `ForEach` named elements by their description: gap M7-a, fixed). The graph panel measures itself: `GraphPanel`'s
  `onGeometryChange` writes `EditorModel.panelPlacement` (its frame in the window and `\.windowSize`, gaps EP-a and M4-a),
  tracked, so a resize or a move rebuilds the canvas; nothing computes the panel's place from `AppLayout`.
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
  Data trees show in two places (`EditorModel+TreeDisplay`): a socket carrying a tree has a tooltip, "Tree 3 × 8"
  (`socketHelp(of:)`, shown by `CanvasSurface`'s model-driven `.help` through `socketTip(at:)`, MetalUI #237), and the inspector gets a "Data" section (`TreeShapeRow`: the shape, and a
  list of branch paths with item counts that `toggleShapeList(_:)` opens, cut after 50) only when the node has a tree on
  an input or output. A `.text` setting (the Path Mapper's rule, Branch by Path's and List Item's paths) is an `InspectorControl.text`.
  Fields show the same way: a socket carrying a field has a tooltip with its recipe cut to 80 characters (`Value.fieldSummary(limit:)`,
  "3 fields" for a list), and a node with a field output gets a last "Field" section (`InspectorRow.recipe`, which puts the text
  under its label so a long recipe wraps; `InspectorBuilder.fieldSection`). A field socket's dot borrows the Feature header colour
  (`Palette.header(for: .fields)`) until the theme has a role of its own. A node's `InspectorControl.note(_:)` is a line of help
  (Field Scatter's note on renumbering), shown as an `InspectorRow.recipe(label: "Note", …)`.
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
  `commitCommentEdit`, `cancelCommentEdit`, `commentSelectionChanged`), so a canvas press, a selection or level change, hiding the panel, undo, save
  and export commit it, as one `setNoteText` / `setFrameTitle` step (the inspector's own paths), and a field typed into
  elsewhere (`notePendingEntry`) commits it first. `CommentEditorLayer` draws the field (`CommentEditorField`: a
  `TextEditor`, ⌘↩ commits, or a `TextField`, Return commits; Esc cancels; losing focus commits; both bind
  `CommentEdit.selection`, which `beginEditing` sets to the whole title or the end of the note, `Kind.openingSelection(in:)`,
  and the field writes back, `commentSelectionChanged`; read it as Character offsets with `selectedOffsets`) under the canvas's own
  zoom and pan, as the sibling of `CanvasSurface`, the canvas's key region: never inside it, or the field's keys would
  reach the canvas's handler. Comment views draw no shadows and few rects (`StickyView`, `CommentFrameView`). Make Unique copies a definition's
  comments (`GroupCommands+MakeUnique`); Ungroup splices them into the level. ⌘A, arrows (one undo step per key-down run) and F act only while the
  panel shows; Esc closes the palette, then cancels a drag, then clears the selection.
  Cable ties (`CableTie`, `TieID`: `Sources/CreatorGraph/Ties`; spec 2026-10-26): per `Graph` (`ties`), saved sorted by ID with
  each tie's wires sorted and only when present (format 9), edited by `setTie` and `removeTie` (no evaluation). A wire is its input
  endpoint (`Link.to`); a tie holds two or more wires that are links (`Graph.apply` refuses otherwise; decoding repairs). `removeNode`,
  `disconnect` and a replacing `connect` strip their wires from ties in the same command (`Graph.stripTies`), and their inverse is
  `.batch([old inverse] + setTie(old)…)` only when a tie was reached. Group moves a tie inside when all its wires go, Ungroup brings a
  definition's ties out remapped, Make Unique copies them. The editor's geometry is `WireRouting` (pure: `WireRoute`, the taut chain of
  `WireGeometry` pieces through each tie's lane, ties met by stored `position.x` then ID; `TieLayout`, lanes 4 pt apart across the flow
  and the 6 pt band), read by drawing, hit testing (`CanvasHit.tie`/`.wire`: socket, tie, node, note, wire, frame), boxes (an ⌥-box
  selects wires only, `CanvasInteraction.wireBoxSelecting`; a plain box picks ties whose band is inside), culling and ⌘⇧T
  (`GraphKeyCommand.tieWires`, `EditorModel+Ties`, positioned at `wirePickPoints`). `CanvasSelection` holds `wires` and `ties`. The slack
  is `WireMotion` (a closed-form `WireSpring` per piece, kicked only by moves through `withWireSlack`), drawn by `WireLayer` inside
  `TimelineView(.animation)` only while `isWireMotionActive`; `reducesMotion` (from `@Environment(\.accessibilityReduceMotion)`,
  `CanvasLayers`) stops it. Draw order: frames, wires, tie bands, notes, nodes.

Editor geometry is computed by `NodeLayout`, never measured; views are framed to it so
drawing and hit testing agree. Node positions are stored left-to-right; the left dock draws their transpose.
The graph panel's insides (header, node library, canvas) are computed by `GraphPanelLayout` and the palette's size
by `PaletteLayout`; the panel says where it is in its window itself (`EditorModel.panelPlacement`, from `onGeometryChange`;
`AppModel.panelPlacement` forwards it; tests that draw one cold `renderFrame` run no layout callbacks and set it with
`ExpectedLayout.place`). The add-node palette floats over the window as MetalUI's `anchoredOverlay` (gap EP-b), opening at the
pointer's window point (`EditorModel.pointerWindowLocation`, the canvas container's `.global` hover): the host draws
`SearchPaletteOverlay` last (the app inside `PaletteDock`, for the `Panel` key context), then `LibraryDragOverlay`, never
inside the canvas. MetalUI places it (flip and clamp), closes it (any outside press, Escape) and keeps presses and the wheel
on it from what lies beneath; the model holds no palette geometry. A library row is a
`PaletteEntryLabel` under one `DragGesture(minimumDistance: 0, coordinateSpace: .global)`
(`GraphPanelInput.libraryGesture(for:)`; not a `Button`, whose click would hold the drag off), and the model tells a
click from a drag (`LibraryDrag.threshold`); never MetalUI drag and drop (it becomes a system drag outside the
window). The library's visibility is `ViewState.showsLibrary` (an optional key: no format bump).
The graph canvas's pointer input is MetalUI C7's, turned into `EditorModel` calls by `GraphPanelInput`: one
`DragGesture(minimumDistance: 0)` for clicks and drags, whose `value.modifiers` and `value.clickCount` the model reads (it
stays a drag though a `SpatialTapGesture` carries modifiers since C16, gap GI-a: a press must be able to become a box, a wire
or a move; a drag on empty canvas box-selects and never pans; a press MetalUI drops ends through `onCancelled` →
`pointerCancelled()`), a `DragGesture(minimumDistance: 0, button:
.middle)` (`middlePanGesture()` → `middleDragged`: pans, as the viewport's middle drag does; the user's Gate G answer
(b), 2026-10-09), `.onScrollWheel` (`scrolled(by:at:modifiers:phase:)`: pan, ⌘ zooms; MetalUI latches a scroll to where it
began, glide included, gap GI-b) and `MagnifyGesture`
(`pinchChanged`/`pinchEnded`); the cursor is `EditorModel.canvasCursor` (a closed hand while a middle drag pans). Its keys and text
focus are MetalUI C9's: `CanvasSurface` is a `hoverKeyRegion` whose one `onKeyPress` runs the graph's keys
(`GraphPanelInput.keyPressed(_:)`), so with nothing focused they act where the pointer is, a focused field (the inspector's,
the library's, the canvas's comment editor) keeps every key wherever the pointer is, and a canvas press clears a field's focus.
A press anywhere else does too: `AppWindowRoot` (and `GraphPanelPreview`'s root) carries MetalUI C24's `.resignsFocusOnPress()`
(gap CT-a), which resigns on a primary press on inert chrome, the viewport included, and routes no keys; it is why a canvas edit
and a typed inspector value end, committing through their focus-loss handlers, on a press on the glass, a header gap or the
viewport. The shell has no `window.focus(nil)` hook of its own any more; a viewport press only commits a pending entry.
The open palette's ↑/↓ (a keymap action, gap M5-h) and its keys on `onInput` are the stopgap left in `GraphPanelInput`, and
`install(on:)` chains onto the window's existing handlers.
