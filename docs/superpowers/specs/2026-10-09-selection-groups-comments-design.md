# Multi-select, node groups and canvas comments — design

Status: approved in conversation 2026-10-09 (sections 1–3); this document is the written spec.
Parent spec: `2026-10-07-metalcreator-vertical-slice-design.md` (its rules hold unless this one says otherwise).
Reference: MetalNodes (`../MetalNodes`, spec `docs/superpowers/specs/2026-09-04-metalnodes-design.md` §11.5, §18,
§20, §21.4), whose groups, sticky notes and comment frames this follows, adapted to a CAD graph.

## 1. Goals

- Select many nodes and act on them as one: the user selects several nodes and presses **⌘G** to group them.
- **Node groups** are reusable sub-graphs: one group node stands for a definition's graph, with inputs and outputs
  taken from the wires that crossed the selection's boundary. Placing a group again shares its definition; editing
  inside updates every instance; Make Unique splits one off.
- **Canvas comments**: sticky notes, and titled frames drawn behind nodes that move the nodes inside them.

Non-goals (this round): align/distribute; select upstream/downstream; typing comments on the canvas (logged, §8);
collapsing a frame; groups across documents (a library of groups); MSL-style "custom code" bodies.

## 2. Sub-projects and order

One spec, separate plans, in this order:

1. **A — Multi-select polish** (§3). First: B and C build on its selection model.
2. **C1 — Groups: model and evaluation** (§4, §5) and **B — Comments** (§7), in parallel (evaluator vs canvas).
3. **C2 — Groups: editor** (§6), after C1.

**File format.** Groups and comments both add data older readers can't decode, so `GraphFile.currentFormatVersion`
goes **4 → 5 once**, in whichever of C1 and B merges first; the other adds its keys under 5. Both new keys are
optional on decode (absent = none), so version-4 files open unchanged.

## 3. Multi-select (A)

Existing: click selects; ⇧-click extends; a drag on empty canvas box-selects (`CanvasInteraction.boxSelecting`);
copy, paste, duplicate, delete and moving act on the selection.

Added:
- **⌘-click toggles** a node in or out of the selection. ⇧ keeps adding; no modifier replaces. A press on an
  already-selected node without movement collapses the selection to it (⌘: toggles it), so ⌘-drag still moves the
  selection. Modifiers come from the press's drag value (MetalUI C7, `GraphPanelInput`).
- **Box select modes**: no modifier replaces, ⇧ adds, ⌘ toggles each node it covers. It selects nodes **and
  comments** whose rectangles intersect it (comments once B lands).
