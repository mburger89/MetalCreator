# Patterns and data trees (sub-project 7a) — design

Status: written 2026-10-10 from a design conversation with the user; awaiting the user's review.
Parent spec: `2026-10-07-metalcreator-vertical-slice-design.md` (§1 goal 2, §2 row 7, §4.2 broadcasting, §5.3 naming,
§7.3 performance), with all its Errata. Groups spec `2026-10-09-selection-groups-comments-design.md` for instance naming.

## 1. Intent

The slice's goal 2 is "feature patterns and surface textures of the kind that until now only Grasshopper could do".
Sub-project 7 covers it and is split into four, each with its own spec, plan and build, in this order:

| # | Sub-project | Adds | Geometry |
|---|---|---|---|
| **7a** | Data trees and feature patterns (this spec) | nested lists with paths; pattern layouts; per-instance variation, culling, randomness; pattern shortcuts | B-rep: exact, STEP |
| 7b | Fields | a value that varies over space (distance, noise, image, field maths), sampled per placement | feeds 7a, 7c, 7d |
| 7c | Implicit geometry and lattices | an SDF pipeline beside OCCT; gyroid, TPMS and strut lattices filling a volume or shell; meshing | mesh: STL, 3MF only |
| 7d | Surface textures | knurl, hex, voronoi and embossed skins on chosen faces, by displacement | mesh: STL, 3MF only |

Decided with the user (2026-10-10): this split and order; lattices and textures are mesh-only (a part carrying one
exports STL/3MF, never STEP), everything in 7a and 7b stays exact B-rep and STEP-exportable.

**Who and what for.** A designer making mechanical parts who wants bolt circles, vent grids, rib arrays, perforated
panels and graded features to stay parametric: change a count, a spacing or a size list and the part follows, with
fillets and other picks staying on the same instances.

**Success.** Up to about 200 instances, the edit-to-preview loop stays interactive (a second or two); every pattern
is built from inspectable values (placements, lists, trees) rather than opaque features; per-instance variation and
culling need no special nodes beyond lists; picks on patterned instances survive count, spacing and cull changes.

### Decisions recorded (user, 2026-10-10)

1. Patterns are **placements plus Place** (approach A), **plus convenience shortcut nodes** (approach C).
2. Nested data is **nested lists** as the one model, with **Grasshopper-style paths** shown and usable on top,
   **including the Path Mapper** in 7a.
3. Scale target: **up to ~200 instances** interactive.
4. Layouts: **linear and grid, circular/polar, along a curve, on a face** (flat faces in 7a; curved faces later).
5. Instance picks follow **by path**; a vanished path warns.
6. Shortcuts: **Hole Pattern, Boss/Pin Pattern, Slot Pattern, Pattern Feature (generic)**.
7. Variation and selection: **Cull by pattern/index, Random (seeded), Cull by region, Jitter**.

## 2. Data model: trees

- `Value` (today `.one(Scalar)` and `.list([Scalar])`) gains a third case, a **tree**: an ordered list of branches,
  each a list of scalars or a further tree, to any depth. A flat list is a one-level tree; every existing node and
  file keeps working unchanged. Code must not assume `Value` has a fixed set of cases (parent spec §4.2 already says so).
- **Paths.** An item's path is its index at each level, written `{0;3}` (branch 0, item 3); deeper `{1;0;4}`. Paths are
  derived, never stored, so they cannot drift from the data. A sparse tree (gaps in branch numbering) is held with empty
  branches in the gaps and shows them as empty.
- **Broadcasting, level by level.** Inputs match on their outermost level first, then the next. At each level a shorter
  side repeats its last branch (as flat lists repeat their last item today). A `.one` or a flat list applies to every
  branch. A node's outputs keep the nesting of its deepest input. A mismatch the rule cannot resolve (different depths
  that don't nest) falls back to matching the outermost level and warns once, naming both shapes.
- **Socket access.** `item` and `list` access are unchanged; a `list` input receives one branch at a time (so Boolean's
  `tools` gets one branch per evaluation). A new `tree` access receives the whole tree (the reshaping and path nodes).
- **Files.** Trees are computed, never saved. The Path Mapper's rule is a new kind of saved setting (text), so
  `GraphFile.currentFormatVersion` goes 5 → 6. Older builds refuse format-6 files (as for earlier bumps); files of
  format ≤ 5 open unchanged.
- **Display.** Socket tooltips and the inspector show a tree's shape ("3 × 8", or a list of branch counts when they
  differ) and an expandable list of paths with their counts.

## 3. Placements, layouts and Place

