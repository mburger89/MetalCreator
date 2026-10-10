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
  are made under, and each renames, in the same
  undo step, every pick in the document that names a face of the nodes it moves (`GroupScopes.renamingPicks`),
  inside the moved nodes too. So no pick drifts across them, and there is no message to state ("picks across them
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