- **⌘A selects all** nodes and comments on the current level, bound so a focused text field keeps ⌘A.
- **Esc clears** the selection (after closing the palette, ending a wire drag, or cancelling a pick, as today).
- **Arrow keys nudge** the selection 1 pt, ⇧ 10 pt, as one undo step per key-down run (coalesced like slider drags).
- **F frames the selection** in the graph canvas when the pointer is over it (the viewport's F is unchanged).
- **Mixed drags**: dragging any selected item moves every selected node and comment together (MetalNodes leaves
  selected comments behind; we don't). ⌥-drag duplicates the whole selection, deferred until the pointer moves.
- Selection stays view state: never undone, not saved (as today).
- Selected items draw last and are hit-tested in the same order (existing rule).

## 4. Groups: data model (C1)

```swift
public struct GroupID: Hashable, Sendable, Codable          // UUID
public struct GroupDefinition: Sendable, Codable, Equatable {
    public let id: GroupID
    public var name: String                                   // unique in the document, e.g. "Rib"
    public var accent: AccentRole                              // a theme accent role (§7)
    public var inputs: [SocketSpec]                            // ordered; names unique
    public var outputs: [SocketSpec]
    public var graph: Graph                                    // nodes, links, comments (B) of the inside
}
```

- `GraphFile` gains `definitions: [GroupID: GroupDefinition]` (encoded sorted by id).
- A **group node** is an ordinary `Node` of type `group` whose `groupID` setting names its definition. Its sockets are
  the definition's (per-node sockets through `NodeDefinition.inputs(for:)`/`outputs(for:)`, as the Sketch node's
  exposed dimensions already are); unwired inputs keep typed values in `inputValues` like any node.
- Inside a definition, a **Group Input** node (outputs = the definition's inputs) and a **Group Output** node
  (inputs = the definition's outputs) stand for the boundary. Exactly one of each; neither can be deleted or copied.
- **Nesting** is allowed. A definition may not contain, directly or through other groups, an instance of itself:
  any command that would create such a cycle is refused (`GroupDependencies.wouldRecurse`).
- An **Output** node (`.output` category) may not be inside a group: the part's outputs live on the top level.
- `NodeRegistry.makeNode` builds group nodes too (registry entry `group`), so the "create nodes only through the
  registry" rule holds.

## 5. Groups: evaluation, naming, commands (C1)

**Evaluation.**
- A group node evaluates its definition's graph with Group Input's outputs bound to the node's resolved inputs (wire,
  else typed value, else the socket's default), and its outputs taken from Group Output's inputs.
- **Values pass through unchanged**: a list wired in reaches the nodes inside as a list, and they broadcast over it
  as they would at top level. The group node itself does not broadcast.
- Results are **cached per instance path** (`[NodeID]` from the top level down to the inner node), so instances never
  share entries; editing a definition invalidates every instance's entries for it.
- Cancellation stays at node boundaries, which now include nodes inside groups.
- A failed inner node makes the group node fail with the inner message prefixed by the inner node's path
  ("Rib › Fillet: …"); warnings bubble up the same way.

**Naming.** Tags name their producing node by `NodeID` (`NodeTag`, `TopoTag`). Two instances of a definition hold
the same inner nodes, so their tags would collide once their solids meet. Inside a group, each inner node evaluates
under a **scoped `NodeID`**: a name-based (deterministic) UUID derived from the instance path and the inner node's id.
- Tags, `EdgePick`, `FacePick` and saved files keep their shape (no format change for picks).
- The same inner node in two instances yields different tags; a pick made outside a group on an instance's geometry
  keeps resolving when the definition is edited (inner ids are stable) and is distinct per instance.
- Ungroup and Make Unique give nodes new ids, so picks across them follow the existing drift rules (warn, re-derive by
  rule); this is stated in the commands' messages where it applies.
- Naming-stability tests: two instances of a "rib" definition unioned with a plate, a fillet picked on each, edit the
  definition (rib height), both picks still resolve; Make Unique, edit one, the other's pick is untouched.

**Commands** (each one `DocumentModel.perform` step, undoable, as one batch):
- **Group** (⌘G, or Group in the context menu; a selection of one or more nodes on the current level — usually
  several, but one is allowed, as in MetalNodes):
  - Refused, with a plain message, for: an empty selection; Group Input/Output nodes; an Output node ("An Output node
    can't go in a group."); a selection whose boundary socket type can't be resolved.
  - Moves the selected nodes into a new definition "Group", "Group 2"…, positions relative to the selection's
    top-left. Links among them move with them.
  - Each distinct external source feeding the selection becomes **one input socket** (named after the target socket,
    made unique); each distinct internal source wired out becomes **one output socket**.
  - Places the group node at the selection's top-left, rewires the boundary to it, and selects it.
- **Ungroup** (⇧⌘G, one group node): splices the definition's nodes back with fresh ids, rewires through the
  boundary, writes typed values from unwired group inputs onto the inner targets, handles Group Input wired straight to
  Group Output, and selects the spliced nodes. The definition stays if other instances use it.
- **Make Unique**: copies the definition as "Name 2" and points this instance at the copy.
- **Rename**, **set accent**, **add / rename / reorder / remove socket**: definition edits. Removing a socket that any
  instance has wired is refused, naming the instance.
- **Delete definition**: only when no instance uses it.
- **Edits inside a definition** are the existing graph commands addressed to a **graph path** (top level, or a
  definition id); undo covers them like any edit.

## 6. Groups: editor (C2)

- **Look**: a group node is drawn like a node with a doubled accent border; header = definition name.
- **Entering**: double-click the group node, ⌘↓, or "Edit Group" in its inspector. MetalUI gives the canvas no
  double-click (gap GI-a), so `EditorModel` recognises two primary clicks within 0.4 s and 4 pt with no modifiers.
- **Breadcrumbs** in the graph panel header: "Graph › Rib › Hole pattern"; a click on a level, or ⌘↑, goes back out.
  Each level remembers its pan and zoom (view state); the selection clears on changing level.
- **Inside**: Group Input and Group Output carry a **+ socket**. Dropping a wire on Group Output's + exposes a new
  output; dragging from Group Input's + onto an input exposes a new input. One undo step each.
- **Inspector**: group node — name, accent, "Used N times", Edit Group, Make Unique, Ungroup; Group Input/Output —
  the socket list (rename, reorder, remove).
- **Library**: a "Groups" section lists the document's definitions; click or drag places another instance; a
  definition with no instances offers Delete.
- **Viewport**: inside a group, Preview "Selected node", handles and picking work on the level shown; Final preview
  shows the whole part as always.

## 7. Comments (B)

```swift
public struct StickyNote: Sendable, Codable, Equatable { id, text: String, frame: CanvasRect, accent: AccentRole }
public struct CommentFrame: Sendable, Codable, Equatable { id, title: String, frame: CanvasRect, accent: AccentRole }
```
- Stored per `Graph` (`stickies`, `frames`), so a definition's inside has its own. Encoded sorted by id; keys optional
  on decode. Comments never affect evaluation; their edits don't re-evaluate.
- **Accent**: `AccentRole` (cyan, green, orange, pink, purple, yellow, muted), shared with group definitions (§4) and
  drawn from the current theme's roles.
- **Add Note** (⌘⇧N, or the context menu at the pointer): 160 × 100, text "Note", muted; selected.
- **Frame Selection** (⌘⇧C, context menu): the selection's bounds padded 24 pt plus a 22 pt title bar, title "Frame";
  disabled with nothing selected; selected.
- **Frame membership is geometric**: the nodes whose centres lie inside the frame. Dragging a frame (by its title
  bar) moves it and its members as one step. Deleting a frame keeps its nodes. Nothing about membership is stored.
- **Hit-testing**: a note hits on its whole rectangle; a frame only on its title bar and a 6 pt inner edge band, so
  nodes and box select inside it still work. Notes beat frames.
- **Draw order**: frames → wires → notes → nodes; selected items last; hit-testing matches.
- **Resize**: a bottom-right handle when selected; top-left fixed; minimum 80 × 40.
- **Selection, clipboard, undo**: comments join box select, ⌘A, copy/cut/paste/duplicate, delete and mixed drags
  (§3); every change is one undo step ("Add Note", "Edit Note", "Add Frame", "Move", "Resize", "Delete").
- **Editing**: with one comment selected, the inspector edits its text (multi-line; commits on focus loss or ⌘↩) or
  title (commits on Return; empty refused) and accent; with several, "N comments selected".
- No shadows (PERF-a); views stay cheap (PERF-b).

## 8. MetalUI gaps and follow-ups

- **Canvas double-click** (GI-a, MetalUI C16): `EditorModel` synthesises it until MetalUI offers one.
- **Typing comments on the canvas** waits for MetalUI C9 (key and focus scoping) and the canvas double-click; logged
  as a roadmap row. Until then: inspector editing.
- Any new gap found while building is logged in `docs/metalui-gaps.md` and sent to the MetalUI session.

## 9. Testing

- Model tests (Swift Testing) for every command and refusal, selection mode, nudge coalescing, frame membership,
  hit-test order, clipboard round trips (groups referenced by pasted nodes travel with them, merged by content),
  undo/redo of each command, and format-5 encode/decode plus version-4 files opening unchanged.
- Evaluation tests: group results equal the ungrouped graph's (same volume and topology) for the §7.2 bracket's rib
  grouped; lists pass through; nested groups; cycle refusal; per-instance caching and invalidation.
- Naming-stability tests as in §5.
- Render tests for group borders, breadcrumbs, notes, frames and draw order.
- Human checks: new groups GR (groups) and CM (comments), and additions to group GI for selection (A).

## 10. Roadmap

Rows: "Multi-select polish (A)", "Groups: model and evaluation (C1)", "Comments (B)", "Groups: editor (C2)",
"Comments: typing on the canvas (after MetalUI C9 + canvas double-click)".

## Errata (A: multi-select)

Plan `2026-10-09-multi-select.md`.

- Box select, as the user decided on 2026-10-09 (Gate G, answer (b)): §3 holds, and the parent §6.2's "A plain drag on
  empty canvas pans" no longer does. Every drag that starts on empty canvas box-selects; the modifiers held when the
  drag starts (crosses the drag threshold, as ⌥-duplicate's are) fix its mode for the whole drag: none replaces the
  selection, ⇧ adds, ⌘ toggles each node it covers (⌘ wins over ⇧). It is recomputed from the selection it began
  with at every step. Panning is two-finger scroll (as before) and the middle mouse button (the user: "pan with two
  fingers or the middle mouse button"), as in the viewport: a middle drag pans wherever it starts, nodes included,
  and never selects or moves; a primary press ends it. Space-drag isn't a pan (Space opens the palette). Pinned:
  `BoxSelectModeTests`, `MiddlePanTests`.
- §3's "⇧ keeps adding": a ⇧-click on a selected node now keeps it (before, it removed it); ⌘-click toggles; ⌘ wins
  when both are held. A drag on an unselected node with ⇧ or ⌘ adds it, then moves the whole selection.
- ⌘A, the arrows and F act only while the panel is visible (with it hidden, ⌘A then Delete would erase nodes no one
  can see), and pass the key on otherwise. A focused field keeps all three (they come from the window's `onInput`
  fallback). During a drag all three are claimed and do nothing, so a move stays one undo step.
- Esc also drops ⌥-drag ghosts and cancels a box (putting back the selection it began with); during a pan or a move
  it is claimed and does nothing, so it can't split the move's undo step. The rest of a cancelled press is ignored.
- F over the graph canvas frames the selection, or every node when nothing (still on the canvas) is selected, with
  40 screen points of padding, the zoom within 25–300%. `AppInput` declines the viewport's F (as it did + and −) while
  the pointer is over the canvas.
- Arrows nudge 1 canvas point (⇧ 10) the way they point on screen (the left dock's transpose is undone). A key-down
  that isn't an auto-repeat starts a new undo step; anything that ends coalescing (a press, a selection change, Undo)
  also does.
- The selection model B extends: `CanvasSelection` (B adds `comments: Set<CommentID>`), `SelectionPositions` (B adds
  `comments: [CommentID: Vector2]`), and `EditorModel`'s `allItems`, `items(for:)`, `items(intersecting:)`,
  `positions(of:)`, `moveCommands(from:by:)`, `bounds(of:)`, `clipboard(of:)`, `insert(_:offset:)` and
  `deleteSelection()`. Assigning `EditorModel.selection` selects exactly those nodes and no comments. Drags reach
  items only through `items(for:)`, so comment hits select and move without a pointer change; B's other edits are a
  frame's resize drag (its hit case before `items(for:)`, its `CanvasInteraction` case in `update`, `pointerReleased`
  and `cancelInteraction()`) and comment ghosts in `CanvasLayers.ghosts`.
- Graph keys still act in sketch mode, as Delete and ⌘C do: arrows nudge the Sketch node and ⌘A selects every node.

## Errata (C1)

Plan `2026-10-09-groups-core.md`.

- §4 "per-node sockets through `NodeDefinition.inputs(for:)`/`outputs(for:)`": a node definition's static methods
  can't see the document's definitions, so a node's sockets are read through `NodeRegistry.inputs(for:)`/
  `outputs(for:)`, which give group nodes, Group Input and Group Output their definition's sockets (the registry
  carries the document's definitions, `DocumentModel.registry`) and every other node `NodeDefinition.inputs(for:)`/
  `outputs(for:)` (the latter added here). Group Input and Group Output also carry `NodeSetting.group`.
- §4 "registry entry `group`": the three group types live in `CreatorGraph` (the evaluator and the commands need
  them, and `CreatorEditor` can't import `CreatorNodes`), and every `NodeRegistry` registers them itself; the palette
  and the library don't list them.
- §4 Group Output's inputs are optional: an unwired one is an output the group node doesn't produce.
- §5 Naming: a pick stored inside a definition names faces as if the definition were the top level (its own nodes
  by ID, nodes inside its group nodes by `NodeID.scoped` of the path from it), and each instance reads it as its own
  (`EvaluationScope.naming`), so a sub-graph with a picked fillet works in every instance.
- §5 Naming (a change to §5 the user approved on 2026-10-09): Group, Ungroup and Make Unique change the names faces
  are made under, and each renames, in the same undo step, every pick in the document that names a face of the nodes
  it moves (`GroupScopes.renamingPicks`), inside the moved nodes too. So no pick drifts across them, and there is no message to state ("picks across them
  follow the existing drift rules … stated in the commands' messages" no longer applies; `GroupEdit` has no notice).
- §4/§5 A definition's new interface is refused, after the whole command, when it removes a socket, or gives it
  another type, while a wire is still on it: on a group node, or inside on Group Input or Group Output.
- §5 Ungroup removes the definition with its last group node; Make Unique also renames its group node to the
  copy's name; renaming a definition renames the group nodes still named after it.
- §5 ⌘G and ⇧⌘G (`EditorModel.groupSelection`/`ungroupSelection`) act on the top level until C2 shows a
  definition's inside.
- §5 Group is also refused when a node outside the selection both takes from it and feeds it ("These nodes can't
  be grouped: a node outside the selection both takes from them and feeds them."): the group node would be wired in a
  cycle, which wiring refuses. Applies at a definition's path too.
- §2 The file format went 4 → 5 here; comments (B) add their keys under 5.

## Errata (B: comments)

Plan `2026-10-09-comments.md`.

- §7 `CanvasRect` moved from `CreatorEditor` to `CreatorGraph` (Codable), because a `Graph` stores it. A note and a
  frame share one `CommentID` namespace (a selection or a hit names a comment without its kind), and a graph holds an
  ID in at most one of `stickies` and `frames`; a decoded repeat keeps the first.
- §2 Older builds: a build that predates comments ignores the two keys on open and so drops the comments on its next
  save (they are optional under version 5, with no bump, as the spec asks). Ungroup splices a definition's own comments into the level (User decision 8, (b)).
- §7 Storage: the keys are written only when a graph has comments (a graph without any is written exactly as before),
  sorted by ID; an unknown accent reads as muted. A comment's `frame` is stored in left-to-right canvas points like a
  node's position, and the left dock draws the transpose of its origin and size, so a frame stays around the nodes it
  held when the dock changes.
- §7 Commands: `GraphCommand` gains `setSticky`, `removeSticky`, `setFrame`, `removeFrame`. A set adds or replaces the
  comment whole, so a move, a resize, a text, title or accent edit is one command carrying the new value, and its
  inverse the old; all four have `affectsResults == false` and touch no node.
- §7 "Undo names" ('Add Note', 'Edit Note', …): MetalCreator's undo history has no step names (the menu says "Undo"),
  so each change is pinned as exactly one undo step; showing names is a separate change to `UndoStack` and the menus.
- §7 Frame membership is read from drawn centres when a move begins, and a nudge carries it too; ⌥-drag and copy/paste
  of a frame take the frame alone. Only nodes are carried, not notes lying inside a frame.
- §3/§7 Box select: a note is taken when its rectangle meets the box, a frame only when the box meets its chrome (its
  title bar or edge band), so a box drawn among the nodes inside a frame does not select the frame.
- §7 Hit-testing: a node (or socket) beats any comment, a note beats a frame, and the selected raise within their
  kind. A selected comment's 12 pt bottom-right handle is `CanvasHit.resize`, tested before the comment's own body.
- §7 Add Note: ⌘⇧N places the note's top-left at the pointer when it is over the canvas, else centres it on the visible
  canvas; the context menu places it at the point it opened. Frame Selection frames `bounds(of: canvasSelection)`, so
  it can frame comments too. ⌘C with ⇧ is Frame Selection, and ⌘X (cut: copy, then one delete step) is new.
- §7 Editing: a note's text commits on focus loss (not on ⌘↩: MetalUI's `TextEditor` has no commit key, gap CM-a, and
  a chord would work around it), a frame's title on Return and on focus loss, both also on any model commit (a canvas
  press, a selection change); an empty or blank title is refused ("A frame needs a title.") and the field shows the
  old one. The inspector's comment page shows only when no node is selected.
- §7 Draw: the accent roles map to theme colours in `Palette.accent(_:)` (cyan Output's header, green Profile's,
  orange Feature's, pink Selection's, purple Solid's, yellow the warning colour, muted Value's), which group
  definitions (C2) use too. Selected comments draw a 2 pt accent ring; the ⌥-drag ghosts of comments are
  `CanvasLayers.commentGhosts`, beside the nodes' `ghosts`.
- §7 Comments and groups: comments belong to the level (a graph or a definition's inside) they are on. Group leaves
  the level's comments where they are; Make Unique copies the definition's own comments with it; Ungroup splices them
  into the level it ungroups into, offset like the nodes, in the same undo step (User decision 8, (b); one undo takes
  them back out and restores the definition). A
  negative size in a hand-edited file reads as zero.

## Errata (C2)

Plan `2026-10-09-groups-editor.md`.

- §6 "Entering" and "Breadcrumbs": a level is the group nodes entered from the top level (`EditorModel.levelPath`, each
  by its ID in the graph before it), not a definition, so a definition used twice shows the entered instance's states
  (`DocumentModel.innerResults` is keyed by instance path). `EditorModel.graph` is the level's graph and
  `EditorModel.edit(_:)` addresses its path; the document's parameters stay on the top level and show at every level.
  Each level remembers its pan and zoom while the document is open (not saved, not undone); a level entered for the
  first time frames its nodes. Undo or Redo that removes the group node entered drops the panel to the level around it
  (`refreshLevel()`).
- §6 "Entering": Edit Group, Make Unique and Ungroup are the group node's inspector buttons (`InspectorAction.editGroup`,
  `.makeUnique`, `.ungroup`, declared by `GroupNode.inspector`), carried out by the graph panel itself and never
  recorded for the app shell. S5b's double-click recogniser presses the first of `doubleClickActions` ([.editSketch,
  .editGroup]) a node's inspector has, and now runs after the click it ends on, so a click that enters a group
  doesn't select its group node inside. ⌘↓ and ⌘↑ are `GraphKeyCommand.enterGroup`/`.exitGroup`.
- §6 "Inside": the "+" is a socket named `GroupNaming.plusSocket` ("+", reserved: no socket of a definition may have
  it) at the end of Group Input's outputs and Group Output's inputs. A wire dragged between it and another socket,
  either way round, exposes the socket (`GroupCommands.exposeOutput`, `exposeInput`): the new output or input is named
  after the socket and typed from it, an input keeps its target's unit, range and default, and the socket and its wire
  are one command, so one undo step. Any other pairing with a "+" is refused with a hint.
- §6 "Inside": Group Input and Group Output cannot be copied, duplicated or deleted (Delete with only them selected
  says why); they can be moved.
- §6 "Inspector": the definition part shows name, accent and "Used N times" ("Used 1 time") for a group node, Group
  Input or Group Output; the socket list (rename, move up or down, remove) for Group Input and Group Output. Removing
  a socket a group node has wired is refused naming that node (`GroupCommands.removeSocket`).
- §6 "Library": the "Groups" section lists the definitions that match the library's search; a group row carries the
  key "group:<uuid>" through the library's one gesture in place of a node type's ID. A definition no group node uses
  shows Delete. Placing a group inside itself is refused ("A group can't contain itself.").
- §6 "Viewport": while a level is shown the document evaluates all of it (`DocumentModel.inspectedLevel`,
  `Evaluator.evaluate(_:definitions:demand:inspecting:)`), so every inner node has a state in `innerResults` and
  Selected node previews any of them, also one nothing reads; a node asked for this way never changes its group
  node's result. Handles and picking read the level's graph and results (a pick starts from a node of the level, never
  a top-level endpoint or Group Output). A pick is written through
  `GraphContent.relativeToLevel`, which renames the tags naming this instance's identities to the names the
  definition uses; tags naming nodes outside the level stay as they are. A pick under way is cancelled by showing
  another level. Final preview shows the Output nodes of the top level whichever level is shown. An open sketch
  holds the level shown: entering or leaving does nothing until it closes (`EditorModel.isLevelLocked`).
- §6 "Viewport": editing a sketch inside a group is not supported yet: "Edit sketch" there says so. Sketch mode reads
  the top level's graph throughout, and sub-project S5c rewrites it.
- §9 "Clipboard": `NodeClipboard.definitions` holds every definition the copied group nodes use, however deep
  (`GroupMerge.definitions(used:in:)`). On paste (`GroupMerge.plan(importing:into:)`) a definition that some
  definition of the document equals, ignoring ID and name (accent, sockets and inside), is reused, whatever its ID or
  name (the original, a rename of it, or the copy an earlier paste added, so pasting the same clipboard twice adds
  one copy at most), one the document has no match for is added as it is, and one whose ID is taken by other content,
  or whose name is taken, comes in as a copy "Name (imported)" (a fresh ID when the ID was taken), with the pasted
  group nodes, and any definition placing it, retargeted. The additions and the nodes are one undo step.

User decisions (C2), all 15 of the plan's "User decisions" decided as the recommended defaults (approved 2026-10-09/10):

1. Sketches inside a group: "Edit sketch" refuses until S5c lands.
2. The level shown and per-level pan and zoom are not saved.
3. No mouse way to Group yet: keys only (⌘G, ⇧⌘G) and the group node's Ungroup button.
4. A dropped "+" names the socket after its source or target (made unique); an input keeps the target's unit, range,
   default, access and optional.
5. The whole level shown is evaluated.
6. Esc never leaves a group; ⌘↑ and the breadcrumbs do.
7. Copies of a changed definition on paste are named "Name (imported)".
8. "Used 1 time" for one, "Used 0 times" for none.
9. The accent picker is a menu of the seven role names.
10. A rename alone never makes a copy on paste.
11. Group Input and Group Output can't be copied, duplicated or deleted.
12. A pick under way is cancelled when the level changes.
13. Undo and Redo may change something inside a level that isn't shown.
14. The double-click recogniser runs after the click it ends on: double-click selects the group node, then opens it,
    so the selection clears on entry. For a Sketch node this changes S5b's order: the node is now selected first and
    the sketch opens second (`EditorModel+Pointer.swift`: `pairClick` after `click`). The sketcher-s5c owner must
    know before merging.
15. Groups are not in the palette (Space), only in the library.