- A **placement** is a `Plane` (origin and axes: where an instance goes and which way it faces). Planes already exist as
  a scalar and draw in the viewport.
- **Layout nodes** (category Patterns), each outputting placements:
  - **Linear Pattern** — start, direction, count, and spacing or total length. One branch.
  - **Grid Pattern** — count and spacing in X and Y, centred or not, stagger (alternate rows offset by half a pitch,
    hex-style). One branch per row.
  - **Circular Pattern** — centre, axis, radius, count, sweep angle, whether instances rotate with the angle; optional
    rings (ring count, radius step, per-ring count). One branch per ring.
  - **Curve Pattern** — along an edge set (from the selection nodes) or a profile's outline, by count or spacing, each
    placement facing along the tangent. One branch per connected edge chain.
  - **Face Pattern** — a picked flat face (the same `FacePick` as Plane from Face), filled with a grid or staggered grid
    at a spacing, placements facing out along the face normal, clipped to the face including its holes with an edge
    margin. One branch per row. A curved face is refused in 7a with a plain message ("Face Pattern works on flat faces
    for now."); curved faces are a later follow-up.
- **Place** — a tool solid (built at the origin, facing +Z) and placements in; one placed copy per placement out, in the
  placements' tree shape. Each copy's faces carry the instance's path in their tags (§6).
- **Points to Placements** — turns any list or tree of points (e.g. Grid Points') into placements facing a chosen
  direction, so existing graphs (the bracket's holes) can move over gradually. Grid Points and Transform stay.
- A layout over 2,000 placements refuses: "Patterns are limited to 2,000 instances." (as Grid Points caps its count).

## 4. Trees, culling and randomness

- **Tree nodes** (category Lists & Trees), all with `tree` access:
  - **Flatten** — removes all nesting, or down to a given level.
  - **Graft** — wraps each item in its own branch.
  - **Partition** — splits each branch into branches of N.
  - **Tree Statistics** — paths, branch counts, depth.
  - **List Item** and **Branch by Path** — by index, or by a path such as `{0;3}`.
  - **Path Mapper** — reshapes by a text rule `source → target`, e.g. `{A;B} → {B;A}` (swap rows and columns),
    `{A;B} → {A}` (merge each row), `{A;B} → {A;B%2}`. Letters bind the index at that level; `(i)` is an item's index
    within its branch; `+ − × / %` and integer literals are allowed in the target. A rule that does not parse, or whose
    source depth does not match the tree, refuses with a message naming the failing part; a rule that matches some
    branches only warns and passes the rest through unchanged.
- **Culling:**
  - **Cull Pattern** — a true/false mask repeated across each branch.
  - **Cull Index** — drops listed indices or paths.
  - **Cull by Region** — keeps placements inside or outside a profile, or within or beyond a distance from a point, an
    edge set or a face.
- **Random, always seeded** (the seed is an input; the same seed gives the same result on every machine, so an edit
  never reshuffles; the generator is a fixed, documented algorithm, never the system's):
  - **Random Reduce** — drop N or a fraction, per branch or overall.
  - **Random Values** — per-instance integers or reals in a range, in the shape of a given tree or count.
  - **Jitter** — a random offset in each placement's own plane and a random turn about its normal, within limits.
- **Variation** needs no extra nodes: a list or tree on any input varies per instance through broadcasting; Range and
  Series make graded sequences.
- **Culling keeps paths.** Remaining instances keep their original paths (no renumbering), so a cull never moves a pick
  to another instance; a culled instance's path is gone and a pick on it warns (§6).

## 5. Shortcut nodes

Each is Place + Boolean underneath (documented as such in its inspector help), takes a part and placements, and takes
lists or trees on any size input for per-instance variation.

- **Hole Pattern** — diameter, depth or through-all, optional counterbore (diameter, depth) or countersink (diameter,
  angle). A hole is cut from the placement's origin into the part, against the normal. Through-all reaches past the
  part's bounds.
- **Boss / Pin Pattern** — diameter, height, optional draft angle and tip fillet; unioned on, growing along the normal.
- **Slot Pattern** — length, width (rounded ends), depth or through, along each placement's X axis; cut.
- **Pattern Feature** — any tool solid, union or subtract; the general shortcut.

An instance whose tool misses the part (a hole in empty space) does not fail the node: it warns with the count
("3 of 24 holes miss the part.").

## 6. Naming

- A placed copy's face tags are its tool's tags qualified by the instance path, by the same mechanism as group
  instances (`NodeID.scoped`, `EvaluationScope`), so a pick on `{0;3}`'s rim names that path.
- After an edit, a pick resolves against the instance with the same path. If that path no longer exists (a lower count,
  a cull), the pick warns, naming the path, and selects nothing there; it never jumps to a neighbour.
- Changing spacing, position or size of instances keeps paths, so picks follow.
- No new saved key: picks already store tags; the scoped tags are a longer form of the same data.

## 7. Performance

- Target: ~200 instances, edit-to-preview within a second or two (release build, idle Mac).
- A shortcut or a Boolean with placed tools makes **one** kernel call: the placed tools are fused into one compound and
  cut or joined at once (Boolean's tools list already works this way). Never one boolean per instance.
- **Tool reuse:** placed copies of one tool share its geometry and differ only in transform, so building the tool costs
  once per distinct size, not per instance.
- **Tags without extra history:** instance tags come from the path and the tool's own tags; naming adds no boolean work.
- A release benchmark (200 through-holes in a plate, and the same with a fillet on one patterned hole) joins
  `Tests/CreatorAppTests/Bench` and `docs/verification/performance.md`, with the target above. A miss is recorded with
  its numbers, never hidden (parent spec §7.3).

## 8. Errors and UI

- Messages are plain and actionable, as elsewhere: tree mismatches name both shapes; Path Mapper errors name the
  failing part of the rule; a vanished instance path is named; shortcut misses give the count; a seed change never warns.
- **Previews:** a selected layout node shows its placements in the viewport as small axis triads (Face Pattern also
  outlines its clipped area), drawn as guides (like Final preview's selected-rule edges): they never pick, frame or open
  a menu.
- **Library:** a **Patterns** category (layouts, Place, Points to Placements, shortcuts, culling, random, Jitter) and a
  **Lists & Trees** category (reshaping and path nodes).
- **Path Mapper's rule** is a text field in the inspector, committed like other text entries.

## 9. Testing

- Unit: level-by-level broadcasting (equal, repeat-last, flat-onto-tree, mismatched depths), path derivation and display,
  each tree node, sparse trees, the Path Mapper parser and evaluator (good, bad and partly matching rules).
- Layouts: placements against known coordinates for each layout, including stagger, rings, tangents and Face Pattern
  clipping around holes and margins.
- Random: fixed seeds give fixed results (pinned values), per branch and overall.
- Naming: a fillet on `{0;3}` survives a count change, a spacing change and a cull of another instance; a vanished path
  warns.
- Acceptance (headless, in the spirit of the bracket): a plate with a circular bolt pattern (per-ring diameters), a
  staggered vent grid on a face with an edge margin, and a fillet on one patterned hole; parameters change, the file is
  saved (format 6) and reopened, every pick holds, STEP export succeeds; a format-5 file opens unchanged.
- Performance: the 200-hole benchmark (§7).
- Human checks: layout previews, tree display, Path Mapper messages, the shortcuts' results.

## 10. Out of scope (later)

- Curved faces in Face Pattern; fields (7b); lattices (7c); textures (7d).
- Patterns of patterns beyond what nesting gives (e.g. a pattern feature that itself contains picks inside each instance).
- More than ~2,000 instances as B-rep.

## Errata (7a-1: data trees)

Plan `2026-10-10-7a-trees.md`. Where the build settled what §2 and §4 left open:

- §2 Depth. A flat list is a tree of depth 1 and an item has depth 0; every branch at a level has the same depth, so a tree is
  held as a depth plus nested branches (`DataTree`). `Value.tree` holds depth 2 or more; a depth-1 tree is always a `.list`.
- §2 Broadcasting. A `list` socket uses up one level of a tree (one branch per run), so a `list` socket on a 3 × 8 tree runs 3
  times and its output has one entry per branch. Trees of depth 2 or more that differ in depth (3 × 8 against 2 × 3 × 4) are
  matched from the outermost level, and the node warns once, naming both shapes, even when the shallower tree's levels line up with
  the outer ones (2 × 2 against 2 × 2 × 1: the build does not judge which depths "nest"; User decision 4); a tree against a single
  item or a flat list never warns. A broadcast over more than 100,000 runs is refused naming the shapes. A node that returns a tree runs once: a list on one
  of its other inputs fails with "This node works on a whole tree at once, so its other inputs must be single values, not lists."
- §2 Broadcasting, a flat list. Against a tree on an item socket a flat list applies to every branch and matches that branch's items
  (a flat list of 8 against a 3 × 8 tree). Against a tree on a `list` socket, which has used one level up, a flat list on an item
  socket is paired with the branches one for one and the shorter side repeats its last (three plates against three rows of tools;
  `[1,2,3]` against `[[10,11],[20]]` runs 3 times: branch 0, 1, 1). One rule gives both: a flat list steps only when it is as deep
  as the deepest input left. The spec's "a flat list applies to every branch" is read for item sockets only (User decision 3).
- §2 Types. Tree nodes' sockets are `SocketType.any` (accepts and may be wired to every type; the items are checked where they
  are used). `SocketSpec.Access.tree` hands a node the whole value; a single item arrives as a list of one.
- §2 Files. Format 6; the new saved settings are `NodeSetting.pathRule`, `NodeSetting.branchPath` and `NodeSetting.itemPath`, all `.text`.
- §4 Path Mapper. A rule's paths name branches or items, chosen by how many letters the source has (User decision 2, option
  c). A source with as many terms as the tree has levels of branches names branches (one index per level of branches): a 3 × 8
  tree has the branches `{0}` to `{2}`, a flat list has one branch `{}`, and `(i)` is the item's index in its branch. A source
  with exactly one term more names items: the first terms match the branch and the last the item's index in it, so on a 3 × 8
  grid `{A;B} → {B;A}` makes an 8 × 3 one (a transpose) and `{A;B} → {A}` gathers every item of branch A into branch A (the rows
  stay). With items named, the target has the branch's terms (`{A}`) or one more, the item's position in the branch it goes to
  (`{B;A}`); an item the source does not match stays at its own index in its own branch. A source with two or more terms too many
  or too few refuses, naming the depth ("The rule's source {A;B;C} names 3 levels, but this tree (3 × 8) has 1 level of
  branches."). `{A} → {(i)}` is still the branch-level way to swap rows and columns, and `{A;B} → {A}` merges the branches of a
  tree of depth 3 (branch-level, two levels of branches). Letters are single letters
  other than `i`; a repeated letter or a whole number in the source matches only equal or that index; unmatched branches stay
  where they were (a warning), which needs a target of the same depth; the target may use `+ - * / %` (also `−` and `×`), whole
  numbers, letters and brackets; a negative index, a division by zero, an overflow and a result of more than 10,000 branches
  refuse. A branch that stays where it was can land on a path the rule also wrote to; its items are then mixed with the result's
  and the warning says how many branches did (`{0;B} → {B;0}`). A new node's rule is `{A} → {A}`.
- §4 Tree Statistics outputs `depth`, `branches` (how many hold items), `items` and `counts` (items per branch); the path list is
  the inspector's expandable Data section, because no socket carries text.
- §4 List Item takes the item at an index from every branch and keeps the branches (one item each, none where the branch is too
  short, with a warning counting them). Its `itemPath` setting (empty by default) takes the one item a full path such as `{0;3}`
  names instead, and the index is then ignored; a path with the wrong number of indices, a missing branch or a missing item
  refuses ("No item {1;7}: {1} has 3 items."), never a neighbour (User decision 5). Branch by Path takes the branch at a path setting (`{0}` by default); a shorter path
  takes the subtree under it; a path that is not there refuses ("No branch {5}: the tree has 3 branches."), never a neighbour.
- §4 Flatten's `level` is how many levels of branches to keep from the outside; empty keeps none.
- §8 Library. The category is "Lists & Trees" (`NodeCategory.lists`, between Feature and Output) and shares the Value header
  colour: the theme files have no role for it.
- §2 Display. A socket's tooltip reads "Tree 3 × 8" (only for trees); the inspector's "Data" section appears only when a node has a
  tree on an input or output.

## Errata (7a-2: Place and shortcuts)

- **A tree on a pattern node is refused** (User decision 8a, fixed at the merge with 7a-1). A tree wired to any input of Place,
  Hole, Boss, Slot or Pattern Feature would run the node once per branch, cutting the part once per branch and restarting `{i}`
  at 0 in each. `EvalContext.isTreeRun` tells a node its run came from a tree, and `PlacementMoves.requireFlat` (the one place
  the check is written) fails it with "Patterns take a flat list of placements for now: flatten the tree first." before
  anything is placed. Nested paths for tree instances arrive with 7a-3.

- **Group edits rename instance picks** (User decision 3, fixed in 7a-2). Group, Ungroup and Make Unique rename a pick on
  a pattern instance's faces exactly as they rename a pick on any node's: `GroupScopes.names` lifts its table to the
  placer/tool pairs (`GroupScopes.lifting`) for every node whose type places instances, so the pick resolves to the same
  instance with no warning, and undo restores it in the same step. Still open: a Place inside a group whose tool is made
  outside it doesn't match picks stored in the definition.
