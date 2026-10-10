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
