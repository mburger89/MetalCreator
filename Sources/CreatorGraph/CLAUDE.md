# CreatorGraph

Notes for this module, moved from the root `CLAUDE.md` (which Claude Code loads in every session) so they load only when work touches this folder. The project-wide rules, commands and toolchain notes stay in the root file.

Groups C1 (model and evaluation, `docs/superpowers/specs/2026-10-09-selection-groups-comments-design.md` §4–§5) is done.

Named undo steps (plan `docs/superpowers/plans/2026-10-10-named-undo.md`) code is done; its human checks (group NU) are pending.
Final-review follow-ups (plans `docs/superpowers/plans/2026-10-10-followups-app.md`, `2026-10-10-followups-editor.md` and
`2026-10-10-followups-kernel.md`) code is done; the app track's human checks (group FA) are pending.
Data trees (sub-project 7a-1: spec `docs/superpowers/specs/2026-10-10-patterns-trees-design.md` §2 and §4's tree nodes, plan
`docs/superpowers/plans/2026-10-10-7a-trees.md`) code is done; its human checks (group TR) are pending.

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
    the Edit menu (`AppCommands`) shows "Undo <name>" and "Redo <name>" and the top bar (`TopBar`) shows the name as the Undo and Redo icons' tooltip and accessibility label (plain "Undo"/"Redo"
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
  - Data trees (`DataTree`, `TreePath`, `Value.tree`; 7a spec §2): `Value` is `.one`, `.list` or `.tree`. A `DataTree` has a
    `depth` (1 is a flat list, which is why `Value(_ tree:)` makes a `.list` of it, except a culled list, below), every branch at a level has the same depth,
    and a gap is an empty branch. `TreePath` (`{0;3}`, `TreePath(parsing:)`) is the one path type: derived, never stored, and
    what later instance names adopt. Broadcasting stays flat (the old code, unchanged) until a `.tree` meets an item or list
    socket; then `BroadcastPlan.nestedPlan` matches level by level: the outermost level first, the shorter side repeating its
    last branch, a `.one` or flat list applying to every branch, a `list` socket using up one level (one branch per run),
    trees of different depth matched from the outside with one warning naming both shapes, and more than
    `maximumTreeIterations` runs refused. Outputs keep the deepest nesting (`BroadcastPlan.assemble`). A `tree`-access socket
    (`SocketSpec.Access.tree`, `NodeInputs.tree`) gets the whole value as a `DataTree` and never broadcasts; a node returns
    trees through `NodeOutputs(trees:)` and must run once (other inputs single values;
    `NodeDefinition.singleValuesRefusal` lets a node, the layouts, refuse a list
    there in its own words before it runs). `SocketType.any` is for the tree
    nodes' sockets only. Iteration `item` numbers (the tag's item) are flat, row by row.
    Culling keeps paths (patterns spec §4): a flat list or branch that has had items taken out holds the survivors at the indices
    they had (`DataTree.culledList(_:at:)`, `isCulled`, `itemPositions`; `DataTree.keepingItems(where:)` and
    `mappingItems(_:)` are how nodes cull and refill, `replacingItems(_:)` keeps the indices), and since a `.list` cannot say which
    indices its items keep, such a list is a `Value.tree` of depth 1 (`Value(_:)` makes every other flat tree a `.list`). It broadcasts as a list: an item or list socket sees
    the survivors in order, as a rank, and a `tree` socket gets the tree whole with its indices, which is how `InstanceGrid` reads
    them. Reshaping nodes (Flatten, Graft, Partition, Path Mapper) renumber, as reshaping does, and List Item, Branch by Path and
    Tree Statistics count a culled list's survivors by rank; Cull Index alone names the places items had.

File format is version 21 (2 added `.edgePicks`; 3 added `loop` on hole-wall side tags, written only when non-zero;

4 added the `.sketch` and `.facePick` settings; 5 added `definitions`, group definitions, optional on decode; canvas comments' `stickies` and `frames` keys, written only when present and optional on decode, are also under 5; 6 added the tree nodes' text settings `pathRule`, `branchPath` and `itemPath`; trees themselves are computed, never saved; 7 added the Image Field's `image` setting, the optional top-level `images` table (base64 bytes keyed by SHA-256, sorted, written only when used; a damaged entry is dropped on reading) and the `field` socket type in group interfaces; 8 added the `implicit` and `mesh` socket types in group interfaces and the Implicit and Mesh nodes' settings (Shell's `side`, Mesh's resolutions: existing integer and number kinds); implicit solids and meshes are computed, never saved; 9 added cable ties, a graph's optional `ties` key (written only when present, sorted by ID, each tie's wires sorted; decoding drops wires that are no link's input, then ties left with fewer than two); 10 added the document's units (optional key `units` on the top-level graph, written only when not millimetres at the default precision), the new sketch-dimension kinds (radius, diameter and the distances between circles' centres or edges, in `DimensionKind`) and a sketch dimension's optional `labelPoint` (written only when set), and a graph's optional `dimensionPins` key (written only when present); 11 added sketch splines (the `spline` entity with its handle flags, `solved` handle values) and the `curvature` constraint; 12 added the Import Mesh node's `meshFile` setting (`ConstantValue.meshFile`, an `ImageReference`; embedded bytes share the `images` table); 13 added the Import KiCad Board node's `pcbFile` setting (`ConstantValue.pcbFile`, an `ImageReference`, linked only) and the `imported(face:)` role in saved picks; 14 added the `curve` socket type in group interfaces, the Import Model node's `modelFile` setting (`ConstantValue.modelFile`, an `ImageReference`; embedded bytes share the `images` table) and `TopoRole.boundary` in saved picks; 15 added the Edit Surface and Edit Curve nodes' `poleMoves` setting (`ConstantValue.poleMoves`); 16 added `ConstantValue.regionPicks` (Trim Surface's `keepRegions`), `TopoRole.cutSide` and `BoundaryRole.cut` in saved picks; 17 added the top-level graph's optional `drawings` key (`Graph.drawings`, written only when it holds a sheet: the sheets in tab order, each with its views sorted by ID); 18 added drawing annotations (a sheet's `annotations`, sorted by `AnnotationID`, enums with payloads coded as keyed containers with a `type` string), a view's `showsCentreMarks` flag and the structured `DrawingSettings.generalTolerance` and `decimalSign`; 19 added section, detail and auxiliary views (a view's optional `derivation` and `letter`, coded with a `type` string; a version-18 reader cannot decode the new view kinds); 20 added datum feature symbols, feature control frames, surface texture symbols and a sheet's notes (`AnnotationKind`, `AnnotationFigure.attachment`, `DrawingSheet.notes`; a version-19 reader cannot decode the new annotation kinds); 21 added assembly views (`DrawingView.assembly`), part anchors (`AnchorTarget.onPart`), balloons, parts lists and revision tables (`AnnotationKind`), the drawing's `items` and `partNames` and a title block's `logo` (a version-20 reader cannot decode the new anchors and kinds); files of format 1 to 20 open unchanged and are written as 21).
