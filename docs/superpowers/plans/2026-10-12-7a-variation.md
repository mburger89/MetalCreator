# Variation and Culling (7a-3 part B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Six tree-aware nodes in the Patterns category (Cull Pattern, Cull Index, Cull by Region, Random Reduce, Random Values, Jitter) whose culls keep paths, whose randomness is one fixed, documented, seeded generator, and whose survivors keep their original instance index in Place's and the shortcuts' tags, so a pick on one instance survives a cull of another and a pick on a culled instance warns naming its path.

**Architecture:** A cull cannot renumber, so a flat list or branch gains the one thing it lacked, item-level gaps: a `DataTree` of depth 1 may carry the indices its items keep (a "culled list", a `Value.tree` of depth 1), and `NodeInputs.positions(_:)` hands them to a `list` socket. Points to Placements passes a culled list of points on as culled placements, and Place and the shortcuts read culled placements through `PlacementSet`: the instances are exactly the surviving indices, each copy's tags carry its index (the copies `Kernel.place` numbers 0, 1, 2… are renumbered to their instance), and sizes and tools are read by index. The six nodes take a tree whole (`tree` access) and return the same nesting; all randomness is `SeededRandom`, SplitMix64 written out in the repo, drawn by an item's place (branch ordinal and index), never by how many items there are.

**Tech Stack:** Swift 6.4 strict concurrency, Swift Testing, `FakeKernel` and `OCCTKernel` in tests, `swiftlint lint --strict`. No third-party code. No MetalUI change, no new MetalUI gap.

**Spec:** `docs/superpowers/specs/2026-10-10-patterns-trees-design.md` §4 (culling and randomness), §6 (naming), §8 (errors), §9 (testing) and its Errata for 7a-1 and 7a-2, under `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata; the merged plans `docs/superpowers/plans/2026-10-10-7a-trees.md` and `2026-10-10-7a-place.md`. Executors read the spec's §4 and §6 first. This plan adds an Errata section to the spec in Task 10.

**Base:** branch `7a-variation` off master `9e5d2d5` (2639 tests). Layout nodes (Linear, Grid, Circular, Curve, Face), previews, lifting the tree refusal on Place and the shortcuts, tree-path instance picks and the acceptance test are 7a-layouts, not here. Never run the release benchmark.

## Merge order and shared files

7a-layouts merges **first**, this track **second**, harness independently. The side that merges second (this one) resolves every conflict below by keeping both sides' additions and re-deriving the numbers noted.

| Shared file | Others touching it | What this track keeps / what to re-derive |
|---|---|---|
| `Sources/CreatorNodes/BuiltInNodes.swift` | 7a-layouts (5 layout nodes), harness (none) | This track adds six lines **above `OutputNode.self`** (one per node), never in the shortcut line. Keep both. |
| `Tests/CreatorNodesTests/OutputNodeTests.swift` | 7a-layouts | Node count and the category dictionary: after both, 41 + 5 + 6 = **52** nodes and `.patterns` = 6 + 5 + 6 = **17**. |
| `Tests/CreatorEditorTests/PatternsLibraryTests.swift` | 7a-layouts | The Patterns names list: layouts first (library order is `BuiltInNodes.all` order within the category), then Place … Pattern Feature, then this track's six in the order Cull Pattern, Cull Index, Cull by Region, Random Reduce, Random Values, Jitter. |
| `Sources/CreatorGraph/NodeSetting.swift` | 7a-layouts if it adds a setting | `cullPattern` and `cullIndices` are added to `all`; keep every other track's. |
| `Sources/CreatorGraph/{DataTree,Value,DataTree+Shape,NodeInputs,BroadcastPlan,TreeCursor}.swift` | 7a-layouts (lifting the tree refusal may touch `EvalContext`, `BroadcastPlan`) | **Keep the culled list**: `slots` in `DataTree`, `Value(_:)` returning `.tree` for a culled depth-1 tree, `meetsTree` ignoring depth-1 trees, `culledInputs`, `NodeInputs.positions(_:)`, the `TreeCursor.slot` case. A tree run (`isTreeRun`) must still deliver a culled branch's indices (`TreeCursor.slot`). |
| `Sources/CreatorNodes/Patterns/{PlaceNode,PatternApply,PlacementMoves,PatternMisses,PerInstance,PointsToPlacementsNode}.swift`, `HolePatternNode`, `BossPatternNode`, `SlotPatternNode`, `PatternFeatureNode` | 7a-layouts (tree refusal, tree-path picks) — **the heaviest overlap** | **Keep:** `PlacementSet.instances(alongside:)` as the single source of the instances; `PlacementMoves.copies(of:at:instances:…)` as the one place copies are made and tagged; reading sizes through `PerInstance(…, positions:)`; `PatternMisses.count(…, instances:)`; **in `PointsToPlacementsNode`** the culled-points path (`PerInstance` for `points` and `direction`, the instances a culled `points` list holds, a `trees` output of culled placements, and the tree-run warning) — if 7a-layouts changes how that node runs in a tree (it should not need to), keep a culled list of points producing a culled list of placements. If 7a-layouts changes how an instance is named (a tree path instead of the flat index), `copies` must tag each copy with **its instance's path** (`DataTree.Leaf.itemPath(_:)`), and `Topology.renumberingInstance` becomes whatever sets that path; delete it if `Kernel.place` takes the paths itself. |
| `Tests/CreatorNodesTests/Variation/CulledPickTests.swift` | — | **Must pass unchanged after 7a-layouts merges**: it uses one flat list (Grid Points and Points to Placements with a Cull Index on either side of Points to Placements), where a tree-path pick `{i}` is still the item index. If it fails, the merge broke "culling keeps the instance's index", not the test. It reads `PatternPlate`'s `h`, `plate`, `grid` and `placements` (and `VariationPipelineTests` its `plateVolume`): if 7a-layouts changes that fixture, adapt the fixture's use in these two files, never the expectations. |
| `Sources/CreatorKernel/Topology+InstanceItems.swift` | — (new) | New file; `Topology+Instances.swift` is not edited. |
| `CLAUDE.md`, `docs/superpowers/roadmap.md`, the spec's Errata, `docs/verification/human-checks.md` | 7a-layouts, harness | Each track appends its own paragraph/section; keep all. This track's: the CLAUDE.md paragraph and the Variation bullet, roadmap row text for 7a-3 part B, "Errata (7a-3 part B)", "Group VA". The CLAUDE.md node count becomes 52 and "the twelve `Patterns` nodes" becomes seventeen. |
| `Tests/CreatorNodesTests/PatternPickStabilityTests.swift`, `Support/PatternPlate.swift` | 7a-layouts | **Not edited here** (`CulledPickTests` has its own fixture and only reads `PatternPlate`). |

## Global Constraints

- Swift 6 strict concurrency, Swift Testing, the repo's `CLAUDE.md` rules: one type per file, behaviour in models and thin views (this plan touches no views), no force unwraps, no GCD, `FormatStyle` for text (`.formatted(.number.locale(.messages))`, `.list(type:)`), no C-style formatting.
- `swiftlint lint --strict` reports zero violations before every commit (line length 140, trailing commas in multi-line literals).
- Randomness is **always seeded** through a `seed` input, by one fixed, documented algorithm implemented in the repo (`SeededRandom`, SplitMix64), **never the system generator**. Each random node draws for its own `SeededRandom.Purpose`, which is mixed into the seed, so two nodes with the same seed do not draw the same numbers (User decision U7). The same seed gives the same result on every machine and in every release, a seed change never warns, and fixed seeds are pinned in tests, per branch and overall.
- Culling keeps paths: survivors keep their original paths (a sparse result), never renumbered; a pick on an instance survives a cull of another instance and a pick on a culled instance warns naming its path (spec §4, §6).
- Messages are plain and actionable (spec §8): a path error names the shape, a refused value names the socket and the limit, a path that names nothing is named.
- All six nodes are in `NodeCategory.patterns`, tree-aware, and take lists or trees (`access: .tree`).
- `GraphFile.currentFormatVersion` stays 6: the two new settings are `.text` values of new node types (see Key decisions).
- MetalUI gaps go in `docs/metalui-gaps.md` (entry **and** summary table row) and are never worked around. This plan finds none.
- A full `swift test` run passes only if the exit code is 0, no line says "recorded an issue" or "failed after", and 11 "Test run with" lines appear. Never run the release benchmark (`scripts/bench.sh`).
- Run every command from the worktree root. Do not edit `Package.swift`'s MetalUI path or anything under `../MetalUI`.
- **Reading the edits.** "Create" writes a whole file. "replace … with" swaps one block of text that occurs exactly once. "directly after … add" puts the block on **new lines straight after the anchor's last line** (never on the same line); a block that opens with a blank line leaves one blank line between them.

## Review Focus

The inputs and conditions the spec implies but no node's own happy-path tests would exercise, most likely first. Each has its test in the task that owns the code.

1. **A size or tool list longer than the culled placements.** A culled tail must not come back as repeats of the last placement ("ghost" instances), and a survivor must keep its own size, not the size of its rank. Tests: `aCulledListMakesExactlyTheInstancesItKeeps`, `aLongerToolListAddsNoInstancesToCulledPlacements`, `aSurvivingInstanceKeepsItsOwnTool`, `aCulledSizeListIsReadByTheInstancesIndex` (Task 3). The same holds the other way round: a culled size or tool list with **more** survivors than there are plain placements sets no number of instances (`aCulledSizeListWithMoreSurvivorsThanPlacementsSetsNoNumberOfInstances`, `aCulledSizeListLongerThanThePlacementsMakesNoExtraHoles`, Task 3).
2. **Everything culled.** A cull that removes every placement leaves the part untouched with no error and no warning, and Place makes no copies. Test: `aCullThatRemovesEveryPlacementLeavesThePartAloneAndMakesNoCopies` (Task 3); empty branches stay as gaps: `aMaskThatCullsEverythingLeavesEmptyBranches` (Task 4).
3. **Culling a list that was already culled.** The mask counts the items left; indices and paths name the places items had at the start; nothing renumbers. Tests: `aSecondCullCountsTheSurvivorsAndKeepsTheFirstOnesIndices` (Task 4), `indicesNameThePlacesTheItemsHadBeforeAnyCull`, `aPathOnAnItemAlreadyCulledWarns` (Task 5).
4. **A reshaping node after a cull** (Partition, Flatten, Path Mapper) renumbers, as reshaping does; and an ordinary item socket given a culled list pairs by place and drops the gaps. Pinned, so a change is deliberate: `aReshapingNodeAfterACullRenumbersAsReshapingDoes` (Task 4), `aCulledListOnAnItemSocketPairsItemsByTheirPlaceInTheList` (Task 2).
5. **Numbers must not depend on how many items there are.** More placements, a longer list, a cull, or a changed count must not reshuffle the others: `moreItemsAtTheEndNeverChangeWhichEarlierOneIsLowest` (Task 7), `theFirstNumbersDoNotDependOnHowManyThereAre`, `aCulledShapeGetsNumbersAtThePathsItKeptAndTheOthersKeepTheirNumbers` (Task 8), `addingPlacementsDoesNotMoveTheEarlierOnes`, `aCulledInputStaysCulledAndTheSurvivorsMoveAsTheyWouldHave` (Task 9).
6. **A cull placed before Points to Placements.** Grid Points → Cull → Points to Placements is the most natural graph, and Points to Placements used to read `points` as a plain list, so the placements came out renumbered and every pick shifted to a neighbour. It now passes a culled list of points on as culled placements. Tests: `pointsToPlacementsKeepsACulledListsIndices`, `aCulledDirectionListIsReadByTheInstancesIndex`, `aCullThatRemovesEveryPointMakesAnEmptyCulledList` (Task 3), and `CulledPickTests` run with the cull on **both sides** of Points to Placements (Task 5, `aPickOnOneInstanceSurvivesACullOfAnother` and the two tests after it). Inside a tree run a culled branch still renumbers, and the node says so (`inATreeRunACulledBranchIsRenumberedAndSaysSo`, User decision U15).
7. **Equal seeds on different nodes.** Random Reduce, Random Values and Jitter all default to seed 0; unsalted, the items Random Reduce drops would be exactly the ones with the smallest Random Values. Each node draws for its own `SeededRandom.Purpose` (Task 1: `eachPurposeHasItsOwnPinnedNumbers`, `equalSeedsOnDifferentPurposesDrawDifferentNumbers`; Task 10: `withTheSameSeedTheItemsRandomReduceDropsAreNotTheSmallestRandomValues`).

---

## Key decisions

1. **Item-level gaps: `Value.tree` could not express them, so it is extended minimally.** 7a-1 holds a sparse tree's gaps as empty branches, which only says "branch 2 has nothing", not "item 1 of this branch is gone". The extension: a `DataTree` of depth 1 may carry `slots`, the index each item keeps (`DataTree.culledList(_:at:)`, `isCulled`, `itemPositions`); `Value(_:)` makes it a `Value.tree` of depth 1 (a `.list` cannot say it), and every other flat tree stays a `.list`, so no existing value changes form. Deeper trees carry gaps in their depth-1 leaves, so a cull of a 3 × 8 tree leaves 3 culled branches. *Why not a null item:* arithmetic nodes would fail with type errors on it, and counts would include it. A list culled only at its end is still marked culled (`slots` held even when 0, 1, 2…) so the culled tail cannot come back as repeated placements.
2. **A culled list broadcasts as a list.** `BroadcastPlan.meetsTree` now looks only at trees of depth 2 or more, so a culled list on a `list` socket runs the node once (`isTreeRun` stays false and Place does not refuse it) and arrives with its indices (`NodeInputs.positions`); on an `item` socket it pairs by place and drops the gaps; on a `tree` socket it arrives whole. Beside a real tree (a nested plan) the same indices arrive through `TreeCursor.slot`.
3. **Surviving instances keep their index without touching the `Kernel` protocol.** `Kernel.place` numbers copies by position in its argument list. Rather than adding a parameter to the protocol (three conformers, and 7a-layouts is changing instance naming), `PlacementMoves.copies` places the survivors and renumbers any copy whose instance index differs (`Topology.renumberingInstance(to:)` sets the item of every instance-qualified tag, blend source edges included) on a new `Solid` that shares the kernel's storage, as `OCCTKernel.place` itself builds its copies.
4. **Instances are exactly the surviving indices.** `PlacementSet.instances(alongside:)`: a plain list makes `0..<max(placements, other lists)` as before; a culled list makes its indices and a longer size list adds none. Sizes and tools are read by the instance's index (`PerInstance(…, positions:)`: its own value, else the nearest one before it, else the first). A culled size or tool list never sets the number of instances, however many survivors it holds: it contributes `PerInstance.span` (1 when it holds anything, 0 when everything was culled, which makes no instances, as an empty plain list does). Dense graphs behave exactly as before (the 7a-2 tests pass untouched).
5. **One generator, drawn by place.** `SeededRandom` is SplitMix64: draw `k` of a stream is `mix(start + (k + 1) × 0x9E3779B97F4A7C15)`, so any draw is reachable directly and sequential and direct access agree. Stream 0 starts at the seed; stream `n` at `mix(seed + n × step)`. Nodes draw item `(branch ordinal n, index i)` from stream `n` at draw `i` (Jitter: draws `3i`, `3i + 1`, `3i + 2`), so counts, culls and longer lists reshuffle nothing. Seed 0 reproduces the published SplitMix64 vector (pinned, `Purpose.plain`), and other seeds' first draws are pinned. **Each random node draws for its own `SeededRandom.Purpose`** (`reduce`, `values`, `jitter`): the seed is first mixed with a fixed per-purpose constant (`mix(seed ^ salt)`, the salt being the node's name in ASCII ending `_1`), so equal seeds on different nodes draw unrelated numbers (User decision U7). The salts are part of the contract and pinned in `SeededRandomTests`.
6. **Random Reduce ranks, it does not shuffle.** Every item gets its draw as a key and the smallest keys go: a bigger amount drops what a smaller one did and more, and the choice depends on the seed and the items' places alone. Per branch ranks within each branch (stream = branch ordinal); overall ranks all items together. A fraction rounds to the nearest whole item, halves up.
7. **Random Values has two outputs.** `values` (reals, `min` up to `max`) and `integers` (both ends included, `min` rounded up to `max` rounded down), the second an optional output left out when no whole number is in range (the existing "isn't produced" wire message covers it). With a `shape` wired it fills that tree (culled gaps included); with none it makes a flat list of `count` (at most 100,000).
8. **Cull Pattern and Cull Index take their lists as saved text** (`cullPattern`: `1 0 1`; `cullIndices`: `1, 4, {0;3}`) because no node today makes a list of booleans or integers by hand; each also takes a wired list (`keep` booleans; `indices` numbers, so a Series or Random Values' `integers` works). A bare index names that place in every branch; a path names one item or, when short, a whole branch (left as an empty branch).
9. **Cull by Region judges a placement by its origin**; a profile is a prism along its plane's normal; the boundary counts as inside/within; distances use exact straight and circular edges (anything else refuses with the count) and the **plane** of a flat face (a curved face refuses with the count). Choices are integer sockets with segmented controls (`reference`: Profile, Point, Edges, Face; `keep`: Inside or within, Outside or beyond), the same way `Pattern Feature`'s operation is.
10. **No file-format bump.** The new settings belong to new node types; `NodeSetting.all` gains them (so Group sockets cannot be named like them). A file with these nodes opened by a build without them already fails on the unknown node type, which is how 7a-2's nodes behaved.
11. **The nodes are `tree`-access and `any`-typed** (like the Lists & Trees nodes), except Cull by Region and Jitter, whose placements are `plane`-typed, and Random Values, whose outputs are `number` and `integer`: a typed wire connects them to size and placement inputs, and `Value.converted(to:)` keeps the culled indices.
12. **Points to Placements carries a cull through.** A cull is as likely to sit before Points to Placements (on Grid Points) as after it, and the node used to read its `points` as a plain list and return a plain one, which renumbered. It now reads `points` and `direction` through `PerInstance`: when `points` is culled the placements are exactly the surviving indices, the output is a culled list (`DataTree.culledList`, through `NodeOutputs(trees:)`), and a direction list is read by the instance's index. Inside a tree run (a culled branch of a deeper tree) the node cannot return a tree per run, so it returns the branch as a plain list and warns that culling after the node keeps the paths (User decision U15).

## User decisions (the plan takes the recommended default; change them before executing if you disagree)

| # | Open product behaviour | Options | Recommended and planned |
|---|---|---|---|
| U1 | Cull Pattern polarity | (a) `1`/true **keeps**, `0`/false culls, the wired socket is called `keep`; (b) Grasshopper's: true culls | (a): "keep" says what the socket does; a designer reads `1 0` as "every other one stays". |
| U2 | What a repeating mask counts | (a) the items the branch has **now** (a second Cull Pattern works on what is left); (b) the places they had | (a), like a list pattern in Grasshopper. Indices and paths in Cull Index always use places. |
| U3 | Distance to a face | (a) to the face's **plane**, flat faces only, a curved face refused (a placement far beside a small face counts as near it); (b) Face refuses altogether until a kernel distance to the face's outline exists; (c) to the face's real outline (needs a kernel query) | (a) now, (c) when a kernel distance exists; the docs, the node's comment and the Errata say "to the plane". `FaceInfo` has no bounds beyond area and centroid, so "also inside the face's bounds" cannot be done without that query. Choose (b) if a wrong keep near a small face would be worse than no Face option. |
| U4 | A placement exactly on a boundary or at exactly the distance | (a) inside/within; (b) outside/beyond | (a). |
| U5 | Paths through reshaping and selecting | (a) Partition, Flatten, Graft and Path Mapper renumber a culled list (reshaping makes new branches), and **List Item, Branch by Path and Tree Statistics count a culled list's survivors by rank** (List Item index 2 on a list culled to {0, 2, 4} returns the item at {4}), while Cull Index always names the places items had; (b) they carry or name the old indices | (a): cull last, or cull after reshaping; the same rule as U2 (a node that works on "what is there now" counts the survivors). (b) would need each node to decide what a path means after a reshape, and would change 7a-1's nodes. |
| U6 | An arbitrary node (Extrude, Rectangle…) fed a culled list | (a) pairs by place and returns a plain list (gaps dropped); (b) keeps the gaps in its output (the "outputs keep the nesting of the deepest input" rule extended to gaps) | (a) now: only the pattern, cull and random nodes keep gaps. Wire the cull after the sizes, or feed sizes into the pattern node (it reads them by index). |
| U7 | Two random nodes with the same seed | (a) the same draws (correlated: with equal seeds Random Reduce drops exactly the items with the smallest Random Values, and Jitter's offsets follow the same numbers); (b) each node type salts the seed (`SeededRandom.Purpose`) so equal seeds decorrelate | **(b), planned.** Nothing has shipped with these nodes, so the salt costs nothing now, and adding one later would change every pinned value and every saved file's result, which is the property the spec makes a promise. The cost: one more constant per node to document and pin. Choose (a) only if "the seed is the seed" matters more than independence. |
| U8 | Jitter's shape | (a) a disc of radius `distance` in the placement's plane and a symmetric turn; (b) a square (independent X and Y limits) | (a): one number, direction-free. |
| U9 | Random Values' `integers` when no whole number is in range | (a) output left out (a wire says it isn't produced); (b) error | (a): the reals still work. |
| U10 | A bare number in Cull Index | (a) names that place in **every** branch; (b) is refused unless it is a full path | (a): the common case for a flat list or "the third of every row". A bare `{}` (the empty path, the whole tree) is refused with a message pointing at Cull Pattern `0`, since a stray `{}` must not empty a graph silently. |
| U11 | Where Cull by Region judges a placement | (a) by its **origin** only, a profile being a prism along its plane's normal (a tilted placement's footprint and height are ignored); (b) by the placement's footprint or the tool's extent | (a): one point, easy to predict and explain; a designer who needs margins adds the tool's radius to `distance`. |
| U12 | An instance whose own size or tool was culled | (a) takes the nearest earlier surviving value, else the first (a plain shorter list repeats its last); (b) is refused, naming its path; (c) is skipped | (a): never a surprise failure after a cull, and it is how a shorter plain list already behaves. |
| U13 | Rounding a fraction in Random Reduce | (a) to the nearest whole item, halves up (a quarter of 6 is 2); (b) always down; (c) always up | (a). |
| U14 | Defaults | Random Reduce drops 1 per branch (seed 0); Cull Pattern starts at `1 0` (every other item stays); Jitter 1 mm and 5 degrees; Random Values 8 values from 0 to 1 | As planned: each does something visible when dropped on the canvas, and 0 is the empty default only for Cull Index. The alternative is dropping nothing by default. |
| U15 | Points to Placements on a culled branch inside a tree run | (a) returns the branch as a plain list (renumbered) and warns "cull after Points to Placements to keep the paths"; (b) refuses; (c) takes `points` as a whole tree (a larger change to a 7a-2 node, with tree-path instances) | (a): graphs that worked on master keep working, the warning names the fix, and 7a-layouts (which owns tree-path instance names) can do (c). Flat lists and single-level culls, the common case, keep their indices. |

---

## File structure

Source (all new files unless marked), by responsibility:

| File | Responsibility |
|---|---|
| `Sources/CreatorNodes/Patterns/Variation/SeededRandom.swift` | SplitMix64: the only generator; draws by place; a `Purpose` per random node |
| `Sources/CreatorGraph/DataTree.swift` (edit), `DataTree+Culling.swift`, `Value+Culled.swift` | culled lists: per-item indices, `keepingItems`, `replacingItems`, `rebuildingLeaves` |
| `Sources/CreatorGraph/{Value,DataTree+Shape,NodeInputs,BroadcastPlan,TreeCursor}.swift` (edits) | `Value(_:)` form, "culled" in shape text, `positions(_:)`, a culled list broadcasts as a list |
| `Sources/CreatorKernel/Topology+InstanceItems.swift` | `renumberingInstance(to:)`: a copy's tags take its instance's index |
| `Sources/CreatorNodes/Patterns/PlacementSet.swift`, `NodeInputs+PerInstance.swift` | the instances culled placements make; sizes read by index |
| `Sources/CreatorNodes/Patterns/{PlacementMoves,PlaceNode,PatternApply,PatternMisses,PerInstance,HolePatternNode,BossPatternNode,SlotPatternNode,PatternFeatureNode}.swift` (edits) | Place and the shortcuts use `PlacementSet` and `PlacementMoves.copies`; `PerInstance.span` |
| `Sources/CreatorNodes/Patterns/PointsToPlacementsNode.swift` (edit) | a culled list of points makes a culled list of placements |
| `Sources/CreatorNodes/Patterns/Variation/CullMask.swift`, `CullPatternNode.swift` | Cull Pattern |
| `Sources/CreatorNodes/Patterns/Variation/CullTargets.swift`, `CullIndexNode.swift` | Cull Index |
| `Sources/CreatorGeometry/Profile2D+Contains.swift`, `Sources/CreatorNodes/Patterns/Variation/RegionDistance.swift`, `CullByRegionNode.swift` | Cull by Region |
| `Sources/CreatorNodes/Patterns/Variation/RandomReduction.swift`, `RandomReduceNode.swift` | Random Reduce |
| `Sources/CreatorNodes/Patterns/Variation/RandomValuesNode.swift` | Random Values |
| `Sources/CreatorNodes/Patterns/Variation/PlaneJitter.swift`, `JitterNode.swift` | Jitter |
| `Sources/CreatorGraph/NodeSetting.swift`, `Sources/CreatorNodes/BuiltInNodes.swift` (edits) | `cullPattern`, `cullIndices`; six registrations |

Tests: `Tests/CreatorNodesTests/Variation/*` (one file per node, `CulledInstancesTests`, `CulledPickTests`, `VariationPipelineTests`),
`Tests/CreatorGraphTests/Trees/CulledTreeTests.swift`, `Tests/CreatorKernelTests/InstanceRenumberingTests.swift`,
`Tests/CreatorGeometryTests/ProfileContainsTests.swift`, `Tests/CreatorNodesTests/Support/VariationFixtures.swift`, and edits to
`OutputNodeTests.swift` and `PatternsLibraryTests.swift`. Docs: `CLAUDE.md`, `docs/superpowers/roadmap.md`, the spec's Errata,
`docs/verification/human-checks.md`.

---

## Tasks

### Task 1: SeededRandom, the one generator

**Files:**

- Create: `Sources/CreatorNodes/Patterns/Variation/SeededRandom.swift`
- Test: `Tests/CreatorNodesTests/Variation/SeededRandomTests.swift` (new)

**Interfaces:**

- Consumes: Nothing.
- Produces: `struct SeededRandom: Sendable` (internal, `CreatorNodes`): `enum Purpose: UInt64` (`plain`, `reduce`, `values`, `jitter`); `init(seed: Int, stream: Int = 0, purpose: Purpose = .plain)`; `static func mix(_: UInt64) -> UInt64`;
`func value(at index: Int) -> UInt64` (draw `index` of the stream, reachable directly); `mutating func next() -> UInt64`;
`func unit(at index: Int) -> Double` (in [0, 1)); `func below(_ bound: Int, at index: Int) -> Int` (in 0 ..< bound, bound at least 1).

The generator comes first because everything random depends on it and its output is the contract: "the same seed gives the same
result on every machine and across releases". It is SplitMix64, written out in the repo; the tests pin the published seed-0 vector and the
first draws of other seeds, so a change to any step fails here before it changes a saved file.

Each random node draws for its own `Purpose` (User decision U7), which is mixed into the seed: `mix(seed ^ salt)`, the salt being the node's
name in ASCII with `_1` at the end (`Reduce_1`, `Values_1`, `Jitter_1`). Without it the three nodes' default seed 0 would give them the same
draw at the same place, and the items Random Reduce drops would be exactly the ones with the smallest Random Values. `Purpose.plain` is the
bare generator (the published vector); the three salts are pinned too, so changing one fails here.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorNodesTests/Variation/SeededRandomTests.swift`:

```swift
import Testing
@testable import CreatorNodes

/// The generator behind every random node (patterns spec §4: "the same seed gives the same result on every machine").
/// These numbers are pinned: if one changes, every saved file's random results change with it, so a failure here means the
/// algorithm was altered, not that the expectation is stale.
struct SeededRandomTests {
    /// SplitMix64's published test vector: seed 0 gives these four numbers first.
    @Test func seedZeroGivesSplitMix64sPublishedSequence() {
        var random = SeededRandom(seed: 0)
        #expect([random.next(), random.next(), random.next(), random.next()]
            == [0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4, 0x06C4_5D18_8009_454F, 0xF88B_B8A8_724C_81EC])
    }

    @Test(arguments: [
        (1, [0x910A_2DEC_8902_5CC1, 0xBEEB_8DA1_658E_EC67, 0xF893_A2EE_FB32_555E]),
        (42, [0xBDD7_3226_2FEB_6E95, 0x28EF_E333_B266_F103, 0x4752_6757_130F_9F52]),
        (-1, [0xE4D9_7177_1B65_2C20, 0xE99F_F867_DBF6_82C9, 0x382F_F84C_B272_81E9]),
    ] as [(Int, [UInt64])])
    func fixedSeedsGiveFixedNumbers(seed: Int, expected: [UInt64]) {
        var random = SeededRandom(seed: seed)
        #expect(expected.map { _ in random.next() } == expected)
    }

    @Test func streamsAreIndependentRunsOfTheSameSeed() {
        var first = SeededRandom(seed: 42, stream: 1)
        var second = SeededRandom(seed: 42, stream: 2)
        #expect((0..<3).map { _ in first.next() } == [0x57E1_FABA_6510_7204, 0xF4AB_D143_FEB2_4055, 0x7C81_6738_C129_03B2])
        #expect((0..<3).map { _ in second.next() } == [0xFC99_1BCA_1A1A_A1AE, 0x4F04_82A7_2B57_EE7D, 0x81BA_563D_5522_8AB4])
        #expect(SeededRandom(seed: 42, stream: 0).value(at: 0) == SeededRandom(seed: 42).value(at: 0), "stream 0 is the seed itself")
    }

    @Test func anyDrawCanBeReachedDirectlyAndMatchesTheSequence() {
        var sequential = SeededRandom(seed: 7, stream: 3)
        let direct = SeededRandom(seed: 7, stream: 3)
        for index in 0..<20 {
            #expect(sequential.next() == direct.value(at: index))
        }
    }

    @Test func theSameSeedGivesTheSameNumbersWhenAskedAgain() {
        let a = SeededRandom(seed: 99), b = SeededRandom(seed: 99)
        #expect((0..<50).map { a.value(at: $0) } == (0..<50).map { b.value(at: $0) })
        #expect(SeededRandom(seed: 100).value(at: 0) != a.value(at: 0))
    }

    @Test func realsArePinnedAndInsideZeroToOne() {
        let random = SeededRandom(seed: 42)
        #expect((0..<4).map { random.unit(at: $0) } == [0.7415648787718233, 0.1599103928769201, 0.27860113025513866, 0.34419071652363753])
        #expect((0..<1000).allSatisfy { (0.0..<1.0).contains(random.unit(at: $0)) })
    }

    @Test func wholeNumbersArePinnedAndBelowTheBound() {
        let random = SeededRandom(seed: 42)
        #expect((0..<8).map { random.below(10, at: $0) } == [7, 1, 2, 3, 0, 8, 2, 8])
        #expect((0..<8).map { random.below(6, at: $0) } == [4, 0, 1, 2, 0, 5, 1, 4])
        #expect((0..<1000).allSatisfy { (0..<7).contains(random.below(7, at: $0)) })
        #expect(random.below(1, at: 5) == 0)
    }

    @Test func eachWholeNumberTurnsUpAboutAsOftenAsTheOthers() {
        let random = SeededRandom(seed: 5)
        var counts = [Int](repeating: 0, count: 6)
        for index in 0..<6000 { counts[random.below(6, at: index)] += 1 }
        #expect(counts.allSatisfy { (850...1150).contains($0) }, "got \(counts)")
    }

    // MARK: purposes

    /// The numbers each random node draws for seed 42, pinned: they are what makes equal seeds on different nodes independent.
    @Test(arguments: [
        (SeededRandom.Purpose.reduce, [0xED46_CB32_7858_9E11, 0x2E0B_23F3_B198_49ED, 0x4754_6584_6F85_B6A6]),
        (.values, [0xF9BB_CEF4_C416_28FE, 0xA58E_6243_02BB_490E, 0x2860_470B_EC01_3B99]),
        (.jitter, [0x9673_367E_075B_CECA, 0xEDD4_89D4_9837_C26E, 0xC753_6F39_C67C_D7BC]),
    ] as [(SeededRandom.Purpose, [UInt64])])
    func eachPurposeHasItsOwnPinnedNumbers(purpose: SeededRandom.Purpose, expected: [UInt64]) {
        let random = SeededRandom(seed: 42, purpose: purpose)
        #expect((0..<3).map { random.value(at: $0) } == expected)
    }

    @Test func thePlainPurposeIsTheBareGeneratorAndAStreamStillStartsFromThePurposesSeed() {
        #expect(SeededRandom(seed: 42, purpose: .plain).value(at: 0) == SeededRandom(seed: 42).value(at: 0))
        let second = SeededRandom(seed: 42, stream: 2, purpose: .values)
        #expect([second.value(at: 0), second.value(at: 1)] == [0x5CAC_DAA9_7C6F_B7CC, 0xF62B_5C3A_1A2A_CAAA])
    }

    @Test func equalSeedsOnDifferentPurposesDrawDifferentNumbers() {
        for seed in -20..<50 {
            let firsts = [SeededRandom.Purpose.plain, .reduce, .values, .jitter].map { SeededRandom(seed: seed, purpose: $0).value(at: 0) }
            #expect(Set(firsts).count == 4, "seed \(seed)")
        }
    }
}
```


- [ ] **Step 2: Run them**

Run: `swift test --filter "SeededRandomTests" 2>&1 | grep -v 'ld: warning'`

Expected: FAIL, the tests do not build (`cannot find 'SeededRandom' in scope`).

- [ ] **Step 3: Write the implementation**

Create `Sources/CreatorNodes/Patterns/Variation/SeededRandom.swift`:

```swift
/// The app's one random generator (patterns spec §4: "always seeded"): SplitMix64, Steele, Lea and Flood, "Fast Splittable
/// Pseudorandom Number Generators" (OOPSLA 2014), in the public-domain form Sebastiano Vigna publishes. It is written out
/// here, never the system's generator, so a seed gives the same numbers on every machine and in every release; changing a
/// step below changes every random result in every saved file, so `SeededRandomTests` pins its output.
///
/// The algorithm: the state starts at the seed and every draw adds `step` to it, then scrambles it with `mix`. That makes
/// draw `k` a function of the seed and `k` alone, so `value(at:)` reaches any draw directly and the nodes draw by an item's
/// place, not by how many items came before: adding a branch or an item never reshuffles the others.
///
/// A purpose says which node is drawing. The plain generator starts at the seed itself; a purpose first mixes the seed with a
/// constant of its own (`mix(seed ^ salt)`), so two nodes given the same seed still draw unrelated numbers. The salts are part
/// of the contract like the algorithm: changing one changes every saved file's result for that node, and `SeededRandomTests`
/// pins them.
///
/// A stream is an independent run of draws for the same seed and purpose. Stream 0 starts at the (mixed) seed itself; stream `n`
/// starts at `mix(start + n × step)`. The nodes use a branch's number as its stream, so two branches don't repeat each other's numbers.
struct SeededRandom: Sendable {
    /// 2⁶⁴ divided by the golden ratio, rounded to an odd number.
    static let step: UInt64 = 0x9E37_79B9_7F4A_7C15

    /// Which node is drawing: the raw value is the salt mixed into the seed, the node's name in ASCII ending `_1`.
    enum Purpose: UInt64, Sendable {
        /// The bare generator (the published SplitMix64 sequence for seed 0), for tests of the generator itself.
        case plain = 0
        /// Random Reduce: "Reduce_1".
        case reduce = 0x5265_6475_6365_5F31
        /// Random Values: "Values_1".
        case values = 0x5661_6C75_6573_5F31
        /// Jitter: "Jitter_1".
        case jitter = 0x4A69_7474_6572_5F31
    }

    private let start: UInt64
    private var drawn = 0

    init(seed: Int, stream: Int = 0, purpose: Purpose = .plain) {
        var state = UInt64(truncatingIfNeeded: seed)
        if purpose != .plain { state = Self.mix(state ^ purpose.rawValue) }
        if stream != 0 { state = Self.mix(state &+ UInt64(truncatingIfNeeded: stream) &* Self.step) }
        start = state
    }

    /// SplitMix64's output function: two xor-shift-multiply rounds and a last xor-shift.
    static func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Draw `index` (counting from 0) of this stream.
    func value(at index: Int) -> UInt64 {
        Self.mix(start &+ UInt64(truncatingIfNeeded: index &+ 1) &* Self.step)
    }

    /// The next draw of this stream.
    mutating func next() -> UInt64 {
        defer { drawn += 1 }
        return value(at: drawn)
    }

    /// Draw `index` as a real in [0, 1): its top 53 bits over 2⁵³, so every value is exact in a `Double`.
    func unit(at index: Int) -> Double {
        Double(value(at: index) >> 11) * 0x1p-53
    }

    /// Draw `index` as a whole number in 0 ..< `bound` (`bound` at least 1): the draw's high bits scaled to the bound
    /// (multiply-high, no division), whose bias is below `bound` / 2⁶⁴.
    func below(_ bound: Int, at index: Int) -> Int {
        Int(value(at: index).multipliedFullWidth(by: UInt64(bound)).high)
    }
}
```


- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter "SeededRandomTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

- [ ] **Step 5: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > /tmp/vtest.log 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,650 = master + 11** (+11 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(7a-3b): SeededRandom, the SplitMix64 generator every random node draws from"
```

---

### Task 2: Culled lists in trees (paths kept through a cull)

**Files:**

- Create: `Sources/CreatorGraph/DataTree+Culling.swift`
- Create: `Sources/CreatorGraph/Value+Culled.swift`
- Modify: `Sources/CreatorGraph/BroadcastPlan.swift`
- Modify: `Sources/CreatorGraph/DataTree+Shape.swift`
- Modify: `Sources/CreatorGraph/DataTree.swift`
- Modify: `Sources/CreatorGraph/NodeInputs.swift`
- Modify: `Sources/CreatorGraph/TreeCursor.swift`
- Modify: `Sources/CreatorGraph/Value.swift`
- Test: `Tests/CreatorGraphTests/Trees/CulledTreeTests.swift` (new)

**Interfaces:**

- Consumes: 7a-1: `DataTree`, `Value.tree`, `TreePath`, `BroadcastPlan`, `TreeCursor`, `NodeInputs.tree`.
- Produces: `DataTree.culledList(_ scalars: [Scalar], at positions: [Int]) -> DataTree?` (nil unless one non-negative, strictly increasing index per
item); `isCulled: Bool`; `itemPositions: [Int]` (a flat list's indices; empty for a deeper tree); `culledPositions: [Int]?`;
`DataTree.Leaf` gains `positions: [Int]`, `isCulled: Bool` and `itemPath(_ k: Int) -> TreePath`;
`rebuildingLeaves(_ transform: (Leaf, _ ordinal: Int) -> LeafRewrite) -> DataTree`;
`keepingItems(where keep: (Leaf, _ ordinal: Int, _ k: Int) -> Bool) -> DataTree` (survivors keep their indices; an unchanged plain list stays plain);
`replacingItems(_ transform: (Leaf, _ ordinal: Int, _ k: Int) -> Scalar) -> DataTree`;
`NodeInputs.positions(_ name: SocketName) -> [Int]?`; `Value(_:)` returns `.tree` for a culled depth-1 tree; `DataTree.shapeText` adds ", culled".

This is the key extension (Key decisions 1 and 2): a flat list or branch that has had items taken out holds the survivors at the indices
they had. `DataTree` gains the optional per-item indices of a depth-1 tree, `Value(_:)` makes a culled depth-1 tree a `.tree`, broadcasting
treats it as a list (so a pattern node still runs once) and hands the indices to a `list` socket, and two builders (`keepingItems`,
`replacingItems`) are how every later node culls or refills a tree while keeping its nesting. Nothing existing changes form: a plain flat tree is
still a `.list`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorGraphTests/Trees/CulledTreeTests.swift`:

```swift
import Testing
@testable import CreatorGraph

/// Culling keeps paths (patterns spec §4): a flat list or a branch that has had items taken out holds the survivors at
/// the indices they had, so item `{3}` is still `{3}` when `{1}` is gone. `Value.list` cannot say that, so a culled flat
/// list is a `Value.tree` of depth 1.
struct CulledTreeTests {
    func numbers(_ values: [Int]) -> [Scalar] { values.map { .integer($0) } }

    func culled(_ values: [Int], at positions: [Int]) throws -> DataTree {
        try #require(DataTree.culledList(numbers(values), at: positions))
    }

    // MARK: building

    @Test func positionsMustFitTheItems() {
        #expect(DataTree.culledList(numbers([1, 2]), at: [0]) == nil, "one position short")
        #expect(DataTree.culledList(numbers([1, 2]), at: [2, 1]) == nil, "they must increase")
        #expect(DataTree.culledList(numbers([1, 2]), at: [1, 1]) == nil, "no two items share an index")
        #expect(DataTree.culledList(numbers([1, 2]), at: [-1, 0]) == nil, "none is negative")
        #expect(DataTree.culledList([], at: []) != nil, "everything culled is still a culled list")
    }

    @Test func aCulledListKeepsItsIndicesAndItsItems() throws {
        let tree = try culled([10, 30, 40], at: [0, 2, 3])
        #expect(tree.isCulled)
        #expect(tree.depth == 1)
        #expect(tree.itemPositions == [0, 2, 3])
        #expect(tree.culledPositions == [0, 2, 3])
        #expect(tree.items.map(\.outlineText) == ["10", "30", "40"])
        #expect(tree.itemCount == 3)
    }

    @Test func aPlainListIsNotCulledAndNumbersItsItemsFromZero() {
        let tree = DataTree.list(numbers([5, 6, 7]))
        #expect(!tree.isCulled)
        #expect(tree.itemPositions == [0, 1, 2])
        #expect(tree.culledPositions == nil)
    }

    @Test func aListCulledOnlyAtTheEndIsStillCulledSoTheEndDoesNotComeBack() throws {
        let tree = try culled([1, 2], at: [0, 1])
        #expect(tree.isCulled)
        #expect(tree.itemPositions == [0, 1])
    }

    // MARK: values

    @Test func aCulledFlatListIsATreeValueAndAPlainOneIsAList() throws {
        if case .tree(let tree) = Value(try culled([1], at: [4])) { #expect(tree.depth == 1) } else { Issue.record("expected a tree") }
        #expect(Value(.list(numbers([1, 2]))).isList)
    }

    @Test func aCulledListHasDepthOneAndItsItemsInOrder() throws {
        let value = Value(try culled([7, 8], at: [1, 5]))
        #expect(value.depth == 1)
        #expect(value.items.map(\.outlineText) == ["7", "8"])
        #expect(value.asTree?.itemPositions == [1, 5])
    }

    @Test func convertingAValueKeepsTheIndices() throws {
        let value = Value(try culled([1, 2], at: [3, 9]))
        let converted = try #require(value.converted(to: .number))
        #expect(converted.asTree?.itemPositions == [3, 9])
        #expect(converted.items.allSatisfy { if case .number = $0 { true } else { false } })
    }

    @Test func theShapeSaysCulled() throws {
        #expect(try culled([1, 2, 3], at: [0, 2, 3]).shapeText == "3, culled")
        let deeper = try #require(DataTree(depth: 2, branches: [culled([1], at: [2]), .list(numbers([4, 5]))]))
        #expect(deeper.shapeText == "2 branches: 1, 2, culled")
        #expect(DataTree.list(numbers([1, 2])).shapeText == "2")
    }

    // MARK: branches

    @Test func leavesReportEachBranchsIndicesAndItemPaths() throws {
        let tree = try #require(DataTree(depth: 2, branches: [culled([1, 2], at: [0, 3]), .list(numbers([5])), .list([])]))
        let leaves = tree.leaves
        #expect(leaves.map(\.positions) == [[0, 3], [0], []])
        #expect(leaves.map(\.isCulled) == [true, false, false])
        #expect(leaves[0].itemPath(1) == TreePath([0, 3]))
        #expect(leaves[1].itemPath(0) == TreePath([1, 0]))
    }

    @Test func keepingItemsLeavesGapsAndNoRenumbering() throws {
        let tree = try #require(DataTree(depth: 2, branches: [.list(numbers([0, 1, 2, 3])), .list(numbers([10, 11, 12]))]))
        let kept = tree.keepingItems { _, _, k in k != 1 }
        #expect(kept.outline == "[[0,2,3],[10,12]]")
        #expect(kept.leaves.map(\.positions) == [[0, 2, 3], [0, 2]])
        #expect(kept.isCulled)
    }

    @Test func keepingEverythingChangesNothingAndKeepsAPlainListPlain() {
        let tree = DataTree.list(numbers([1, 2, 3]))
        #expect(!tree.keepingItems { _, _, _ in true }.isCulled)
    }

    @Test func aBranchThatLosesEverythingStaysAsAnEmptyBranch() throws {
        let tree = try #require(DataTree(depth: 2, branches: [.list(numbers([1])), .list(numbers([2, 3]))]))
        let kept = tree.keepingItems { leaf, _, _ in leaf.path != TreePath([0]) }
        #expect(kept.outline == "[[],[2,3]]")
        #expect(kept.leaves.map(\.positions) == [[], [0, 1]])
        #expect(kept.branches.count == 2)
    }

    @Test func aSecondCullKeepsTheFirstOnesIndices() throws {
        let first = DataTree.list(numbers([0, 1, 2, 3, 4])).keepingItems { _, _, k in k != 1 }
        let second = first.keepingItems { _, _, k in k != 0 }
        #expect(second.itemPositions == [2, 3, 4], "k counts the survivors, the indices stay the original ones")
        #expect(second.items.map(\.outlineText) == ["2", "3", "4"])
    }

    @Test func rebuildingNumbersTheBranchesThatHoldItemsEvenWhenEmpty() throws {
        let tree = try #require(DataTree(depth: 2, branches: [.list([]), .list(numbers([1])), .list(numbers([2]))]))
        var seen: [Int] = []
        _ = tree.rebuildingLeaves { leaf, ordinal in
            seen.append(ordinal)
            return (leaf.items, leaf.positions, leaf.isCulled)
        }
        #expect(seen == [0, 1, 2])
    }

    @Test func replacingItemsKeepsTheNestingAndTheIndices() throws {
        let tree = try #require(DataTree(depth: 2, branches: [culled([1, 2], at: [1, 4]), .list(numbers([3]))]))
        let replaced = tree.replacingItems { leaf, ordinal, k in .integer(ordinal * 100 + leaf.positions[k]) }
        #expect(replaced.outline == "[[1,4],[100]]")
        #expect(replaced.leaves.map(\.positions) == [[1, 4], [0]])
    }

    // MARK: broadcasting

    let specs = [SocketSpec("a", .number, access: .list), SocketSpec("b", .number)]

    @Test func aCulledListOnAListSocketRunsOnceAndKeepsItsIndices() throws {
        let plan = BroadcastPlan.make(inputs: ["a": Value(try culled([1, 2, 3], at: [0, 2, 5]))], specs: specs)
        #expect(!plan.isTreeRun)
        #expect(plan.iterations == 1)
        let inputs = plan.inputs(at: 0)
        #expect(try inputs.list("a").count == 3)
        #expect(inputs.positions("a") == [0, 2, 5])
    }

    @Test func anOrdinaryListHasNoPositions() {
        let plan = BroadcastPlan.make(inputs: ["a": .list(numbers([1, 2]))], specs: specs)
        #expect(plan.inputs(at: 0).positions("a") == nil)
    }

    @Test func aCulledListOnAnItemSocketPairsItemsByTheirPlaceInTheList() throws {
        let reals = try #require(DataTree.culledList([5, 6, 7].map { .number(Double($0)) }, at: [1, 2, 8]))
        let plan = BroadcastPlan.make(inputs: ["a": .one(.number(0)), "b": Value(reals)], specs: specs)
        #expect(!plan.isTreeRun)
        #expect(plan.iterations == 3)
        #expect(try (0..<3).map { try plan.inputs(at: $0).number("b") } == [5, 6, 7])
    }

    @Test func aCulledListOnAListSocketBesideARealTreeKeepsItsIndices() throws {
        let tree = try #require(DataTree(depth: 2, branches: [.list(numbers([1, 2])), .list(numbers([3, 4]))]))
        let plan = BroadcastPlan.make(inputs: ["a": Value(try culled([1, 2], at: [0, 4])), "b": .tree(tree)], specs: specs)
        #expect(plan.isTreeRun)
        #expect(plan.iterations == 4)
        #expect(plan.inputs(at: 3).positions("a") == [0, 4])
    }

    @Test func aTreeAccessSocketGetsTheCulledTreeWhole() throws {
        let treeSpecs = [SocketSpec("t", .any, access: .tree)]
        let plan = BroadcastPlan.make(inputs: ["t": Value(try culled([1, 2], at: [3, 4]))], specs: treeSpecs)
        let tree = try plan.inputs(at: 0).tree("t")
        #expect(tree.itemPositions == [3, 4])
    }
}
```


- [ ] **Step 2: Run them**

Run: `swift test --filter "CulledTreeTests" 2>&1 | grep -v 'ld: warning'`

Expected: FAIL, the tests do not build (`type 'DataTree' has no member 'culledList'`).

- [ ] **Step 3: Write the implementation**

Create `Sources/CreatorGraph/DataTree+Culling.swift`:

```swift
extension DataTree {
    /// What `rebuildingLeaves` takes back for one branch: its new items, the index each one has in its branch (one per
    /// item), and whether the branch is culled (so those indices are kept as they are rather than counted).
    public typealias LeafRewrite = (items: [Scalar], positions: [Int], isCulled: Bool)

    /// The same nesting with every branch that holds items rewritten by `transform`, which gets the branch and its
    /// ordinal (0 for the first branch that holds items, 1 for the next, counting empty ones, and so on in tree order).
    /// Branches that are empty gaps stay as they are. A branch's ordinal is what the random nodes use as its stream.
    public func rebuildingLeaves(_ transform: (_ leaf: Leaf, _ ordinal: Int) -> LeafRewrite) -> DataTree {
        var ordinal = 0
        return rebuilt(under: TreePath(), ordinal: &ordinal, transform)
    }

    private func rebuilt(under path: TreePath, ordinal: inout Int,
                         _ transform: (_ leaf: Leaf, _ ordinal: Int) -> LeafRewrite) -> DataTree {
        if depth == 1 {
            let leaf = Leaf(path: path, items: items, positions: itemPositions, isCulled: isCulled)
            let rewritten = transform(leaf, ordinal)
            ordinal += 1
            guard rewritten.isCulled else { return .list(rewritten.items) }
            return DataTree.culledList(rewritten.items, at: rewritten.positions) ?? .list(rewritten.items)
        }
        var rebuiltBranches: [DataTree] = []
        for (index, branch) in branches.enumerated() {
            rebuiltBranches.append(branch.rebuilt(under: path.appending(index), ordinal: &ordinal, transform))
        }
        return DataTree(depth: depth, scalars: [], children: rebuiltBranches)
    }

    /// Culling (patterns spec §4: "culling keeps paths"): the same nesting with only the items `keep` accepts, `k` being
    /// the item's place in the branch it is in now. Survivors keep the indices they had, so a gap is left where an item
    /// was taken out and no later item moves; a branch that loses every item stays, empty. A branch that was culled
    /// before stays culled, and one that loses nothing is left as it was.
    public func keepingItems(where keep: (_ leaf: Leaf, _ ordinal: Int, _ k: Int) -> Bool) -> DataTree {
        rebuildingLeaves { leaf, ordinal in
            let kept = leaf.items.indices.filter { keep(leaf, ordinal, $0) }
            return (kept.map { leaf.items[$0] }, kept.map { leaf.positions[$0] }, leaf.isCulled || kept.count < leaf.items.count)
        }
    }

    /// The same nesting and the same indices with each item replaced by `transform(leaf, ordinal, k)`.
    public func replacingItems(_ transform: (_ leaf: Leaf, _ ordinal: Int, _ k: Int) -> Scalar) -> DataTree {
        rebuildingLeaves { leaf, ordinal in
            (leaf.items.indices.map { transform(leaf, ordinal, $0) }, leaf.positions, leaf.isCulled)
        }
    }
}
```


Create `Sources/CreatorGraph/Value+Culled.swift`:

```swift
extension Value {
    /// This value with a culled flat list's indices dropped: a plain `.list` of its items. For an item socket, which
    /// pairs items by their place in the list, so the gaps mean nothing to it. Any other value is returned as it is.
    var droppingCulls: Value {
        if case .tree(let tree) = self, tree.depth == 1 { .list(tree.items) } else { self }
    }
}
```


In `Sources/CreatorGraph/DataTree.swift`, directly after:

```swift
    private let scalars: [Scalar]
    private let children: [DataTree]
```

add:

```swift
    /// A flat list that has been culled: each item's index in its branch, strictly increasing. `nil` for a list that
    /// has not been (its items are 0, 1, 2…) and for every tree deeper than a list.
    private let slots: [Int]?
```


In `Sources/CreatorGraph/DataTree.swift`, replace:

```swift
    init(depth: Int, scalars: [Scalar], children: [DataTree]) {
        self.depth = depth
        self.scalars = scalars
        self.children = children
    }
```

with:

```swift
    init(depth: Int, scalars: [Scalar], children: [DataTree], slots: [Int]? = nil) {
        self.depth = depth
        self.scalars = scalars
        self.children = children
        self.slots = slots
    }

    /// A flat list that has been culled: its items keep the indices `positions` gives them (one per item, none
    /// negative, strictly increasing), so item `k` is still `{positions[k]}` and the gaps are the items taken out.
    /// Unlike a plain list it is kept as culled even when `positions` happens to be 0, 1, 2…, because what was taken
    /// off its end must not come back. `nil` when `positions` doesn't fit the items.
    public static func culledList(_ scalars: [Scalar], at positions: [Int]) -> DataTree? {
        guard positions.count == scalars.count, positions.allSatisfy({ $0 >= 0 }),
              zip(positions, positions.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        return DataTree(depth: 1, scalars: scalars, children: [], slots: positions)
    }

    /// True when some branch has been culled, so its items' indices are the ones they had, not 0, 1, 2…
    public var isCulled: Bool { depth == 1 ? slots != nil : children.contains { $0.isCulled } }

    /// A flat list's items' indices in their branch: 0, 1, 2… unless it was culled. Empty for a deeper tree.
    public var itemPositions: [Int] { depth == 1 ? (slots ?? Array(scalars.indices)) : [] }

    /// The indices of a culled flat list; `nil` for a plain list and for a deeper tree.
    public var culledPositions: [Int]? { depth == 1 ? slots : nil }
```


In `Sources/CreatorGraph/DataTree.swift`, replace:

```swift
    /// One branch holding items: its path (the item paths without their last index) and the items.
    public struct Leaf: Sendable {
        public var path: TreePath
        public var items: [Scalar]
    }
```

with:

```swift
    /// One branch holding items: its path (the item paths without their last index) and the items.
    public struct Leaf: Sendable {
        public var path: TreePath
        public var items: [Scalar]
        /// Each item's index in its branch: 0, 1, 2… unless the branch was culled, when the survivors keep the indices
        /// they had.
        public var positions: [Int]
        /// Whether the branch was culled (its `positions` are held, not counted).
        public var isCulled: Bool

        /// The full path of item `k` of this branch.
        public func itemPath(_ k: Int) -> TreePath { path.appending(positions[k]) }
    }
```


In `Sources/CreatorGraph/DataTree.swift`, replace:

```swift
        if depth == 1 { return [Leaf(path: path, items: scalars)] }
```

with:

```swift
        if depth == 1 { return [Leaf(path: path, items: scalars, positions: itemPositions, isCulled: slots != nil)] }
```


In `Sources/CreatorGraph/DataTree.swift`, replace:

```swift
            let mapped = scalars.compactMap(transform)
            return mapped.count == scalars.count ? .list(mapped) : nil
```

with:

```swift
            let mapped = scalars.compactMap(transform)
            guard mapped.count == scalars.count else { return nil }
            return DataTree(depth: 1, scalars: mapped, children: [], slots: slots)
```


In `Sources/CreatorGraph/Value.swift`, replace:

```swift
    /// Nested lists of depth 2 or more; `Value(_:)` turns a flat `DataTree` into a `.list`.
    case tree(DataTree)

    /// The value of `tree`: a flat list for depth 1, else `.tree`.
    public init(_ tree: DataTree) {
        self = tree.depth == 1 ? .list(tree.items) : .tree(tree)
    }
```

with:

```swift
    /// Nested lists of depth 2 or more, or a flat list that has been culled (`DataTree.isCulled`: its items keep the
    /// indices they had, which a `.list` cannot say); `Value(_:)` turns any other flat `DataTree` into a `.list`.
    case tree(DataTree)

    /// The value of `tree`: a flat list for a plain depth-1 tree, else `.tree`.
    public init(_ tree: DataTree) {
        self = tree.depth == 1 && !tree.isCulled ? .list(tree.items) : .tree(tree)
    }
```


In `Sources/CreatorGraph/DataTree+Shape.swift`, replace:

```swift
    public var shapeText: String {
        if let dimensions { return dimensions.map { $0.shapeNumber }.joined(separator: " × ") }
        let counts = leaves.map(\.items.count)
        let shown = counts.prefix(Self.shownCounts).map { $0.shapeNumber }.joined(separator: ", ")
        let more = counts.count > Self.shownCounts ? ", …" : ""
        return "\(counts.count.shapeNumber) \(counts.count == 1 ? "branch" : "branches"): \(shown)\(more)"
    }
```

with:

```swift
    public var shapeText: String {
        let culled = isCulled ? ", culled" : ""
        if let dimensions { return dimensions.map { $0.shapeNumber }.joined(separator: " × ") + culled }
        let counts = leaves.map(\.items.count)
        let shown = counts.prefix(Self.shownCounts).map { $0.shapeNumber }.joined(separator: ", ")
        let more = counts.count > Self.shownCounts ? ", …" : ""
        return "\(counts.count.shapeNumber) \(counts.count == 1 ? "branch" : "branches"): \(shown)\(more)\(culled)"
    }
```


In `Sources/CreatorGraph/NodeInputs.swift`, directly after:

```swift
    public func has(_ name: SocketName) -> Bool { slots[name] != nil }
```

add:

```swift

    /// The indices a culled flat list's items keep (`DataTree.culledPositions`): item `k` of `list(name)` is `{positions[k]}`.
    /// `nil` for anything that is not a culled flat list, whose items are 0, 1, 2….
    public func positions(_ name: SocketName) -> [Int]? {
        if case .tree(let tree)? = slots[name] { tree.culledPositions } else { nil }
    }
```


In `Sources/CreatorGraph/BroadcastPlan.swift`, replace:

```swift
    private let treeInputs: [SocketName: DataTree]
    /// Present when
```

with:

```swift
    private let treeInputs: [SocketName: DataTree]
    /// A culled flat list on a list socket: the node gets its items as the list and its indices from `NodeInputs.positions`.
    private let culledInputs: [SocketName: DataTree]
    /// Present when
```


In `Sources/CreatorGraph/BroadcastPlan.swift`, replace:

```swift
    init(iterations: Int, isSingle: Bool, itemInputs: [SocketName: Value], listInputs: [SocketName: [Scalar]],
         treeInputs: [SocketName: DataTree], nested: NestedIterations? = nil, warning: String? = nil,
         refusal: String? = nil) {
        self.iterations = iterations
        self.isSingle = isSingle
        self.itemInputs = itemInputs
        self.listInputs = listInputs
        self.treeInputs = treeInputs
```

with:

```swift
    init(iterations: Int, isSingle: Bool, itemInputs: [SocketName: Value], listInputs: [SocketName: [Scalar]],
         treeInputs: [SocketName: DataTree], culledInputs: [SocketName: DataTree] = [:], nested: NestedIterations? = nil,
         warning: String? = nil, refusal: String? = nil) {
        self.iterations = iterations
        self.isSingle = isSingle
        self.itemInputs = itemInputs
        self.listInputs = listInputs
        self.treeInputs = treeInputs
        self.culledInputs = culledInputs
```


In `Sources/CreatorGraph/BroadcastPlan.swift`, replace:

```swift
        let meetsTree = specs.contains { spec in
            if spec.access != .tree, case .tree? = inputs[spec.name] { true } else { false }
        }
```

with:

```swift
        let meetsTree = specs.contains { spec in
            // A culled flat list is a tree of depth 1 but broadcasts as a list, so only deeper trees need the nested plan.
            if spec.access != .tree, case .tree(let tree)? = inputs[spec.name] { tree.depth >= 2 } else { false }
        }
```


In `Sources/CreatorGraph/BroadcastPlan.swift`, replace:

```swift
        var treeInputs: [SocketName: DataTree] = [:]
        var counts: [Int] = []
        for spec in specs {
            guard let value = inputs[spec.name] else { continue }
            switch spec.access {
            case .list:
                listInputs[spec.name] = value.items
            case .tree:
                treeInputs[spec.name] = value.asTree ?? .list(value.items)
            case .item:
                itemInputs[spec.name] = value
                if case .list(let scalars) = value { counts.append(scalars.count) }
            }
        }
```

with:

```swift
        var treeInputs: [SocketName: DataTree] = [:]
        var culledInputs: [SocketName: DataTree] = [:]
        var counts: [Int] = []
        for spec in specs {
            guard let value = inputs[spec.name] else { continue }
            switch spec.access {
            case .list:
                listInputs[spec.name] = value.items
                if case .tree(let tree) = value { culledInputs[spec.name] = tree }
            case .tree:
                treeInputs[spec.name] = value.asTree ?? .list(value.items)
            case .item:
                let flat = value.droppingCulls
                itemInputs[spec.name] = flat
                if case .list(let scalars) = flat { counts.append(scalars.count) }
            }
        }
```


In `Sources/CreatorGraph/BroadcastPlan.swift`, replace:

```swift
            return BroadcastPlan(iterations: 1, isSingle: true, itemInputs: itemInputs, listInputs: listInputs,
                                 treeInputs: treeInputs)
```

with:

```swift
            return BroadcastPlan(iterations: 1, isSingle: true, itemInputs: itemInputs, listInputs: listInputs,
                                 treeInputs: treeInputs, culledInputs: culledInputs)
```


In `Sources/CreatorGraph/BroadcastPlan.swift`, replace:

```swift
        return BroadcastPlan(iterations: iterations, isSingle: false, itemInputs: itemInputs, listInputs: listInputs,
                             treeInputs: treeInputs)
```

with:

```swift
        return BroadcastPlan(iterations: iterations, isSingle: false, itemInputs: itemInputs, listInputs: listInputs,
                             treeInputs: treeInputs, culledInputs: culledInputs)
```


In `Sources/CreatorGraph/BroadcastPlan.swift`, directly after:

```swift
        for (name, scalars) in listInputs {
            slots[name] = .list(scalars)
        }
```

add:

```swift
        for (name, tree) in culledInputs {
            slots[name] = .tree(tree)
        }
```


In `Sources/CreatorGraph/TreeCursor.swift`, replace:

```swift
        case (.list, .tree(let tree)): .list(tree.items)
```

with:

```swift
        case (.list, .tree(let tree)):
            if tree.depth == 1, tree.isCulled { .tree(tree) } else { .list(tree.items) }
```


- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter "CulledTreeTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

- [ ] **Step 5: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > /tmp/vtest.log 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,670 = master + 31** (+20 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(7a-3b): culled lists, a flat tree whose items keep the indices they had"
```

---

### Task 3: Surviving instances keep their index

**Files:**

- Create: `Sources/CreatorKernel/Topology+InstanceItems.swift`
- Create: `Sources/CreatorNodes/Patterns/NodeInputs+PerInstance.swift`
- Create: `Sources/CreatorNodes/Patterns/PlacementSet.swift`
- Modify: `Sources/CreatorNodes/Patterns/BossPatternNode.swift`
- Modify: `Sources/CreatorNodes/Patterns/HolePatternNode.swift`
- Modify: `Sources/CreatorNodes/Patterns/PatternApply.swift`
- Modify: `Sources/CreatorNodes/Patterns/PatternFeatureNode.swift`
- Modify: `Sources/CreatorNodes/Patterns/PatternMisses.swift`
- Modify: `Sources/CreatorNodes/Patterns/PerInstance.swift`
- Modify: `Sources/CreatorNodes/Patterns/PlaceNode.swift`
- Modify: `Sources/CreatorNodes/Patterns/PlacementMoves.swift`
- Modify: `Sources/CreatorNodes/Patterns/PointsToPlacementsNode.swift`
- Modify: `Sources/CreatorNodes/Patterns/SlotPatternNode.swift`
- Test: `Tests/CreatorKernelTests/InstanceRenumberingTests.swift` (new)
- Test: `Tests/CreatorNodesTests/Variation/CulledInstancesTests.swift` (new)
- Test: `Tests/CreatorNodesTests/Variation/PointsToPlacementsCullTests.swift` (new)

**Interfaces:**

- Consumes: Task 2: `DataTree.culledList`, `NodeInputs.positions`; 7a-2: `PlaceNode`, the shortcuts, `PatternApply`, `PlacementMoves`, `PerInstance`, `PatternMisses`; `Topology.qualified(item:_:)`.
- Produces: `Topology.renumberingInstance(to item: Int) -> Topology` (CreatorKernel, public);
`struct PlacementSet { let planes: [Plane]; let culledIndices: [Int]?; func instances(alongside lengths: [Int]) -> [Int]; func planes(for instances: [Int]) -> [Plane] }`
and `NodeInputs.placementSet(_:)`; `PlacementMoves.copies(of:at:instances:placedBy:kernel:tag:) async throws -> [Solid]` replacing `PlacementMoves.make(_:count:)`
(now `make(_:instances:)`); `PerInstance(_:positions:)` with `span` and `NodeInputs.perInstanceNumbers/Bools/Integers/Solids/Vectors(_:)`;
`PatternApply.Request` gains `instances: [Int]` (its `tools` and `planes` are one per instance, in the same order) and `PatternApply.tools(_:for:)` takes a `PerInstance<Solid>`;
`PatternMisses.count(_:part:result:copies:instances:)`. Place outputs the copies of culled placements as a culled list; **Points to Placements turns a culled list of points into a culled list of placements** (Key decision 12).

Place and the four shortcuts must make exactly the instances a culled placement list holds, tag each copy with the index its placement had, and
read sizes and tools by that index. The cull may also sit **before** Points to Placements (Grid Points → Cull → Points to Placements), so that node
has to pass the indices on or the cull renumbers there; and a culled size or tool list must never set how many instances there are, however many
survivors it holds (`PerInstance.span`). This is the "naming" half of the track: until it is done a cull would shift every later pick to the next
hole (Key decisions 3 and 4). Dense graphs are unchanged, so the 7a-2 tests (`HolePatternNodeTests`, `PatternPickStabilityTests`, …) must pass
untouched; run them after Step 3. The tests call the nodes' `evaluate` directly with culled placements because no Cull node exists yet; the
graph-level naming test comes in Task 5.

After Step 3 also run the existing pattern suites, which the change must not move:
`swift test --filter "HolePatternNodeTests|BossPatternNodeTests|SlotPatternNodeTests|PatternFeatureNodeTests|PlaceNodeTests|PatternPickStabilityTests|GroupPatternNamingTests"`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorKernelTests/InstanceRenumberingTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorKernel

/// A copy made by `Kernel.place` is numbered by its place in the call; culling renumbers it to the index its placement had.
struct InstanceRenumberingTests {
    let tool = NodeID()

    /// A stand-in for `NodeID.instanceScoped` (CreatorGraph): a fixed map into version-8 IDs.
    func qualify(_ node: NodeID) -> NodeID {
        var bytes = node.rawValue.uuid
        bytes.6 = (bytes.6 & 0x0F) | 0x80
        bytes.0 ^= 0x5A
        return NodeID(rawValue: UUID(uuid: bytes))
    }

    func face(_ id: Int, _ tags: Set<TopoTag>) -> FaceInfo {
        FaceInfo(id: FaceID(id), kind: .cylinder, normal: nil, area: 1, centroid: .zero, tags: tags)
    }

    @Test func everyInstanceTagTakesTheNewItem() {
        let wall = TopoTag(node: tool, item: 0, role: .side(segment: 1))
        let cap = TopoTag(node: tool, item: 0, role: .endCap)
        let placed = Topology(faces: [face(0, [wall]), face(1, [cap])], edges: []).qualified(item: 1, qualify)
        let moved = placed.renumberingInstance(to: 6)
        #expect(moved.faces[0].tags == [TopoTag(node: qualify(tool), item: 6, role: .side(segment: 1))])
        #expect(moved.faces[1].tags == [TopoTag(node: qualify(tool), item: 6, role: .endCap)])
        #expect(moved.faces.map(\.id) == placed.faces.map(\.id), "faces and their order are untouched")
    }

    @Test func aBlendTagsSourceEdgeIsRenumberedToo() {
        let edge = EdgeKey([TopoTag(node: tool, item: 0, role: .side(segment: 1))], [TopoTag(node: tool, item: 0, role: .endCap)])
        let blend = TopoTag(node: tool, item: 0, role: .blend(sourceEdge: edge))
        let moved = Topology(faces: [face(0, [blend])], edges: []).qualified(item: 2, qualify).renumberingInstance(to: 9)
        let expected = EdgeKey([TopoTag(node: qualify(tool), item: 9, role: .side(segment: 1))],
                               [TopoTag(node: qualify(tool), item: 9, role: .endCap)])
        #expect(moved.faces[0].tags == [TopoTag(node: qualify(tool), item: 9, role: .blend(sourceEdge: expected))])
    }

    @Test func aTagThatIsNotAnInstancesIsLeftAlone() {
        let plain = TopoTag(node: tool, item: 3, role: .endCap)
        let moved = Topology(faces: [face(0, [plain])], edges: []).renumberingInstance(to: 8)
        #expect(moved.faces[0].tags == [plain])
    }
}
```


Create `Tests/CreatorNodesTests/Variation/PointsToPlacementsCullTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import Testing

/// Points to Placements and a cull (patterns spec §4, Key decision 12): a cull of the Grid Points must number the instances
/// as a cull of the placements would, so a culled list of points makes a culled list of placements at the same indices.
struct PointsToPlacementsCullTests {
    let kernel = FakeKernel()

    /// The inputs the evaluator would hand the node: every socket's default unless `given` sets it.
    func inputs(_ given: [SocketName: Value]) -> NodeInputs {
        var values: [SocketName: Value] = given
        for spec in PointsToPlacementsNode.inputs where values[spec.name] == nil {
            if let constant = spec.defaultValue, let scalar = Scalar(constant) { values[spec.name] = .one(scalar) }
        }
        return BroadcastPlan.make(inputs: values, specs: PointsToPlacementsNode.inputs).inputs(at: 0)
    }

    func context(isTreeRun: Bool = false) -> EvalContext {
        EvalContext(node: BuiltInNodes.registry.makeNode(PointsToPlacementsNode.typeID), item: 0, parameters: [:], isTreeRun: isTreeRun)
    }

    /// Points at x = 0, 20, 40, 60 with the ones in `kept` left, as a Cull node leaves them.
    func culledPoints(_ kept: [Int]) throws -> Value {
        Value(try #require(DataTree.culledList(kept.map { .vector(Vector3(Double($0) * 20, 0, 0)) }, at: kept)))
    }

    @Test func pointsToPlacementsKeepsACulledListsIndices() async throws {
        let outputs = try await PointsToPlacementsNode.evaluate(
            inputs(["points": try culledPoints([1, 2, 3])]),
            kernel: kernel, context: context())
        let tree = try #require(outputs.trees["placements"])
        #expect(tree.itemPositions == [1, 2, 3], "the first survivor is still {1}, not {0}")
        #expect(Value(tree).planes?.map(\.origin.x) == [20, 40, 60])
        #expect(outputs.warnings.isEmpty)
    }

    @Test func aCulledDirectionListIsReadByTheInstancesIndexAndSetsNoNumberOfPlacements() async throws {
        let directions = try #require(DataTree.culledList([.vector(.unitX), .vector(.unitY)], at: [0, 2]))
        let points = Value.list((0..<3).map { .vector(Vector3(Double($0) * 20, 0, 0)) })
        let outputs = try await PointsToPlacementsNode.evaluate(
            inputs(["points": points, "direction": Value(directions)]),
            kernel: kernel, context: context())
        let planes = try #require(outputs.lists["placements"].flatMap { Value.list($0).planes })
        #expect(planes.count == 3, "three points, three placements")
        #expect(zip(planes.map(\.normal), [Vector3.unitX, .unitX, .unitY]).allSatisfy { isClose($0, $1) }, "{1} takes {0}'s direction")
    }

    @Test func aCullThatRemovesEveryPointMakesAnEmptyCulledListOfPlacements() async throws {
        let outputs = try await PointsToPlacementsNode.evaluate(
            inputs(["points": try culledPoints([])]),
            kernel: kernel, context: context())
        let tree = try #require(outputs.trees["placements"])
        #expect(tree.isCulled && tree.itemCount == 0)
    }

    @Test func inATreeRunACulledBranchIsRenumberedAndSaysSo() async throws {
        let inTree = context(isTreeRun: true)
        let outputs = try await PointsToPlacementsNode.evaluate(
            inputs(["points": try culledPoints([1, 3])]), kernel: kernel, context: inTree)
        #expect(outputs.trees.isEmpty, "a node in a tree run returns one list per branch")
        #expect(outputs.lists["placements"]?.count == 2)
        #expect(outputs.warnings == ["Points to Placements numbers a culled branch from 0 again. Cull after it to keep the paths."])
        let whole = try await PointsToPlacementsNode.evaluate(
            inputs(["points": try culledPoints([0, 1])]), kernel: kernel, context: inTree)
        #expect(whole.warnings.isEmpty, "nothing was renumbered")
    }
}
```


Create `Tests/CreatorNodesTests/Variation/CulledInstancesTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import Testing

/// Culling keeps paths (patterns spec §4, §6): an instance whose placement survived a cull keeps its index in its tags,
/// its messages and its tool, so a pick on it follows it. Place and the shortcuts read culled placements here; the
/// Cull nodes that make them have their own tests.
struct CulledInstancesTests {
    let kernel = OCCTKernel()

    func plane(_ x: Double) -> Plane { .through(Vector3(x, 0, 0)) }

    /// Placements at x = 0, 20, 40, 60 with the instances in `kept` left, as a Cull node leaves them.
    func culled(_ kept: [Int]) throws -> Value {
        let tree = try #require(DataTree.culledList(kept.map { .plane(plane(Double($0) * 20)) }, at: kept))
        return Value(tree)
    }

    func plain(_ count: Int) -> Value { .list((0..<count).map { .plane(plane(Double($0) * 20)) }) }

    func block(height: Double = 10) async throws -> Solid {
        try await kernel.extrude(.rectangle(width: 10, height: 10, plane: .xy), distance: height, mode: .oneSided,
                                 tag: NodeTag(node: NodeID(), item: 0))
    }

    /// The inputs the evaluator would hand a node: every socket's default unless `given` sets it.
    func inputs(_ definition: any NodeDefinition.Type, _ given: [SocketName: Value]) -> NodeInputs {
        var values: [SocketName: Value] = given
        for spec in definition.inputs where values[spec.name] == nil {
            if let constant = spec.defaultValue, let scalar = Scalar(constant) { values[spec.name] = .one(scalar) }
        }
        return BroadcastPlan.make(inputs: values, specs: definition.inputs).inputs(at: 0)
    }

    func context(_ definition: any NodeDefinition.Type) -> EvalContext {
        EvalContext(node: BuiltInNodes.registry.makeNode(definition.typeID), item: 0, parameters: [:])
    }

    /// The solid a shortcut node made.
    func resultSolid(_ outputs: NodeOutputs) throws -> Solid {
        guard case .solid(let solid)? = outputs.values["solid"] else { throw NodeError.invalidValue("The node made no solid.") }
        return solid
    }

    /// The copies of a Place that left its copies as a culled tree.
    func copies(_ outputs: NodeOutputs) throws -> [Solid] {
        let tree = try #require(outputs.trees["solids"])
        return try #require(Value(tree).solids)
    }

    func items(of solid: Solid) -> Set<Int> {
        Set(solid.topology.faces.flatMap(\.tags).filter(\.node.isInstanceQualified).map(\.item))
    }

    // MARK: the set

    @Test func aPlainListMakesInstancesFromZeroAndTheLongestListSetsHowMany() {
        let set = PlacementSet(planes: [plane(0), plane(1)], culledIndices: nil)
        #expect(set.instances(alongside: []) == [0, 1])
        #expect(set.instances(alongside: [4, 1]) == [0, 1, 2, 3])
        #expect(set.planes(for: [0, 1, 2, 3]).map(\.origin.x) == [0, 1, 1, 1], "the shorter repeats its last")
    }

    @Test func anEmptyListMeansNoInstances() {
        #expect(PlacementSet(planes: [plane(0)], culledIndices: nil).instances(alongside: [0, 3]).isEmpty)
        #expect(PlacementSet(planes: [], culledIndices: nil).instances(alongside: [3]).isEmpty)
        #expect(PlacementSet(planes: [], culledIndices: []).instances(alongside: []).isEmpty)
    }

    @Test func aCulledListMakesExactlyTheInstancesItKeeps() {
        let set = PlacementSet(planes: [plane(0), plane(40)], culledIndices: [0, 2])
        #expect(set.instances(alongside: []) == [0, 2])
        #expect(set.instances(alongside: [9]) == [0, 2], "a longer size list adds none")
        #expect(set.planes(for: [0, 2]).map(\.origin.x) == [0, 40])
    }

    @Test func aSetIsReadFromTheSocket() throws {
        let set = try inputs(PlaceNode.self, ["placements": try culled([1, 3])]).placementSet("placements")
        #expect(set.culledIndices == [1, 3])
        #expect(set.planes.count == 2)
        #expect(try inputs(PlaceNode.self, ["placements": plain(2)]).placementSet("placements").culledIndices == nil)
    }

    // MARK: Place

    @Test func placeTagsEachCopyWithItsOriginalIndex() async throws {
        let tool = try await block()
        let given = inputs(PlaceNode.self, ["tool": .one(.solid(tool)), "placements": try culled([0, 2, 3])])
        let outputs = try await PlaceNode.evaluate(given, kernel: kernel, context: context(PlaceNode.self))
        let copies = try copies(outputs)
        #expect(copies.map { items(of: $0) } == [[0], [2], [3]])
        #expect(zip(copies.map(\.bounds.min.x), [-5, 35, 55]).allSatisfy { isClose($0, $1) }, "each copy stands on its own placement")
    }

    @Test func placeOutputsCulledCopiesAtTheirPaths() async throws {
        let outputs = try await PlaceNode.evaluate(
            inputs(PlaceNode.self, ["tool": .one(.solid(try await block())), "placements": try culled([1, 3])]),
            kernel: kernel, context: context(PlaceNode.self))
        let tree = try #require(outputs.trees["solids"])
        #expect(tree.itemPositions == [1, 3])
        #expect(tree.isCulled)
    }

    @Test func placeWithPlainPlacementsIsUnchanged() async throws {
        let outputs = try await PlaceNode.evaluate(
            inputs(PlaceNode.self, ["tool": .one(.solid(try await block())), "placements": plain(3)]),
            kernel: kernel, context: context(PlaceNode.self))
        #expect(outputs.trees.isEmpty)
        let copies = try #require(outputs.lists["solids"].flatMap { Value.list($0).solids })
        #expect(copies.map { items(of: $0) } == [[0], [1], [2]])
    }

    @Test func aSurvivingInstanceKeepsItsOwnTool() async throws {
        let tools = try await [block(height: 5), block(height: 6), block(height: 7), block(height: 8)]
        let outputs = try await PlaceNode.evaluate(
            inputs(PlaceNode.self, ["tool": .list(tools.map(Scalar.solid)), "placements": try culled([1, 3])]),
            kernel: kernel, context: context(PlaceNode.self))
        let copies = try copies(outputs)
        #expect(zip(copies.map(\.bounds.max.z), [6, 8]).allSatisfy { isClose($0, $1) }, "{1} has the second tool, {3} the fourth")
    }

    @Test func aLongerToolListAddsNoInstancesToCulledPlacements() async throws {
        let tools = try await [block(), block(), block(), block(), block()]
        let outputs = try await PlaceNode.evaluate(
            inputs(PlaceNode.self, ["tool": .list(tools.map(Scalar.solid)), "placements": try culled([0, 1])]),
            kernel: kernel, context: context(PlaceNode.self))
        #expect(try #require(outputs.trees["solids"]).itemCount == 2, "what was culled off the end stays gone")
    }

    @Test func aBadCulledPlacementNamesItsOwnPath() async throws {
        let bad = Plane(origin: .zero, normal: .zero, xAxis: .unitX)
        let tree = try #require(DataTree.culledList([.plane(plane(0)), .plane(bad)], at: [0, 5]))
        let given = inputs(PlaceNode.self, ["tool": .one(.solid(try await block())), "placements": Value(tree)])
        var message: String?
        do {
            _ = try await PlaceNode.evaluate(given, kernel: kernel, context: context(PlaceNode.self))
        } catch let error as NodeError {
            message = error.message
        }
        #expect(message?.hasPrefix("Placement {5} has no usable direction") == true, "got \(String(describing: message))")
    }

    // MARK: per-instance lists

    @Test func aPlainListRepeatsItsLastAndACulledOneIsReadByIndex() {
        let plain = PerInstance([10, 20])
        #expect([0, 1, 2, 5].map { plain[$0] } == [10, 20, 20, 20])
        let culled = PerInstance([10, 20, 30], positions: [1, 3, 4])
        #expect([0, 1, 2, 3, 4, 9].map { culled[$0] } == [10, 10, 10, 20, 30, 30],
                "its own value at its index, else the nearest one before it, else the first")
        #expect(culled.count == 3)
        #expect(culled.span == 1, "a culled list never sets the number of instances")
        #expect(plain.span == 2 && PerInstance<Int>([], positions: []).span == 0)
    }

    @Test func aCulledSizeListWithMoreSurvivorsThanPlacementsSetsNoNumberOfInstances() {
        let planes = (0..<4).map { plane(Double($0)) }
        let sizes = PerInstance(Array(repeating: 5.0, count: 10), positions: Array(10..<20))
        #expect(sizes.count == 10 && sizes.span == 1)
        let set = PlacementSet(planes: planes, culledIndices: nil)
        #expect(set.instances(alongside: [sizes.span]) == [0, 1, 2, 3], "ten survivors do not make ten instances")
        #expect(set.instances(alongside: [PerInstance<Double>([], positions: []).span]).isEmpty, "everything culled makes none")
    }

    @Test func aCulledSizeListLongerThanThePlacementsMakesNoExtraHoles() async throws {
        let sizes = try #require(DataTree.culledList(Array(repeating: Scalar.number(5), count: 10), at: Array(10..<20)))
        let given = inputs(HolePatternNode.self, [
            "part": .one(.solid(try await plate())), "placements": plain(4), "diameter": Value(sizes),
        ])
        let outputs = try await HolePatternNode.evaluate(given, kernel: kernel, context: context(HolePatternNode.self))
        #expect(items(of: try resultSolid(outputs)) == [0, 1, 2, 3], "four placements, four holes, all of {10}'s size")
    }

    @Test func aCulledSizeListWithNothingLeftMakesNoHoles() async throws {
        let part = try await plate()
        let none = try #require(DataTree.culledList([], at: []))
        let given = inputs(HolePatternNode.self, ["part": .one(.solid(part)), "placements": plain(3), "diameter": Value(none)])
        let outputs = try await HolePatternNode.evaluate(given, kernel: kernel, context: context(HolePatternNode.self))
        #expect(try resultSolid(outputs) === part)
        #expect(outputs.warnings.isEmpty)
    }

    @Test func aCulledToolListGivesEachSurvivorItsOwnTool() async throws {
        let tools = try await [block(height: 5), block(height: 6), block(height: 7)]
        let toolTree = try #require(DataTree.culledList(tools.map(Scalar.solid), at: [1, 2, 3]))
        let outputs = try await PlaceNode.evaluate(
            inputs(PlaceNode.self, ["tool": Value(toolTree), "placements": plain(4)]),
            kernel: kernel, context: context(PlaceNode.self))
        let placed = try #require(outputs.lists["solids"].flatMap { Value.list($0).solids })
        #expect(zip(placed.map(\.bounds.max.z), [5, 5, 6, 7]).allSatisfy { isClose($0, $1) }, "{0} has no tool of its own: the first")
        #expect(placed.count == 4, "a culled tool list sets no number of instances")
    }

    @Test func aCulledSizeListIsReadByTheInstancesIndex() async throws {
        let sizes = try #require(DataTree.culledList([.number(5), .number(-1)], at: [0, 3]))
        let given = inputs(HolePatternNode.self, [
            "part": .one(.solid(try await plate())), "placements": plain(4), "diameter": Value(sizes),
        ])
        var message: String?
        do {
            _ = try await HolePatternNode.evaluate(given, kernel: kernel, context: context(HolePatternNode.self))
        } catch let error as NodeError {
            message = error.message
        }
        #expect(message == "Hole {3}: the diameter must be greater than 0 mm.", "{1} and {2} took {0}'s 5 mm; {3} its own")
    }

    // MARK: the shortcuts

    /// A 160 × 40 × 6 plate standing on z = −6…0, so placements on z = 0 lie on its top face.
    func plate() async throws -> Solid {
        try await kernel.extrude(.rectangle(width: 160, height: 40, plane: .through(Vector3(0, 0, -6))), distance: 6, mode: .oneSided,
                                 tag: NodeTag(node: NodeID(), item: 0))
    }

    @Test func aHolePatternKeepsEachSurvivorsIndexAndDoesntCountTheCulledAsMissing() async throws {
        let part = try await plate()
        let outputs = try await HolePatternNode.evaluate(
            inputs(HolePatternNode.self, ["part": .one(.solid(part)), "placements": try culled([0, 2, 3])]),
            kernel: kernel, context: context(HolePatternNode.self))
        let solid = try resultSolid(outputs)
        #expect(items(of: solid) == [0, 2, 3], "got \(items(of: solid).sorted())")
        #expect(outputs.warnings.isEmpty, "no hole on {1} to miss the part: \(outputs.warnings)")
    }

    /// Hole sizes where only {1} is unusable.
    func holes(keeping kept: [Int]) async throws -> NodeInputs {
        let diameters = Value.list([5, -1, 5, 5].map { .number($0) })
        return inputs(HolePatternNode.self, [
            "part": .one(.solid(try await plate())), "placements": try culled(kept), "diameter": diameters,
        ])
    }

    @Test func aHolePatternReadsASizeByTheInstancesIndexAndNamesItsPath() async throws {
        var message: String?
        do {
            _ = try await HolePatternNode.evaluate(try await holes(keeping: [1, 3]), kernel: kernel,
                                                   context: context(HolePatternNode.self))
        } catch let error as NodeError {
            message = error.message
        }
        #expect(message == "Hole {1}: the diameter must be greater than 0 mm.")
    }

    @Test func aCulledInstancesSizeIsNeverRead() async throws {
        let outputs = try await HolePatternNode.evaluate(try await holes(keeping: [0, 2, 3]), kernel: kernel,
                                                         context: context(HolePatternNode.self))
        let solid = try resultSolid(outputs)
        #expect(items(of: solid) == [0, 2, 3], "got \(items(of: solid).sorted())")
    }

    @Test func aBossAndASlotAndAFeatureKeepIndicesToo() async throws {
        let part = try await plate()
        let placements = try culled([2, 3])
        for definition in [BossPatternNode.self, SlotPatternNode.self] as [any NodeDefinition.Type] {
            let outputs = try await definition.evaluate(inputs(definition, ["part": .one(.solid(part)), "placements": placements]),
                                                        kernel: kernel, context: context(definition))
            let solid = try resultSolid(outputs)
            #expect(items(of: solid) == [2, 3], "\(definition.typeID)")
        }
        let tool = try await block()
        let featureInputs = inputs(PatternFeatureNode.self, [
            "part": .one(.solid(part)), "tool": .one(.solid(tool)), "placements": placements,
        ])
        let feature = try await PatternFeatureNode.evaluate(featureInputs, kernel: kernel, context: context(PatternFeatureNode.self))
        let solid = try resultSolid(feature)
        #expect(items(of: solid) == [2, 3], "got \(items(of: solid).sorted())")
    }

    @Test func aCullThatRemovesEveryPlacementLeavesThePartAloneAndMakesNoCopies() async throws {
        let part = try await plate()
        let holes = try await HolePatternNode.evaluate(
            inputs(HolePatternNode.self, ["part": .one(.solid(part)), "placements": try culled([])]),
            kernel: kernel, context: context(HolePatternNode.self))
        #expect(try resultSolid(holes) === part)
        #expect(holes.warnings.isEmpty)
        let placed = try await PlaceNode.evaluate(
            inputs(PlaceNode.self, ["tool": .one(.solid(try await block())), "placements": try culled([])]),
            kernel: kernel, context: context(PlaceNode.self))
        #expect(try #require(placed.trees["solids"]).itemCount == 0)
    }

    @Test func aPlainPatternStillNumbersFromZero() async throws {
        let outputs = try await HolePatternNode.evaluate(
            inputs(HolePatternNode.self, ["part": .one(.solid(try await plate())), "placements": plain(3)]),
            kernel: kernel, context: context(HolePatternNode.self))
        let solid = try resultSolid(outputs)
        #expect(items(of: solid) == [0, 1, 2], "got \(items(of: solid).sorted())")
    }
}
```


- [ ] **Step 2: Run them**

Run: `swift test --filter "CulledInstancesTests|InstanceRenumberingTests|PointsToPlacementsCullTests" 2>&1 | grep -v 'ld: warning'`

Expected: FAIL, the tests do not build (`value of type 'Topology' has no member 'renumberingInstance'`, then `cannot find 'PlacementSet' in scope`).

- [ ] **Step 3: Write the implementation**

Create `Sources/CreatorKernel/Topology+InstanceItems.swift`:

```swift
extension Topology {
    /// This topology as the copy numbered `item` of a placed tool, for a copy that `Kernel.place` numbered otherwise: every
    /// instance-qualified tag (`NodeID.isInstanceQualified`, the ones `qualified(item:_:)` made) gets `item` as its item,
    /// its blend source edge's tags too. Faces, edges and their order are untouched. Culling uses it: a copy of the third
    /// survivor is `{4}` when the placement it stands on had the index 4 before the cull.
    public func renumberingInstance(to item: Int) -> Topology {
        var copy = self
        for index in copy.faces.indices {
            copy.faces[index].tags = Set(copy.faces[index].tags.map { $0.renumbered(to: item) })
        }
        return copy
    }
}

extension TopoTag {
    func renumbered(to item: Int) -> TopoTag {
        TopoTag(node: node, item: node.isInstanceQualified ? item : self.item, role: role.renumbered(to: item))
    }
}

extension TopoRole {
    func renumbered(to item: Int) -> TopoRole {
        guard case .blend(let edge) = self else { return self }
        return .blend(sourceEdge: EdgeKey(Set(edge.first.map { $0.renumbered(to: item) }),
                                          Set(edge.second.map { $0.renumbered(to: item) })))
    }
}
```


Create `Sources/CreatorNodes/Patterns/NodeInputs+PerInstance.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

extension NodeInputs {
    /// A `.list`-access socket read for a pattern's instances: its values, and the indices they keep when the list was culled.
    func perInstanceNumbers(_ name: SocketName) throws -> PerInstance<Double> {
        PerInstance(try numbers(name), positions: positions(name))
    }

    func perInstanceBools(_ name: SocketName) throws -> PerInstance<Bool> {
        PerInstance(try bools(name), positions: positions(name))
    }

    func perInstanceIntegers(_ name: SocketName) throws -> PerInstance<Int> {
        PerInstance(try integers(name), positions: positions(name))
    }

    func perInstanceSolids(_ name: SocketName) throws -> PerInstance<Solid> {
        PerInstance(try solids(name), positions: positions(name))
    }

    func perInstanceVectors(_ name: SocketName) throws -> PerInstance<Vector3> {
        PerInstance(try vectors(name), positions: positions(name))
    }
}
```


Create `Sources/CreatorNodes/Patterns/PlacementSet.swift`:

```swift
import CreatorGeometry
import CreatorGraph

/// The placements on a pattern node's `placements` socket and the instances they make (patterns spec §4: "culling keeps
/// paths"). An instance's index is the `{i}` in its tags and its messages, so a pick follows it.
///
/// A plain list makes the instances 0, 1, 2… and, as everywhere (spec §4.2), the longest of it and the node's other
/// per-instance lists sets how many, a shorter one repeating its last item. A culled list (a Cull node's output) makes
/// exactly the instances it still holds, at the indices they had before the cull: `{3}` is still `{3}` when `{1}` is
/// gone, a longer size list adds none, and what was culled off the end does not come back. A culled size or tool list never adds instances
/// either, however many survivors it holds. Sizes and tools are read by
/// the instance's index either way, so a surviving instance keeps its own size.
struct PlacementSet {
    let planes: [Plane]
    /// A culled list's instance indices, one per plane; `nil` for a plain list.
    let culledIndices: [Int]?

    /// The instances this set and the node's per-instance lists make. `lengths` are the lists' `PerInstance.span`s, not their
    /// counts: a plain list's span is its count and a culled list's is 1, or 0 when everything was culled. None if any is 0.
    func instances(alongside lengths: [Int]) -> [Int] {
        if planes.isEmpty || lengths.contains(0) { return [] }
        if let culledIndices { return culledIndices }
        return Array(0..<max(planes.count, lengths.max() ?? 0))
    }

    /// The placement of each of `instances` (from `instances(alongside:)`), in order.
    func planes(for instances: [Int]) -> [Plane] {
        guard culledIndices == nil, let last = planes.indices.last else { return planes }
        return instances.map { planes[min($0, last)] }
    }
}

extension NodeInputs {
    /// The `placements` of a pattern node: its planes, and the indices they keep when they were culled.
    func placementSet(_ name: SocketName) throws -> PlacementSet {
        PlacementSet(planes: try planes(name), culledIndices: positions(name))
    }
}
```


In `Sources/CreatorNodes/Patterns/PlacementMoves.swift`, replace:

```swift
    /// The move for each of `count` instances: instance `i` uses placement `i`, and a shorter list repeats its last
    /// placement (broadcasting, spec §4.2). A placement with no usable direction names its path.
    static func make(_ planes: [Plane], count: Int) throws -> [Transform] {
        guard let last = planes.indices.last else { return [] }
        var moves: [Transform] = []
        moves.reserveCapacity(count)
        for index in 0..<count {
            guard let move = planes[min(index, last)].placement else {
                throw NodeError.invalidValue("Placement \(InstancePath.text(index)) has no usable direction: "
                    + "its normal and x axis must not be zero or along each other.")
            }
            moves.append(move)
        }
        return moves
    }
```

with:

```swift
    /// The move for each instance: `planes[j]` is the placement of instance `instances[j]` (`PlacementSet.planes(for:)`).
    /// A placement with no usable direction names its instance's path.
    static func make(_ planes: [Plane], instances: [Int]) throws -> [Transform] {
        var moves: [Transform] = []
        moves.reserveCapacity(instances.count)
        for (plane, instance) in zip(planes, instances) {
            guard let move = plane.placement else {
                throw NodeError.invalidValue("Placement \(InstancePath.text(instance)) has no usable direction: "
                    + "its normal and x axis must not be zero or along each other.")
            }
            moves.append(move)
        }
        return moves
    }

    /// One copy of `tools[j]` on `planes[j]` for each instance `instances[j]`, in one kernel call. The copy's tags name
    /// the instance (`instances[j]`), not its place `j` in this call, so a copy keeps its index when other instances were
    /// culled: `Kernel.place` numbers the copies 0, 1, 2…, and any whose instance is another number is renumbered.
    static func copies(of tools: [Solid], at planes: [Plane], instances: [Int], placedBy place: NodeID, kernel: any Kernel,
                       tag: NodeTag) async throws -> [Solid] {
        let moves = try make(planes, instances: instances)
        let placed = try await kernel.place(tools, at: moves, qualifying: qualifier(placedBy: place), tag: tag)
        return zip(placed, instances).enumerated().map { slot, pair in
            let (copy, instance) = pair
            guard instance != slot else { return copy }
            return Solid(topology: copy.topology.renumberingInstance(to: instance), bounds: copy.bounds, storage: copy.storage)
        }
    }
```


In `Sources/CreatorNodes/Patterns/PlaceNode.swift`, replace:

```swift
        let tools = try inputs.solids("tool")
        let planes = try inputs.planes("placements")
        let count = tools.isEmpty || planes.isEmpty ? 0 : max(tools.count, planes.count)
        try PatternLimit.check(count)
        let moves = try PlacementMoves.make(planes, count: count)
        let used = (0..<count).map { tools[min($0, tools.count - 1)] }
        let copies = try await kernel.place(used, at: moves, qualifying: PlacementMoves.qualifier(placedBy: context.node.id),
                                            tag: context.tag)
        return NodeOutputs(lists: ["solids": copies.map(Scalar.solid)])
```

with:

```swift
        let tools = try inputs.perInstanceSolids("tool")
        let placements = try inputs.placementSet("placements")
        let instances = placements.instances(alongside: [tools.span])
        try PatternLimit.check(instances.count)
        let used = instances.map { tools[$0] }
        let copies = try await PlacementMoves.copies(of: used, at: placements.planes(for: instances), instances: instances,
                                                     placedBy: context.node.id, kernel: kernel, tag: context.tag)
        // Copies of culled placements are a culled list too, so each copy is still at its instance's path.
        guard placements.culledIndices != nil, let culled = DataTree.culledList(copies.map(Scalar.solid), at: instances) else {
            return NodeOutputs(lists: ["solids": copies.map(Scalar.solid)])
        }
        return NodeOutputs(trees: ["solids": culled])
```


In `Sources/CreatorNodes/Patterns/PointsToPlacementsNode.swift`, replace:

```swift
/// built on Grid Points over to Place without redrawing them. Points and directions broadcast: the longer list sets
/// the number of placements and the shorter repeats its last item.
```

with:

```swift
/// built on Grid Points over to Place without redrawing them. Points and directions broadcast: the longer list sets
/// the number of placements and the shorter repeats its last item. Culling keeps paths (spec §4): a culled list of points (a
/// Cull node's output, `NodeInputs.positions`) makes exactly the placements at the indices the points kept, as a culled
/// list too, so a cull before this node numbers the instances as one after it would. A direction list is read by that
/// index (`PerInstance`), and a culled one sets no number of placements.
```


In `Sources/CreatorNodes/Patterns/PointsToPlacementsNode.swift`, replace:

```swift
        let points = try inputs.vectors("points")
        let directions = try inputs.vectors("direction")
        let count = points.isEmpty || directions.isEmpty ? 0 : max(points.count, directions.count)
        try PatternLimit.check(count)
        var planes: [Scalar] = []
        planes.reserveCapacity(count)
        for index in 0..<count {
            guard let normal = directions[min(index, directions.count - 1)].normalized else {
                throw NodeError.invalidValue("The direction of placement \(InstancePath.text(index)) can't be zero.")
            }
            planes.append(.plane(FacePlane.plane(origin: points[min(index, points.count - 1)], normal: normal)))
        }
        return NodeOutputs(lists: ["placements": planes])
    }
```

with:

```swift
        let points = try inputs.perInstanceVectors("points")
        let directions = try inputs.perInstanceVectors("direction")
        let instances = Self.instances(points: points, directions: directions)
        try PatternLimit.check(instances.count)
        var planes: [Scalar] = []
        planes.reserveCapacity(instances.count)
        for instance in instances {
            guard let normal = directions[instance].normalized else {
                throw NodeError.invalidValue("The direction of placement \(InstancePath.text(instance)) can't be zero.")
            }
            planes.append(.plane(FacePlane.plane(origin: points[instance], normal: normal)))
        }
        guard let kept = points.positions else { return NodeOutputs(lists: ["placements": planes]) }
        // Inside a tree run the node makes one list per branch, so a culled branch can only come out renumbered (User decision U15).
        if context.isTreeRun {
            let gaps = kept != Array(0..<kept.count)
            return NodeOutputs(lists: ["placements": planes], warnings: gaps ? [Self.renumberedWarning] : [])
        }
        guard let culled = DataTree.culledList(planes, at: kept) else { return NodeOutputs(lists: ["placements": planes]) }
        return NodeOutputs(trees: ["placements": culled])
    }

    static let renumberedWarning = "Points to Placements numbers a culled branch from 0 again. Cull after it to keep the paths."

    /// The placements to make: none if either list is empty; exactly the indices a culled list of points keeps; otherwise 0, 1, 2…
    /// as many as the longer list says (a culled direction list sets no number).
    private static func instances(points: PerInstance<Vector3>, directions: PerInstance<Vector3>) -> [Int] {
        if points.count == 0 || directions.count == 0 { return [] }
        if let kept = points.positions { return kept }
        return Array(0..<max(points.count, directions.span))
    }
```


In `Sources/CreatorNodes/Patterns/PatternApply.swift`, replace:

```swift
    /// What a shortcut asks for: `operation` of `part` with a copy of `tools[i]` at every instance `i`, placed on
    /// `planes[min(i, planes.count - 1)]`.
    struct Request {
        let operation: BooleanOp
        let part: Solid
        let tools: [Solid]
        let planes: [Plane]
        let nouns: Nouns
    }
```

with:

```swift
    /// What a shortcut asks for: `operation` of `part` with a copy of `tools[j]` on `planes[j]` for each instance
    /// `instances[j]` (`PlacementSet.instances(alongside:)`: 0, 1, 2… for a plain list, the surviving indices for a culled
    /// one). The three lists are the same length.
    struct Request {
        let operation: BooleanOp
        let part: Solid
        let tools: [Solid]
        let planes: [Plane]
        let instances: [Int]
        let nouns: Nouns
    }
```


In `Sources/CreatorNodes/Patterns/PatternApply.swift`, replace:

```swift
        let (op, part, tools, planes) = (request.operation, request.part, request.tools, request.planes)
        let count = planes.isEmpty ? 0 : tools.count
        try PatternLimit.check(count)
        guard count > 0 else { return NodeOutputs(["solid": .solid(part)]) }
        let moves = try PlacementMoves.make(planes, count: count)
        let copies = try await kernel.place(tools, at: moves, qualifying: PlacementMoves.qualifier(placedBy: context.node.id),
                                            tag: context.tag)
        let result = try await kernel.boolean(op, part, copies, tag: context.tag)
        var warnings = PieceWarning.warnings(for: result)
        let missed = PatternMisses.count(op, part: part, result: result, copies: copies)
        let nouns = request.nouns
        if let message = PatternMisses.warning(missed: missed, of: count, singular: nouns.singular, plural: nouns.plural) {
```

with:

```swift
        let (op, part, instances) = (request.operation, request.part, request.instances)
        try PatternLimit.check(instances.count)
        guard !instances.isEmpty else { return NodeOutputs(["solid": .solid(part)]) }
        let copies = try await PlacementMoves.copies(of: request.tools, at: request.planes, instances: instances,
                                                     placedBy: context.node.id, kernel: kernel, tag: context.tag)
        let result = try await kernel.boolean(op, part, copies, tag: context.tag)
        var warnings = PieceWarning.warnings(for: result)
        let missed = PatternMisses.count(op, part: part, result: result, copies: copies, instances: instances)
        let nouns = request.nouns
        if let message = PatternMisses.warning(missed: missed, of: instances.count, singular: nouns.singular, plural: nouns.plural) {
```


In `Sources/CreatorNodes/Patterns/PatternApply.swift`, replace:

```swift
    /// The tool for each of the instances that `tools` and `planes` make together: the longer list sets the number
    /// of instances and the shorter repeats its last item (broadcasting, spec §4.2).
    static func tools(_ tools: [Solid], planes: [Plane]) -> [Solid] {
        guard let last = tools.indices.last, !planes.isEmpty else { return [] }
        return (0..<max(tools.count, planes.count)).map { tools[min($0, last)] }
    }
```

with:

```swift
    /// The tool for each of `instances`, by the instance's index: a list of tools gives a surviving instance its own tool,
    /// and a list shorter than the index repeats its last (broadcasting, spec §4.2).
    static func tools(_ tools: PerInstance<Solid>, for instances: [Int]) -> [Solid] {
        tools.values.isEmpty ? [] : instances.map { tools[$0] }
    }
```


In `Sources/CreatorNodes/Patterns/PatternMisses.swift`, replace:

```swift
    static func count(_ op: BooleanOp, part: Solid, result: Solid, copies: [Solid]) -> Int {
```

with:

```swift
    /// `instances[j]` is the index copy `j` carries in its tags (a cull leaves gaps in the numbering).
    static func count(_ op: BooleanOp, part: Solid, result: Solid, copies: [Solid], instances: [Int]) -> Int {
```


In `Sources/CreatorNodes/Patterns/PatternMisses.swift`, replace:

```swift
            return copies.indices.filter { !present.contains($0) }.count
```

with:

```swift
            return instances.filter { !present.contains($0) }.count
```


In `Sources/CreatorNodes/Patterns/PatternFeatureNode.swift`, replace:

```swift
        let planes = try inputs.planes("placements")
        let tools = PatternApply.tools(try inputs.solids("tool"), planes: planes)
        let request = PatternApply.Request(operation: op, part: try inputs.solid("part"), tools: tools, planes: planes,
                                           nouns: PatternApply.Nouns(singular: "feature", plural: "features"))
```

with:

```swift
        let placements = try inputs.placementSet("placements")
        let tools = try inputs.perInstanceSolids("tool")
        let instances = placements.instances(alongside: [tools.span])
        let request = PatternApply.Request(operation: op, part: try inputs.solid("part"),
                                           tools: PatternApply.tools(tools, for: instances),
                                           planes: placements.planes(for: instances), instances: instances,
                                           nouns: PatternApply.Nouns(singular: "feature", plural: "features"))
```


In `Sources/CreatorNodes/Patterns/BossPatternNode.swift`, replace:

```swift
        let planes = try inputs.planes("placements")
        let (diameters, heights) = (PerInstance(try inputs.numbers("diameter")), PerInstance(try inputs.numbers("height")))
        let (drafts, fillets) = (PerInstance(try inputs.numbers("draft")), PerInstance(try inputs.numbers("tipFillet")))
        let count = PerInstance<Plane>.instances([planes.count, diameters.count, heights.count, drafts.count, fillets.count])
        try PatternLimit.check(count)
        guard count > 0 else { return NodeOutputs(["solid": .solid(part)]) }
        var sizes: [BossSize] = []
        for index in 0..<count {
            let size = BossSize(diameter: diameters[index], height: heights[index], draft: .degrees(drafts[index]),
                                tipFillet: fillets[index])
            if let problem = size.problem(at: InstancePath.text(index)) { throw NodeError.invalidValue(problem) }
```

with:

```swift
        let placements = try inputs.placementSet("placements")
        let (diameters, heights) = (try inputs.perInstanceNumbers("diameter"), try inputs.perInstanceNumbers("height"))
        let (drafts, fillets) = (try inputs.perInstanceNumbers("draft"), try inputs.perInstanceNumbers("tipFillet"))
        let instances = placements.instances(alongside: [diameters.span, heights.span, drafts.span, fillets.span])
        try PatternLimit.check(instances.count)
        guard !instances.isEmpty else { return NodeOutputs(["solid": .solid(part)]) }
        var sizes: [BossSize] = []
        for index in instances {
            let size = BossSize(diameter: diameters[index], height: heights[index], draft: .degrees(drafts[index]),
                                tipFillet: fillets[index])
            if let problem = size.problem(at: InstancePath.text(index)) { throw NodeError.invalidValue(problem) }
```


In `Sources/CreatorNodes/Patterns/BossPatternNode.swift`, replace:

```swift
tools: plan.toolIndex.map { built[$0] }, planes: planes,
                                           nouns: PatternApply.Nouns(singular: "boss", plural: "bosses"))
```

with:

```swift
tools: plan.toolIndex.map { built[$0] },
                                           planes: placements.planes(for: instances), instances: instances,
                                           nouns: PatternApply.Nouns(singular: "boss", plural: "bosses"))
```


In `Sources/CreatorNodes/Patterns/SlotPatternNode.swift`, replace:

```swift
        let planes = try inputs.planes("placements")
        let (lengths, widths) = (PerInstance(try inputs.numbers("length")), PerInstance(try inputs.numbers("width")))
        let (depths, through) = (PerInstance(try inputs.numbers("depth")), PerInstance(try inputs.bools("throughAll")))
        let count = PerInstance<Plane>.instances([planes.count, lengths.count, widths.count, depths.count, through.count])
        try PatternLimit.check(count)
        guard count > 0 else { return NodeOutputs(["solid": .solid(part)]) }
        let reach = through.values.contains(true) ? ThroughReach.length(of: part, placements: planes) : 0
        var sizes: [SlotSize] = []
        for index in 0..<count {
```

with:

```swift
        let placements = try inputs.placementSet("placements")
        let (lengths, widths) = (try inputs.perInstanceNumbers("length"), try inputs.perInstanceNumbers("width"))
        let (depths, through) = (try inputs.perInstanceNumbers("depth"), try inputs.perInstanceBools("throughAll"))
        let instances = placements.instances(alongside: [lengths.span, widths.span, depths.span, through.span])
        try PatternLimit.check(instances.count)
        guard !instances.isEmpty else { return NodeOutputs(["solid": .solid(part)]) }
        let reach = through.values.contains(true) ? ThroughReach.length(of: part, placements: placements.planes) : 0
        var sizes: [SlotSize] = []
        for index in instances {
```


In `Sources/CreatorNodes/Patterns/SlotPatternNode.swift`, replace:

```swift
tools: plan.toolIndex.map { built[$0] }, planes: planes,
                                           nouns: PatternApply.Nouns(singular: "slot", plural: "slots"))
```

with:

```swift
tools: plan.toolIndex.map { built[$0] },
                                           planes: placements.planes(for: instances), instances: instances,
                                           nouns: PatternApply.Nouns(singular: "slot", plural: "slots"))
```


In `Sources/CreatorNodes/Patterns/HolePatternNode.swift`, replace:

```swift
        let planes = try inputs.planes("placements")
        let values = (diameters
```

with:

```swift
        let placements = try inputs.placementSet("placements")
        let values = (diameters
```


In `Sources/CreatorNodes/Patterns/HolePatternNode.swift`, replace:

```swift
        let count = PerInstance<Plane>.instances([
            planes.count, values.diameters.count, values.depths.count, values.through.count, values.styles.count,
            values.cbDiameters.count, values.cbDepths.count, values.csDiameters.count, values.csAngles.count,
        ])
        try PatternLimit.check(count)
        guard count > 0 else { return NodeOutputs(["solid": .solid(part)]) }
        let reach = values.through.values.contains(true) ? ThroughReach.length(of: part, placements: planes) : 0
        var sizes: [HoleSize] = []
        for index in 0..<count {
```

with:

```swift
        let instances = placements.instances(alongside: [
            values.diameters.span, values.depths.span, values.through.span, values.styles.span,
            values.cbDiameters.span, values.cbDepths.span, values.csDiameters.span, values.csAngles.span,
        ])
        try PatternLimit.check(instances.count)
        guard !instances.isEmpty else { return NodeOutputs(["solid": .solid(part)]) }
        let reach = values.through.values.contains(true) ? ThroughReach.length(of: part, placements: placements.planes) : 0
        var sizes: [HoleSize] = []
        for index in instances {
```


In `Sources/CreatorNodes/Patterns/HolePatternNode.swift`, replace:

```swift
tools: plan.toolIndex.map { built[$0] }, planes: planes,
                                           nouns: PatternApply.Nouns(singular: "hole", plural: "holes"))
```

with:

```swift
tools: plan.toolIndex.map { built[$0] },
                                           planes: placements.planes(for: instances), instances: instances,
                                           nouns: PatternApply.Nouns(singular: "hole", plural: "holes"))
```


In `Sources/CreatorNodes/Patterns/HolePatternNode.swift`, replace:

```swift
        let values = (diameters: PerInstance(try inputs.numbers("diameter")), depths: PerInstance(try inputs.numbers("depth")),
                      through: PerInstance(try inputs.bools("throughAll")), styles: PerInstance(try inputs.integers("style")),
                      cbDiameters: PerInstance(try inputs.numbers("counterboreDiameter")),
                      cbDepths: PerInstance(try inputs.numbers("counterboreDepth")),
                      csDiameters: PerInstance(try inputs.numbers("countersinkDiameter")),
                      csAngles: PerInstance(try inputs.numbers("countersinkAngle")))
```

with:

```swift
        let values = (diameters: try inputs.perInstanceNumbers("diameter"), depths: try inputs.perInstanceNumbers("depth"),
                      through: try inputs.perInstanceBools("throughAll"), styles: try inputs.perInstanceIntegers("style"),
                      cbDiameters: try inputs.perInstanceNumbers("counterboreDiameter"),
                      cbDepths: try inputs.perInstanceNumbers("counterboreDepth"),
                      csDiameters: try inputs.perInstanceNumbers("countersinkDiameter"),
                      csAngles: try inputs.perInstanceNumbers("countersinkAngle"))
```


In `Sources/CreatorNodes/Patterns/PerInstance.swift`, replace:

```swift
/// An input that varies by instance (patterns spec §5): one value per item of a list, and a shorter list repeats its
/// last item, as broadcasting does everywhere (spec §4.2). A shortcut node takes its sizes as lists so it can make
/// one kernel call for all its instances, and reads them through this.
struct PerInstance<Value> {
    let values: [Value]

    init(_ values: [Value]) {
        self.values = values
    }

    var count: Int { values.count }

    /// The value for instance `index`, repeating the last. Only call it on a list with a value in it.
    subscript(index: Int) -> Value { values[min(index, values.count - 1)] }
```

with:

```swift
/// An input that varies by instance (patterns spec §5): one value per item of a list, and a shorter list repeats its
/// last item, as broadcasting does everywhere (spec §4.2). A shortcut node takes its sizes as lists so it can make
/// one kernel call for all its instances, and reads them through this.
///
/// A list that was culled (a Cull node's or Random Values' output, `positions` set) holds its values at the indices they
/// had, so instance `i` takes the value at index `i`; where that one was culled it takes the nearest one before it (the
/// first, if none), the way a shorter plain list repeats its last. A culled list's `count` is the values it still holds, but it
/// does not set how many instances there are: its `span` does the telling (`PlacementSet.instances(alongside:)`).
struct PerInstance<Value> {
    let values: [Value]
    /// A culled list's indices, one per value; `nil` for a plain list.
    let positions: [Int]?

    init(_ values: [Value], positions: [Int]? = nil) {
        self.values = values
        self.positions = positions
    }

    var count: Int { values.count }

    /// What this list says about how many instances there are. A plain list says its `count`, as everywhere (the longest list
    /// sets the number). A culled list's survivors sit at indices of their own, so however many it holds it sets no number: its
    /// span is 1 when it holds anything (no placement list is shorter than that) and 0 when everything was culled, which makes
    /// no instances, as an empty plain list does.
    var span: Int { positions == nil ? values.count : min(values.count, 1) }

    /// The value for instance `index`. Only call it on a list with a value in it.
    subscript(index: Int) -> Value {
        guard let positions else { return values[min(index, values.count - 1)] }
        return values[positions.lastIndex { $0 <= index } ?? 0]
    }
```


- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter "CulledInstancesTests|InstanceRenumberingTests|PointsToPlacementsCullTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

- [ ] **Step 5: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > /tmp/vtest.log 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,699 = master + 60** (+29 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(7a-3b): Place and the shortcuts keep a surviving instance's index, its tags and its sizes"
```

---

### Task 4: Cull Pattern

**Files:**

- Create: `Sources/CreatorNodes/Patterns/Variation/CullMask.swift`
- Create: `Sources/CreatorNodes/Patterns/Variation/CullPatternNode.swift`
- Modify: `Sources/CreatorGraph/NodeSetting.swift`
- Modify: `Sources/CreatorNodes/BuiltInNodes.swift`
- Test: `Tests/CreatorNodesTests/Support/VariationFixtures.swift` (new)
- Test: `Tests/CreatorNodesTests/Variation/CullPatternNodeTests.swift` (new)
- Test: `Tests/CreatorEditorTests/PatternsLibraryTests.swift` (modify)
- Test: `Tests/CreatorNodesTests/OutputNodeTests.swift` (modify)

**Interfaces:**

- Consumes: Task 2: `keepingItems(where:)`; `NodeInputs.bools(_:)` (Patterns support).
- Produces: `CullPatternNode` (`creator.cullPattern`, inputs `tree` (any, tree), `keep` (bool list, optional), output `tree`; setting `NodeSetting.cullPattern`, default `"1 0"`);
`CullMask.parse(_:)`; test fixtures `TreeSource`, `Harness.source(count:rows:)`, `Harness.wire(_ source:to:_:)`, `EvaluationReport.tree(_:_:)`, `EvaluationReport.positions(_:_:)`.

The first node, and the shared test fixtures (`TreeSource`, `Harness.source(count:rows:)`, `EvaluationReport.positions`). The mask is the saved text
`cullPattern` (`1 0`, `T F T`), or a wired `keep` list; it repeats across each branch over the items the branch has now (User decision U2) and
`1` keeps (U1). Registering the node updates the node count, the Patterns category count and the library's list, which are the lines the other
tracks also edit (see Merge order).

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorNodesTests/Support/VariationFixtures.swift`:

```swift
// Test fixture file: sources of trees and readers of culled ones, shared by the variation nodes' tests.
import CreatorGraph
import CreatorNodes
import Testing

/// A node and the output socket that carries a list or tree.
struct TreeSource {
    let node: Node
    let socket: SocketName
}

extension Harness {
    /// A Series 0, 1, 2 … of `count` numbers, partitioned into rows of `rows` when that is given: a flat list or a tree.
    mutating func source(count: Int, rows: Int? = nil) -> TreeSource {
        let series = add(SeriesNode.self, ["count": .integer(count)])
        guard let rows else { return TreeSource(node: series, socket: "values") }
        let partition = add(PartitionNode.self, ["size": .integer(rows)])
        wire(series, "values", to: partition, "tree")
        return TreeSource(node: partition, socket: "tree")
    }

    mutating func wire(_ source: TreeSource, to node: Node, _ input: SocketName) {
        wire(source.node, source.socket, to: node, input)
    }
}

extension EvaluationReport {
    /// The tree (or list) on an output, with its culling.
    func tree(_ node: Node, _ socket: SocketName = "tree") -> DataTree? { value(node, socket)?.asTree }

    /// Each branch's item indices, in branch order: `[[0, 2], [0, 3]]`.
    func positions(_ node: Node, _ socket: SocketName = "tree") -> [[Int]]? { tree(node, socket)?.leaves.map(\.positions) }
}
```


Create `Tests/CreatorNodesTests/Variation/CullPatternNodeTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Cull Pattern (patterns spec §4): a true/false mask repeated across each branch, and a cull keeps paths.
struct CullPatternNodeTests {
    func run(_ pattern: String, count: Int = 6, rows: Int? = nil) async throws -> (report: EvaluationReport, cull: Node) {
        var h = Harness()
        let source = h.source(count: count, rows: rows)
        let cull = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text(pattern)])
        h.wire(source, to: cull, "tree")
        return (try await h.run([cull]), cull)
    }

    @Test func everyOtherItemOfAFlatListSurvivesAtItsOwnIndex() async throws {
        let (report, cull) = try await run("1 0")
        #expect(report.value(cull, "tree")?.outline == "[0,2,4]")
        #expect(report.positions(cull) == [[0, 2, 4]])
        #expect(report.tree(cull)?.isCulled == true)
    }

    @Test func theMaskStartsAgainAtEveryBranch() async throws {
        let (report, cull) = try await run("1 1 0", count: 8, rows: 4)
        #expect(report.value(cull, "tree")?.outline == "[[0,1,3],[4,5,7]]")
        #expect(report.positions(cull) == [[0, 1, 3], [0, 1, 3]])
    }

    @Test func aMaskLongerThanTheBranchJustStopsEarly() async throws {
        let (report, cull) = try await run("0 1 1 1 1 1", count: 6, rows: 2)
        #expect(report.positions(cull) == [[1], [1], [1]])
    }

    @Test func aSecondCullCountsTheSurvivorsAndKeepsTheFirstOnesIndices() async throws {
        var h = Harness()
        let source = h.source(count: 6)
        let first = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])
        let second = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])
        h.wire(source, to: first, "tree")
        h.wire(first, "tree", to: second, "tree")
        let report = try await h.run([second])
        #expect(report.value(second, "tree")?.outline == "[0,4]")
        #expect(report.positions(second) == [[0, 4]], "{0} and {4}: the survivors of {0, 2, 4}, not renumbered")
    }

    @Test func aReshapingNodeAfterACullRenumbersAsReshapingDoes() async throws {
        var h = Harness()
        let source = h.source(count: 6)
        let cull = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])
        let rows = h.add(PartitionNode.self, ["size": .integer(2)])
        h.wire(source, to: cull, "tree")
        h.wire(cull, "tree", to: rows, "tree")
        let report = try await h.run([rows])
        #expect(report.value(rows, "tree")?.outline == "[[0,2],[4]]")
        #expect(report.positions(rows) == [[0, 1], [0]], "Partition makes new branches, so the items are counted afresh")
    }

    @Test func aMaskThatKeepsEverythingChangesNothingAndSaysNothing() async throws {
        let (report, cull) = try await run("1")
        #expect(report.isOK(cull))
        #expect(report.value(cull, "tree")?.isList == true, "a plain list stays a plain list")
    }

    @Test func aMaskThatCullsEverythingLeavesEmptyBranches() async throws {
        let (report, cull) = try await run("0", count: 4, rows: 2)
        #expect(report.value(cull, "tree")?.outline == "[[],[]]")
        #expect(report.positions(cull) == [[], []])
    }

    @Test func tAndFAndCommasAreAccepted() async throws {
        let (report, cull) = try await run("T,f,t", count: 6)
        #expect(report.positions(cull) == [[0, 2, 3, 5]])
    }

    @Test func aBadPatternNamesItself() async throws {
        let (report, cull) = try await run("1 2 0")
        #expect(report.error(cull) == "“1 2 0” isn't a pattern. Use 1 to keep an item and 0 to cull it, like 1 0 1.")
        let (blank, blankCull) = try await run("  ")
        #expect(blank.error(blankCull) == "The pattern is empty. Write 1 to keep an item and 0 to cull it, like 1 0 1.")
    }

    /// Runs the node by hand, with `inputs` as the evaluator would hand them over.
    func evaluate(_ inputs: NodeInputs) async throws -> NodeOutputs {
        let node = BuiltInNodes.registry.makeNode(CullPatternNode.typeID)
        return try await CullPatternNode.evaluate(inputs, kernel: FakeKernel(), context: EvalContext(node: node, item: 0, parameters: [:]))
    }

    @Test func aWiredListOfBooleansTakesThePlaceOfTheText() async throws {
        let tree = DataTree.list((0..<4).map { .integer($0) })
        let outputs = try await evaluate(NodeInputs(item: 0, slots: ["tree": .tree(tree), "keep": .list([.bool(false), .bool(true)])]))
        #expect(try #require(outputs.trees["tree"]).itemPositions == [1, 3])
    }

    @Test func anEmptyWiredListIsRefused() async throws {
        let inputs = NodeInputs(item: 0, slots: ["tree": .tree(.list([.integer(1)])), "keep": .list([])])
        await #expect(throws: NodeError.self) { _ = try await evaluate(inputs) }
    }

    @Test func itCullsAnyKindOfItem() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self, ["countX": .integer(3), "countY": .integer(1)])
        let cull = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("0 1 1")])
        h.wire(grid, "points", to: cull, "tree")
        let report = try await h.run([cull])
        #expect(report.value(cull, "tree")?.vectors?.count == 2)
        #expect(report.positions(cull) == [[1, 2]])
    }

    @Test func theNodeStartsWithAPatternThatKeepsEveryOtherItem() {
        let node = BuiltInNodes.registry.makeNode(CullPatternNode.typeID)
        #expect(node.inputValues[NodeSetting.cullPattern] == .text("1 0"))
        #expect(CullPatternNode.category == .patterns)
    }
}
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
        #expect(BuiltInNodes.all.count == 41)
```

with:

```swift
        #expect(BuiltInNodes.all.count == 42)
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
.feature: 2, .patterns: 6, .lists: 7
```

with:

```swift
.feature: 2, .patterns: 7, .lists: 7
```


In `Tests/CreatorEditorTests/PatternsLibraryTests.swift`, replace:

```swift
        #expect(names == ["Place", "Points to Placements", "Hole Pattern", "Boss / Pin Pattern", "Slot Pattern", "Pattern Feature"])
```

with:

```swift
        #expect(names == [
            "Place", "Points to Placements", "Hole Pattern", "Boss / Pin Pattern", "Slot Pattern", "Pattern Feature",
            "Cull Pattern",
        ])
```


- [ ] **Step 2: Run them**

Run: `swift test --filter "CullPatternNodeTests|OutputNodeTests|PatternsLibraryTests|CatalogTests|BuiltInNodesInspectorTests" 2>&1 | grep -v 'ld: warning'`

Expected: FAIL, the tests do not build (`cannot find 'CullPatternNode' in scope`).

- [ ] **Step 3: Write the implementation**

Create `Sources/CreatorNodes/Patterns/Variation/CullMask.swift`:

```swift
import CreatorGraph

/// A Cull Pattern's mask written as text: `1 0 1`, `T F T` or `1,0,1` (1 or T keeps an item, 0 or F culls it).
enum CullMask {
    /// What the node's `cullPattern` setting says; refuses text with anything else in it, or nothing at all.
    static func parse(_ text: String) throws -> [Bool] {
        var mask: [Bool] = []
        for character in text where !character.isWhitespace && character != "," {
            switch character {
            case "1", "t", "T": mask.append(true)
            case "0", "f", "F": mask.append(false)
            default: throw NodeError.invalidValue("“\(text)” isn't a pattern. Use 1 to keep an item and 0 to cull it, like 1 0 1.")
            }
        }
        guard !mask.isEmpty else {
            throw NodeError.invalidValue("The pattern is empty. Write 1 to keep an item and 0 to cull it, like 1 0 1.")
        }
        return mask
    }
}
```


Create `Sources/CreatorNodes/Patterns/Variation/CullPatternNode.swift`:

```swift
import CreatorGraph
import CreatorKernel

/// Keeps or culls the items of every branch by a repeating mask (patterns spec §4): `1 0` keeps every other item, `1 1 0`
/// culls every third. The mask starts again at the first item of each branch and counts the items the branch has now, so a
/// second Cull Pattern after a first works on what is left. Culling keeps paths: a survivor keeps the index it had, so
/// `{3}` is still `{3}` when `{1}` is gone and a pick on it follows it (§6). The mask is a saved text setting, or a list of
/// true and false wired into `keep`, which takes its place.
public enum CullPatternNode: NodeDefinition {
    public static let typeID = "creator.cullPattern"
    public static let displayName = "Cull Pattern"
    public static let category = NodeCategory.patterns
    public static let inputs = [
        SocketSpec("tree", .any, access: .tree),
        SocketSpec("keep", .bool, access: .list, optional: true),
    ]
    public static let outputs = [SocketSpec("tree", .any)]
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.cullPattern: .text("1 0")]
    public static let inspector = [InspectorSection(title: "Pattern", controls: [.text(NodeSetting.cullPattern)])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("tree")
        let mask: [Bool]
        if inputs.has("keep") {
            mask = try inputs.bools("keep")
            guard !mask.isEmpty else { throw NodeError.invalidValue("“keep” is an empty list. Give it at least one true or false.") }
        } else {
            guard case .text(let text)? = context.node.inputValues[NodeSetting.cullPattern] else {
                throw NodeError.invalidValue("The pattern is empty. Write 1 to keep an item and 0 to cull it, like 1 0 1.")
            }
            mask = try CullMask.parse(text)
        }
        return NodeOutputs(trees: ["tree": tree.keepingItems { _, _, k in mask[k % mask.count] }])
    }
}
```


In `Sources/CreatorGraph/NodeSetting.swift`, replace:

```swift
    public static let all: Set<SocketName> = [
        parameter, picks, showHandle, sketch, face, group, pathRule, branchPath, itemPath
    ]
```

with:

```swift
    /// Cull Pattern: its mask, as `.text("1 0 1")` (1 keeps an item, 0 culls it, repeated along each branch).
    public static let cullPattern: SocketName = "cullPattern"

    public static let all: Set<SocketName> = [
        parameter, picks, showHandle, sketch, face, group, pathRule, branchPath, itemPath, cullPattern
    ]
```


In `Sources/CreatorNodes/BuiltInNodes.swift`, replace:

```swift
        OutputNode.self,
    ]
```

with:

```swift
        CullPatternNode.self,
        OutputNode.self,
    ]
```


- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter "CullPatternNodeTests|OutputNodeTests|PatternsLibraryTests|CatalogTests|BuiltInNodesInspectorTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

- [ ] **Step 5: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > /tmp/vtest.log 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,712 = master + 73** (+13 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(7a-3b): Cull Pattern, a repeating keep/cull mask that keeps paths"
```

---

### Task 5: Cull Index, and the naming test (spec §9)

**Files:**

- Create: `Sources/CreatorNodes/Patterns/Variation/CullIndexNode.swift`
- Create: `Sources/CreatorNodes/Patterns/Variation/CullTargets.swift`
- Modify: `Sources/CreatorGraph/NodeSetting.swift`
- Modify: `Sources/CreatorNodes/BuiltInNodes.swift`
- Test: `Tests/CreatorNodesTests/Variation/CullIndexNodeTests.swift` (new)
- Test: `Tests/CreatorNodesTests/Variation/CulledPickTests.swift` (new)
- Test: `Tests/CreatorEditorTests/PatternsLibraryTests.swift` (modify)
- Test: `Tests/CreatorNodesTests/OutputNodeTests.swift` (modify)

**Interfaces:**

- Consumes: Tasks 2–4; `EdgesByTagNode`, `FilletNode`, `HolePatternNode`, `PatternPlate`, `OCCTKernel` (tests).
- Produces: `CullIndexNode` (`creator.cullIndex`, inputs `tree` (any, tree), `indices` (number list, optional), output `tree`; setting `NodeSetting.cullIndices`, default `""`);
`CullTargets` (parses `1, 4, {0;3}`, `drops(_:at:depth:)`, `unmatched(in:)`).

Indices and paths such as `{0;3}` come out of a list or tree; everything else keeps its path. The same task adds the spec §9 naming test,
`CulledPickTests`, on a single flat list (Grid Points and Points to Placements, with the Cull Index either after Points to Placements or before it on the Grid Points, then a Hole Pattern and a fillet on a picked rim): a pick on one
instance survives a cull of another and does not move to a neighbour; a pick on a culled instance warns "Instance {1} no longer exists…" naming
its path and selects nothing; undoing the cull brings the pick back. **After 7a-layouts merges (picks by tree path) this file must pass unchanged**:
a flat list's items are still `{i}`. If culling changed a survivor's flat index, `aPickOnOneInstanceSurvivesACullOfAnother` and
`aCullLeavesTheSurvivorsAtTheirIndices` fail, which is the bug to avoid.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorNodesTests/Variation/CullIndexNodeTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Cull Index (patterns spec §4): listed indices or paths such as {0;3} come out, and everything else keeps its path.
struct CullIndexNodeTests {
    func run(_ text: String, count: Int = 8, rows: Int? = nil) async throws -> (report: EvaluationReport, cull: Node) {
        var h = Harness()
        let source = h.source(count: count, rows: rows)
        let cull = h.add(CullIndexNode.self, [NodeSetting.cullIndices: .text(text)])
        h.wire(source, to: cull, "tree")
        return (try await h.run([cull]), cull)
    }

    @Test func anIndexComesOutOfEveryBranch() async throws {
        let (report, cull) = try await run("1", count: 8, rows: 4)
        #expect(report.value(cull, "tree")?.outline == "[[0,2,3],[4,6,7]]")
        #expect(report.positions(cull) == [[0, 2, 3], [0, 2, 3]])
        #expect(report.isOK(cull))
    }

    @Test func severalIndicesInAnyOrderWithSpaces() async throws {
        let (report, cull) = try await run(" 3 ,0, 5", count: 6)
        #expect(report.value(cull, "tree")?.outline == "[1,2,4]")
        #expect(report.positions(cull) == [[1, 2, 4]])
    }

    @Test func aPathDropsOneItem() async throws {
        let (report, cull) = try await run("{1;2}", count: 8, rows: 4)
        #expect(report.value(cull, "tree")?.outline == "[[0,1,2,3],[4,5,7]]")
        #expect(report.positions(cull) == [[0, 1, 2, 3], [0, 1, 3]])
    }

    @Test func aShortPathDropsTheWholeBranchAndLeavesItsPlaceEmpty() async throws {
        let (report, cull) = try await run("{0}", count: 6, rows: 2)
        #expect(report.value(cull, "tree")?.outline == "[[],[2,3],[4,5]]")
        #expect(report.positions(cull) == [[], [0, 1], [0, 1]])
        #expect(report.tree(cull)?.branches.count == 3, "{1} and {2} are still {1} and {2}")
    }

    @Test func aPathOnAFlatListIsAnIndex() async throws {
        let (report, cull) = try await run("{2}", count: 4)
        #expect(report.positions(cull) == [[0, 1, 3]])
    }

    @Test func indicesAndPathsTogether() async throws {
        let (report, cull) = try await run("0, {1;3}", count: 8, rows: 4)
        #expect(report.positions(cull) == [[1, 2, 3], [1, 2]])
    }

    @Test func aPathWithTooManyIndicesIsRefusedNamingTheShape() async throws {
        let (report, cull) = try await run("{0;1;2}", count: 8, rows: 4)
        #expect(report.error(cull) == "{0;1;2} has 3 indices, but an item of this tree (2 × 4) needs 2. Write it like {0;0}.")
    }

    @Test func aPathThatNamesNothingWarnsOnceAndTheOthersStillApply() async throws {
        let (report, cull) = try await run("{0;1}, {0;9}, {5;0}", count: 8, rows: 4)
        #expect(report.warning(cull) == "{0;9} and {5;0} name nothing in this tree.")
        #expect(report.positions(cull) == [[0, 2, 3], [0, 1, 2, 3]])
        let (single, singleCull) = try await run("{0;9}", count: 8, rows: 4)
        #expect(single.warning(singleCull) == "{0;9} names nothing in this tree.")
    }

    @Test func anIndexPastTheEndIsNotAProblem() async throws {
        let (report, cull) = try await run("99", count: 3)
        #expect(report.isOK(cull))
        #expect(report.value(cull, "tree")?.outline == "[0,1,2]")
    }

    @Test func nothingToCullChangesNothingAndAPlainListStaysPlain() async throws {
        let (report, cull) = try await run("", count: 3)
        #expect(report.isOK(cull))
        #expect(report.value(cull, "tree")?.isList == true)
    }

    @Test func indicesNameThePlacesTheItemsHadBeforeAnyCull() async throws {
        var h = Harness()
        let source = h.source(count: 6)
        let pattern = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])  // keeps {0}, {2}, {4}
        let index = h.add(CullIndexNode.self, [NodeSetting.cullIndices: .text("2, 1")])
        h.wire(source, to: pattern, "tree")
        h.wire(pattern, "tree", to: index, "tree")
        let report = try await h.run([index])
        #expect(report.positions(index) == [[0, 4]], "{2} is gone, and {1} was gone already")
        #expect(report.value(index, "tree")?.outline == "[0,4]")
        #expect(report.isOK(index), "an index never warns")
    }

    @Test func aPathOnAnItemAlreadyCulledWarns() async throws {
        var h = Harness()
        let source = h.source(count: 6)
        let pattern = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])
        let index = h.add(CullIndexNode.self, [NodeSetting.cullIndices: .text("{1}")])
        h.wire(source, to: pattern, "tree")
        h.wire(pattern, "tree", to: index, "tree")
        let report = try await h.run([index])
        #expect(report.warning(index) == "{1} names nothing in this tree.")
    }

    @Test func wiredNumbersAreIndices() async throws {
        var h = Harness()
        let source = h.source(count: 6)
        let which = h.add(SeriesNode.self, ["start": .number(1), "step": .number(2), "count": .integer(2)])  // 1, 3
        let cull = h.add(CullIndexNode.self)
        h.wire(source, to: cull, "tree")
        h.wire(which, "values", to: cull, "indices")
        let report = try await h.run([cull])
        #expect(report.positions(cull) == [[0, 2, 4, 5]])
    }

    @Test func wiredNumbersMustBeWholeAndNotNegative() async throws {
        for bad in [1.5, -1.0] {
            var h = Harness()
            let source = h.source(count: 4)
            let which = h.add(SeriesNode.self, ["start": .number(bad), "count": .integer(1)])
            let cull = h.add(CullIndexNode.self)
            h.wire(source, to: cull, "tree")
            h.wire(which, "values", to: cull, "indices")
            let report = try await h.run([cull])
            #expect(report.error(cull)?.hasPrefix("“indices” must be whole numbers from 0 up") == true, "\(bad)")
        }
    }

    @Test func anEmptyPathIsRefusedBecauseItWouldCullTheWholeTree() async throws {
        for text in ["{}", "1, { }"] {
            let (report, cull) = try await run(text, count: 4)
            #expect(report.error(cull) == "“{}” names the whole tree. To cull everything, use Cull Pattern with 0.", "\(text)")
        }
    }

    @Test func textThatIsNotAnIndexOrAPathNamesItself() async throws {
        let (report, cull) = try await run("1, x, 3")
        #expect(report.error(cull) == "“x” isn't an index or a path. Write indices like 3 and paths like {0;3}, separated by commas.")
        let (negative, negativeCull) = try await run("-2")
        #expect(negative.error(negativeCull)?.hasPrefix("“-2” isn't an index or a path.") == true)
        let (open, openCull) = try await run("{0;3")
        #expect(open.error(openCull)?.hasPrefix("“{0;3” isn't an index or a path.") == true)
    }

    @Test func itCullsAnyKindOfItem() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self, ["countX": .integer(3), "countY": .integer(1)])
        let cull = h.add(CullIndexNode.self, [NodeSetting.cullIndices: .text("0")])
        h.wire(grid, "points", to: cull, "tree")
        let report = try await h.run([cull])
        #expect(report.value(cull, "tree")?.vectors?.count == 2)
        #expect(report.positions(cull) == [[1, 2]])
    }

    @Test func theNodeStartsWithNothingToCull() {
        let node = BuiltInNodes.registry.makeNode(CullIndexNode.typeID)
        #expect(node.inputValues[NodeSetting.cullIndices] == .text(""))
    }
}
```


Create `Tests/CreatorNodesTests/Variation/CulledPickTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import Testing

/// Patterns spec §6 and §9 for culling: a pick on an instance survives a cull of another instance, and a pick on a culled
/// instance warns, naming its path, and selects nothing. The placements are one flat list (Grid Points → Points to
/// Placements → Cull Index), so an instance's path is `{i}`, its index in the list. These tests hold for the tree-path
/// picks of sub-project 7a-layouts as well, where a flat list's items are still `{i}`, and must pass unchanged there.
struct CulledPickTests {
    /// Which side of Points to Placements the cull is on. Both must number the survivors alike: a cull of the Grid Points
    /// is as natural as one of the placements.
    enum Stage: CaseIterable, Sendable {
        case afterPlacements, beforePlacements
    }

    /// 3 × 2 Ø5 holes 15 mm apart, a Cull Index on the points or the placements, an Edges by Tag on the result and a
    /// Fillet on its edges.
    struct Fixture {
        var plate: PatternPlate
        let cull: Node, holes: Node, rule: Node, fillet: Node

        init(_ stage: Stage = .afterPlacements) {
            plate = PatternPlate(columns: 3, rows: 2, spacingX: 15, spacingY: 15)
            cull = plate.h.add(CullIndexNode.self)
            holes = plate.h.add(HolePatternNode.self, ["diameter": .number(5), "depth": .number(6)])
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            switch stage {
            case .afterPlacements:
                plate.h.wire(plate.placements, "placements", to: cull, "tree")
                plate.h.wire(cull, "tree", to: holes, "placements")
            case .beforePlacements:
                // The plate's own Points to Placements is left unused: this one reads the culled points.
                let placed = plate.h.add(PointsToPlacementsNode.self)
                plate.h.wire(plate.grid, "points", to: cull, "tree")
                plate.h.wire(cull, "tree", to: placed, "points")
                plate.h.wire(placed, "placements", to: holes, "placements")
            }
            rule = plate.h.add(EdgesByTagNode.self)
            plate.h.wire(holes, "solid", to: rule, "solid")
            fillet = plate.h.add(FilletNode.self, ["radius": .number(0.5)])
            plate.h.wire(rule, "edges", to: fillet, "edges")
        }

        /// Culls what `text` names (`CullIndexNode`'s setting).
        mutating func cull(_ text: String) {
            plate.h.set(cull, NodeSetting.cullIndices, .text(text))
        }

        /// The tag of hole `index`'s bore, the way Hole Pattern names it.
        func bore(_ index: Int) -> TopoTag {
            TopoTag(node: NodeID.instanceScoped([holes.id, holes.id]), item: index, role: .side(segment: 1))
        }

        /// The rim of hole `index` on the plate's top: the circle between its bore and the plate's end cap.
        func rim(of index: Int, in solid: Solid) -> EdgeInfo? {
            let top = TopoTag(node: plate.plate.id, item: 0, role: .endCap)
            return solid.topology.edges.first { edge in
                guard edge.kind == .circle, !edge.isSeam, edge.faces.count == 2 else { return false }
                let sides = edge.faces.compactMap { solid.topology.face($0) }
                return sides.contains { $0.tags.contains(bore(index)) } && sides.contains { $0.tags.contains(top) }
            }
        }

        /// Picks the rims of the holes `indices` on the rule, from a run with nothing culled.
        mutating func pick(_ indices: [Int], kernel: any Kernel) async throws {
            cull("")
            let solid = try onlySolid(try await plate.h.run([holes], kernel: kernel), holes)
            let edges = try indices.map { try #require(rim(of: $0, in: solid)).id }
            plate.h.set(rule, NodeSetting.picks, .edgePicks(solid.topology.picks(for: edges)))
        }

        /// The edges the rule selects now.
        func selected(_ report: EvaluationReport) throws -> (solid: Solid, edges: [EdgeInfo]) {
            let set = try #require(report.value(rule, "edges")?.edgeSets?.first)
            return (set.solid, set.edges.compactMap { set.solid.topology.edge($0) })
        }

        func center(of edge: EdgeInfo) throws -> Vector3 {
            guard case .circle(let center, _, _, _, _)? = edge.curve else { throw NodeError.invalidValue("not a circle") }
            return center
        }
    }

    func touchesHole(_ index: Int, _ edge: EdgeInfo, in solid: Solid, _ f: Fixture) -> Bool {
        edge.faces.compactMap { solid.topology.face($0) }.contains { $0.tags.contains(f.bore(index)) }
    }

    @Test(arguments: ["1", "0", "2, 3", "{3}", "5"], Stage.allCases)
    func aPickOnOneInstanceSurvivesACullOfAnother(_ cull: String, _ stage: Stage) async throws {
        let kernel = OCCTKernel()
        var f = Fixture(stage)
        try await f.pick([4], kernel: kernel)
        let before = try f.selected(try await f.plate.h.run([f.rule], kernel: kernel))
        f.cull(cull)
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(report.isOK(f.rule) && report.isOK(f.fillet), "after culling \(cull) \(stage): \(String(describing: report.state(f.rule)))")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { touchesHole(4, $0, in: solid, f) }, "still the rim of {4}")
        #expect(isClose(try f.center(of: try #require(edges.first)), try f.center(of: try #require(before.edges.first))),
                "the same physical hole: a cull never moves a pick to a neighbour")
    }

    @Test(arguments: Stage.allCases)
    func aCullLeavesTheSurvivorsAtTheirIndices(_ stage: Stage) async throws {
        let kernel = OCCTKernel()
        var f = Fixture(stage)
        f.cull("1, 2")
        let report = try await f.plate.h.run([f.holes], kernel: kernel)
        let solid = try onlySolid(report, f.holes)
        let items = Set(solid.topology.faces.flatMap(\.tags).filter(\.node.isInstanceQualified).map(\.item))
        #expect(items == [0, 3, 4, 5], "the holes are {0}, {3}, {4} and {5}, not {0} to {3}: \(stage)")
        #expect(report.isOK(f.holes), "a cull never warns")
    }

    @Test(arguments: Stage.allCases)
    func aPickOnACulledInstanceWarnsNamingItAndSelectsNothing(_ stage: Stage) async throws {
        let kernel = OCCTKernel()
        var f = Fixture(stage)
        try await f.pick([1], kernel: kernel)
        f.cull("1")
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instance {1} no longer exists, so the edge picked on it isn't selected.")
        #expect(try f.selected(report).edges.isEmpty, "never a neighbour's rim")
    }

    @Test func onlyTheCulledPicksAreDroppedWhenAnotherStillHolds() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([1, 4], kernel: kernel)
        f.cull("1")
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instance {1} no longer exists, so the edge picked on it isn't selected.")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { touchesHole(4, $0, in: solid, f) })
    }

    @Test func aPickComesBackWhenTheCullIsUndone() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([1], kernel: kernel)
        f.cull("1")
        _ = try await f.plate.h.run([f.rule], kernel: kernel)
        f.cull("")
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.isOK(f.rule))
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { touchesHole(1, $0, in: solid, f) })
    }

    @Test func aPickSurvivesACullAndACountChangeTogether() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([4], kernel: kernel)
        f.cull("0")
        f.plate.h.set(f.plate.grid, "spacingX", .number(18))
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(report.isOK(f.rule) && report.isOK(f.fillet))
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { touchesHole(4, $0, in: solid, f) })
    }
}
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
        #expect(BuiltInNodes.all.count == 42)
```

with:

```swift
        #expect(BuiltInNodes.all.count == 43)
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
.feature: 2, .patterns: 7, .lists: 7
```

with:

```swift
.feature: 2, .patterns: 8, .lists: 7
```


In `Tests/CreatorEditorTests/PatternsLibraryTests.swift`, replace:

```swift
            "Cull Pattern",
        ])
```

with:

```swift
            "Cull Pattern", "Cull Index",
        ])
```


- [ ] **Step 2: Run them**

Run: `swift test --filter "CullIndexNodeTests|CulledPickTests|OutputNodeTests|PatternsLibraryTests|CatalogTests|BuiltInNodesInspectorTests" 2>&1 | grep -v 'ld: warning'`

Expected: FAIL, the tests do not build (`cannot find 'CullIndexNode' in scope`).

- [ ] **Step 3: Write the implementation**

Create `Sources/CreatorNodes/Patterns/Variation/CullIndexNode.swift`:

```swift
import CreatorGraph
import CreatorKernel
import Foundation

/// Takes listed items out of a list or tree (patterns spec §4). An index such as `3` drops that place from every branch; a
/// path such as `{0;3}` drops one item, and a shorter one such as `{1}` drops everything under it. They go in the saved text
/// setting, `1, 4, {0;3}`, or as numbers wired into `indices` (a Series, Random Values' integers). Culling keeps paths: the
/// rest keep the indices they had, so `{4}` is still `{4}` when `{1}` is gone and a pick on it follows it (§6); a pick on the
/// culled item warns, naming its path. A path that names nothing in the tree is said once and the others still apply.
public enum CullIndexNode: NodeDefinition {
    public static let typeID = "creator.cullIndex"
    public static let displayName = "Cull Index"
    public static let category = NodeCategory.patterns
    public static let inputs = [
        SocketSpec("tree", .any, access: .tree),
        SocketSpec("indices", .number, access: .list, optional: true),
    ]
    public static let outputs = [SocketSpec("tree", .any)]
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.cullIndices: .text("")]
    public static let inspector = [InspectorSection(title: "Cull", controls: [.text(NodeSetting.cullIndices)])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("tree")
        var targets = try CullTargets(parsing: setting(of: context.node))
        if inputs.has("indices") { try targets.add(wired: try inputs.numbers("indices")) }
        try targets.validate(against: tree)
        let depth = tree.depth
        let culled = tree.keepingItems { leaf, _, k in !targets.drops(leaf, at: k, depth: depth) }
        return NodeOutputs(trees: ["tree": culled], warnings: warning(for: targets.unmatched(in: tree)).map { [$0] } ?? [])
    }

    /// The text setting; none stored is the same as empty.
    private static func setting(of node: Node) -> String {
        if case .text(let text)? = node.inputValues[NodeSetting.cullIndices] { text } else { "" }
    }

    /// "{0;9} names nothing in this tree." for the paths nothing is at, or `nil`.
    private static func warning(for unmatched: [TreePath]) -> String? {
        guard !unmatched.isEmpty else { return nil }
        let names = unmatched.map(\.description).formatted(.list(type: .and).locale(.messages))
        return "\(names) \(unmatched.count == 1 ? "names" : "name") nothing in this tree."
    }
}
```


Create `Sources/CreatorNodes/Patterns/Variation/CullTargets.swift`:

```swift
import CreatorGraph

/// What a Cull Index takes out (patterns spec §4): item indices, which name that place in every branch (`3` is `{0;3}`,
/// `{1;3}`, … ), and paths, which name one item (`{0;3}`) or, when they stop short of the items, everything under them (`{1}`
/// is the whole second row). An index or path names the place an item had before any cull, so culling twice never shifts it.
struct CullTargets {
    private(set) var indices: Set<Int> = []
    private(set) var paths: [TreePath] = []

    /// Reads the node's text setting: indices and paths separated by commas, `1, 4, {0;3}`. Nothing at all is allowed.
    init(parsing text: String) throws {
        var tokens: [String] = []
        var current = ""
        var inBraces = false
        for character in text {
            if character == "{" { inBraces = true }
            if character == "}" { inBraces = false }
            if character == ",", !inBraces {
                tokens.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        tokens.append(current)
        for token in tokens.map({ $0.trimmingCharacters(in: .whitespaces) }) where !token.isEmpty {
            if token.hasPrefix("{"), let path = TreePath(parsing: token) {
                // `{}` has no indices, so every item would start with it and a stray one would empty the tree without a word.
                guard path.count > 0 else {
                    throw NodeError.invalidValue("“{}” names the whole tree. To cull everything, use Cull Pattern with 0.")
                }
                paths.append(path)
            } else if let index = Int(token), index >= 0 {
                indices.insert(index)
            } else {
                throw NodeError.invalidValue("“\(token)” isn't an index or a path. Write indices like 3 and paths like {0;3}, "
                    + "separated by commas.")
            }
        }
    }

    /// Adds the indices wired into `indices`: whole numbers from 0 up.
    mutating func add(wired values: [Double]) throws {
        for value in values {
            guard value.isFinite, value >= 0, value == value.rounded(), value < Double(Int.max) else {
                let shown = value.formatted(.number.locale(.messages))
                throw NodeError.invalidValue("“indices” must be whole numbers from 0 up, not \(shown).")
            }
            indices.insert(Int(value))
        }
    }

    /// Refuses a path with more indices than an item of `tree` has, naming the shape.
    func validate(against tree: DataTree) throws {
        for path in paths where path.count > tree.depth {
            let example = TreePath(Array(repeating: 0, count: tree.depth))
            throw NodeError.invalidValue("\(path) has \(path.count.display) indices, but an item of this tree (\(tree.shapeText)) "
                + "needs \(tree.depth.display). Write it like \(example).")
        }
    }

    /// Whether item `k` of `leaf` is taken out. `depth` is the tree's.
    func drops(_ leaf: DataTree.Leaf, at k: Int, depth: Int) -> Bool {
        let position = leaf.positions[k]
        if indices.contains(position) { return true }
        return paths.contains { path in
            path.count == depth
                ? path.indices.dropLast() == leaf.path.indices && path.indices.last == position
                : leaf.path.indices.starts(with: path.indices)
        }
    }

    /// The paths that name nothing in `tree`: a branch that isn't there or an item that was never there (or is gone).
    func unmatched(in tree: DataTree) -> [TreePath] {
        paths.filter { path in
            if path.count < tree.depth { return tree.branch(at: path) == nil }
            guard let last = path.indices.last, let leaf = tree.branch(at: TreePath(Array(path.indices.dropLast()))) else { return true }
            return !leaf.itemPositions.contains(last)
        }
    }
}
```


In `Sources/CreatorGraph/NodeSetting.swift`, replace:

```swift
    public static let all: Set<SocketName> = [
        parameter, picks, showHandle, sketch, face, group, pathRule, branchPath, itemPath, cullPattern
    ]
```

with:

```swift
    /// Cull Index: the indices and paths to take out, as `.text("1, 4, {0;3}")`; empty takes nothing out.
    public static let cullIndices: SocketName = "cullIndices"

    public static let all: Set<SocketName> = [
        parameter, picks, showHandle, sketch, face, group, pathRule, branchPath, itemPath, cullPattern, cullIndices
    ]
```


In `Sources/CreatorNodes/BuiltInNodes.swift`, replace:

```swift
        OutputNode.self,
    ]
```

with:

```swift
        CullIndexNode.self,
        OutputNode.self,
    ]
```


- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter "CullIndexNodeTests|CulledPickTests|OutputNodeTests|PatternsLibraryTests|CatalogTests|BuiltInNodesInspectorTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

- [ ] **Step 5: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > /tmp/vtest.log 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,736 = master + 97** (+24 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(7a-3b): Cull Index, and picks that survive a cull of another instance"
```

---

### Task 6: Cull by Region

**Files:**

- Create: `Sources/CreatorGeometry/Profile2D+Contains.swift`
- Create: `Sources/CreatorNodes/Patterns/Variation/CullByRegionNode.swift`
- Create: `Sources/CreatorNodes/Patterns/Variation/RegionDistance.swift`
- Modify: `Sources/CreatorNodes/BuiltInNodes.swift`
- Test: `Tests/CreatorGeometryTests/ProfileContainsTests.swift` (new)
- Test: `Tests/CreatorNodesTests/Variation/CullByRegionNodeTests.swift` (new)
- Test: `Tests/CreatorEditorTests/PatternsLibraryTests.swift` (modify)
- Test: `Tests/CreatorNodesTests/OutputNodeTests.swift` (modify)

**Interfaces:**

- Consumes: Task 2 builders; `NodeInputs.choice(_:options:)`, `.profile/.vector/.edgeSet/.scalar`; `EdgeInfo.curve`, `FaceInfo.normal/centroid/kind`.
- Produces: `Profile2D.contains(_ point: Vector2, tolerance: Double = 1e-6) -> Bool` (public, even-odd over every loop, the outline counts);
`RegionDistance.nearestEdge(_:) throws -> @Sendable (Vector3) -> Double`, `nearestFace(_:)`, `distance(from:to:)`;
`CullByRegionNode` (`creator.cullByRegion`; inputs `placements` (plane, tree), `reference`, `keep`, `profile`, `point`, `edges`, `faces`, `distance`; output `placements`).

Placements kept inside or outside a profile, or within or beyond a distance of a point, an edge set or a face (Key decision 9; User decisions U3 and
U4). A new `Profile2D.contains` (CreatorGeometry) does the point-in-region test; `RegionDistance` measures straight and circular edges exactly and
flat faces by their plane. The node takes `placements` whole, so a tree keeps its branches and every survivor its path.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorGeometryTests/ProfileContainsTests.swift`:

```swift
import Foundation
import Testing
@testable import CreatorGeometry

/// Whether a point lies on a profile's region, for Cull by Region's profile mode.
struct ProfileContainsTests {
    let rectangle = Profile2D.rectangle(width: 20, height: 10, plane: .xy)

    @Test func aPointInsideARectangleIsIn() {
        #expect(rectangle.contains(Vector2(0, 0)))
        #expect(rectangle.contains(Vector2(9.9, 4.9)))
    }

    @Test func aPointOutsideARectangleIsOut() {
        #expect(!rectangle.contains(Vector2(10.1, 0)))
        #expect(!rectangle.contains(Vector2(0, -5.1)))
        #expect(!rectangle.contains(Vector2(-30, 40)))
    }

    @Test func aPointOnTheOutlineCountsAsInside() {
        #expect(rectangle.contains(Vector2(10, 0)))
        #expect(rectangle.contains(Vector2(-10, -5)), "a corner")
        #expect(rectangle.contains(Vector2(10 + 1e-7, 0)), "within the tolerance")
        #expect(!rectangle.contains(Vector2(10 + 1e-3, 0)))
    }

    @Test func aCircleIsFoundThroughItsArc() {
        let circle = Profile2D.circle(radius: 10, center: Vector2(5, 0), plane: .xy)
        #expect(circle.contains(Vector2(5, 0)))
        #expect(circle.contains(Vector2(14.9, 0)))
        #expect(!circle.contains(Vector2(15.1, 0)))
        #expect(!circle.contains(Vector2(5, 10.1)))
        #expect(circle.contains(Vector2(5 + 7, 7)), "inside at 45° (r = 9.9)")
        #expect(!circle.contains(Vector2(5 + 7.2, 7.2)), "outside at 45° (r = 10.18)")
    }

    @Test func aHoleIsOutsideTheRegion() {
        let hole: [Segment2D] = [.arc(center: Vector2(0, 0), radius: 2, start: Angle(radians: 0), end: Angle(radians: 2 * .pi))]
        let plate = Profile2D(plane: .xy, outer: rectangle.outer, holes: [hole])
        #expect(!plate.contains(Vector2(0, 0)), "in the hole")
        #expect(plate.contains(Vector2(3, 0)), "beside the hole")
        #expect(plate.contains(Vector2(2, 0)), "on the hole's edge")
        #expect(!plate.contains(Vector2(20, 0)))
    }

    @Test func aClockwiseArcNotchIsHandled() {
        // An L-shaped notch: the region is the 20 × 10 rectangle without its top-right quarter.
        let corners = [Vector2(-10, -5), Vector2(10, -5), Vector2(10, 0), Vector2(0, 0), Vector2(0, 5), Vector2(-10, 5)]
        let loop = corners.indices.map { Segment2D.line(corners[$0], corners[($0 + 1) % corners.count]) }
        let profile = Profile2D(plane: .xy, segments: loop)
        #expect(profile.contains(Vector2(-5, 3)))
        #expect(profile.contains(Vector2(5, -3)))
        #expect(!profile.contains(Vector2(5, 3)), "in the notch")
    }

    @Test func anEmptyProfileContainsNothing() {
        #expect(!Profile2D(plane: .xy, outer: []).contains(Vector2(0, 0)))
    }
}
```


Create `Tests/CreatorNodesTests/Variation/CullByRegionNodeTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import Testing

/// Cull by Region (patterns spec §4): placements kept inside or outside a profile, or within or beyond a distance from a
/// point, an edge set or a face. Culling keeps paths.
struct CullByRegionNodeTests {
    /// A row of five placements on the X axis, 10 mm apart: x = −20, −10, 0, 10, 20 (indices 0 to 4), into a Cull by Region.
    struct Fixture {
        var h = Harness()
        let cull: Node
        let placements: Node

        init(_ settings: [SocketName: ConstantValue] = [:]) {
            let grid = h.add(GridPointsNode.self, ["countX": .integer(5), "countY": .integer(1)])
            placements = h.add(PointsToPlacementsNode.self)
            cull = h.add(CullByRegionNode.self, settings)
            h.wire(grid, "points", to: placements, "points")
            h.wire(placements, "placements", to: cull, "placements")
        }

        mutating func profile(width: Double, height: Double = 10, plane: Plane = .xy) {
            let rectangle = h.add(RectangleNode.self, ["width": .number(width), "height": .number(height), "plane": .plane(plane)])
            h.wire(rectangle, "profile", to: cull, "profile")
        }

        mutating func point(_ x: Double, _ y: Double = 0, _ z: Double = 0) {
            let vector = h.add(VectorNode.self, ["x": .number(x), "y": .number(y), "z": .number(z)])
            h.wire(vector, "vector", to: cull, "point")
        }

        func kept(_ kernel: any Kernel = FakeKernel()) async throws -> [Int] {
            let report = try await h.run([cull], kernel: kernel)
            if let message = report.error(cull) { throw NodeError.invalidValue(message) }
            return report.positions(cull, "placements")?.first ?? []
        }

        func message(_ kernel: any Kernel = FakeKernel()) async throws -> String? {
            let report = try await h.run([cull], kernel: kernel)
            return report.error(cull)
        }
    }

    // MARK: profile

    @Test func placementsInsideAProfileAreKept() async throws {
        var f = Fixture([:])
        f.profile(width: 25)
        #expect(try await f.kept() == [1, 2, 3])
    }

    @Test func placementsOutsideAProfileAreKept() async throws {
        var f = Fixture(["keep": .integer(1)])
        f.profile(width: 25)
        #expect(try await f.kept() == [0, 4])
    }

    @Test func aPlacementOnTheOutlineIsInside() async throws {
        var f = Fixture([:])
        f.profile(width: 20)
        #expect(try await f.kept() == [1, 2, 3], "x = ±10 lie on the outline")
    }

    @Test func theProfileIsAPrismSoHeightAboveItsPlaneDoesNotMatter() async throws {
        var f = Fixture([:])
        f.profile(width: 25, plane: .through(Vector3(0, 0, 50)))
        #expect(try await f.kept() == [1, 2, 3])
    }

    @Test func aProfileOnAnotherPlaneIsReadInItsOwnCoordinates() async throws {
        var f = Fixture([:])
        // Plane x = 0 facing +X: its local x is world Y and local y world Z, so a row along X all projects onto its origin.
        f.profile(width: 4, height: 4, plane: Plane(origin: .zero, normal: .unitX, xAxis: .unitY))
        #expect(try await f.kept() == [0, 1, 2, 3, 4])
    }

    @Test func theProfileIsRequiredForTheProfileReference() async throws {
        let f = Fixture([:])
        #expect(try await f.message() == "Connect or set “profile”.")
    }

    // MARK: point

    @Test func placementsWithinADistanceOfAPointAreKept() async throws {
        var f = Fixture(["reference": .integer(1), "distance": .number(12)])
        f.point(0, 0, 0)
        #expect(try await f.kept() == [1, 2, 3])
    }

    @Test func placementsBeyondADistanceOfAPointAreKept() async throws {
        var f = Fixture(["reference": .integer(1), "keep": .integer(1), "distance": .number(12)])
        f.point(0, 0, 0)
        #expect(try await f.kept() == [0, 4])
    }

    @Test func aPlacementAtExactlyTheDistanceIsWithin() async throws {
        var f = Fixture(["reference": .integer(1), "distance": .number(10)])
        f.point(0, 0, 0)
        #expect(try await f.kept() == [1, 2, 3])
    }

    @Test func distanceIsMeasuredInThreeDimensions() async throws {
        var f = Fixture(["reference": .integer(1), "distance": .number(10)])
        f.point(0, 0, 8)
        #expect(try await f.kept() == [2], "only x = 0 is within 10 of (0, 0, 8): √(10² + 8²) is 12.8")
    }

    @Test func aNegativeDistanceIsRefused() async throws {
        var f = Fixture(["reference": .integer(1), "distance": .number(-1)])
        f.point(0)
        #expect(try await f.message() == "“distance” can't be negative.")
    }

    // MARK: edges

    /// A 20 × 20 × 10 box on z = 0…10 (OCCT, for its exact edges), its edges wired into `edges`.
    func boxEdges(_ f: inout Fixture) {
        let box = f.h.box(20, 20, 10)
        let edges = f.h.add(AllEdgesNode.self)
        f.h.wire(box, "solid", to: edges, "solid")
        f.h.wire(edges, "edges", to: f.cull, "edges")
    }

    @Test func placementsWithinADistanceOfAnEdgeSetAreKept() async throws {
        var f = Fixture(["reference": .integer(2), "distance": .number(1)])
        boxEdges(&f)
        // The bottom edges at x = ±10 pass through the placements at x = ±10; the others are 10 away.
        #expect(try await f.kept(OCCTKernel()) == [1, 3])
    }

    @Test func placementsBeyondADistanceOfAnEdgeSetAreKept() async throws {
        var f = Fixture(["reference": .integer(2), "keep": .integer(1), "distance": .number(1)])
        boxEdges(&f)
        #expect(try await f.kept(OCCTKernel()) == [0, 2, 4])
    }

    @Test func edgesOfNoExactShapeAreRefusedWithTheCount() async throws {
        let spline = EdgeInfo(id: EdgeID(0), kind: .bspline, direction: nil, length: 5, midpoint: .zero, convexity: .convex, faces: [])
        let line = EdgeInfo(id: EdgeID(1), kind: .line, direction: .unitX, length: 5, midpoint: .zero, convexity: .convex, faces: [],
                            curve: .line(start: .zero, end: Vector3(5, 0, 0)))
        let base = try await FakeKernel().extrude(.rectangle(width: 1, height: 1, plane: .xy), distance: 1, mode: .oneSided,
                                                  tag: NodeTag(node: NodeID(), item: 0))
        let solid = Solid(topology: Topology(faces: [], edges: [spline, line]), bounds: base.bounds, storage: base.storage)
        let expected = "Cull by Region measures from straight and circular edges: 1 of the 2 selected edges are another kind of curve."
        #expect(throws: NodeError.invalidValue(expected)) {
            _ = try RegionDistance.nearestEdge(EdgeSet(solid: solid, edges: [EdgeID(0), EdgeID(1)]))
        }
    }

    @Test func aStraightEdgeIsMeasuredAsASegmentNotALine() {
        let edge = EdgeCurve.line(start: .zero, end: Vector3(10, 0, 0))
        #expect(isClose(RegionDistance.distance(from: Vector3(5, 3, 0), to: edge), 3))
        #expect(isClose(RegionDistance.distance(from: Vector3(13, 4, 0), to: edge), 5), "past the end it is the end that counts")
        #expect(isClose(RegionDistance.distance(from: Vector3(-3, -4, 0), to: edge), 5))
    }

    @Test func anArcIsMeasuredToItsEndsBeyondItsSweep() {
        // A quarter circle of radius 10 about the Z axis from +X to +Y.
        let arc = EdgeCurve.circle(center: .zero, axis: .unitZ, radius: 10, start: Vector3(10, 0, 0), sweep: .pi / 2)
        #expect(isClose(RegionDistance.distance(from: Vector3(7.071067811865476, 7.071067811865476, 0), to: arc), 0), "on the arc")
        #expect(isClose(RegionDistance.distance(from: Vector3(14.142135623730951, 14.142135623730951, 0), to: arc), 10))
        #expect(isClose(RegionDistance.distance(from: Vector3(10, -4, 0), to: arc), 4), "below the start: the start counts")
        #expect(isClose(RegionDistance.distance(from: Vector3(-3, 10, 0), to: arc), 3), "past the end: the end counts")
    }

    @Test func aCircularEdgeIsMeasuredToTheCircleNotTheCentre() async throws {
        // A circle of radius 10 on z = 0: the placements at x = ±10 are on it, the one at 0 is 10 from it, ±20 are 10 outside.
        let kernel = OCCTKernel()
        let tag = NodeTag(node: NodeID(), item: 0)
        let disc = try await kernel.extrude(.circle(radius: 10, center: .zero, plane: .xy), distance: 5, mode: .oneSided, tag: tag)
        let rim = disc.topology.edges.filter { $0.kind == .circle && !$0.isSeam && abs($0.midpoint.z) < 1e-6 }.map(\.id)
        let nearest = try RegionDistance.nearestEdge(EdgeSet(solid: disc, edges: rim))
        #expect(isClose(nearest(Vector3(10, 0, 0)), 0))
        #expect(isClose(nearest(Vector3(0, 0, 0)), 10))
        #expect(isClose(nearest(Vector3(20, 0, 0)), 10))
        #expect(isClose(nearest(Vector3(10, 0, 3)), 3))
        #expect(isClose(nearest(Vector3(0, 7, 0)), 3))
    }

    // MARK: faces

    @Test func distanceToAFlatFaceIsDistanceToItsPlane() async throws {
        let kernel = OCCTKernel()
        let tag = NodeTag(node: NodeID(), item: 0)
        let box = try await kernel.extrude(.rectangle(width: 20, height: 20, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
        let top = try #require(box.topology.faces.first { $0.kind == .plane && ($0.normal?.z ?? 0) > 0.5 })
        let nearest = try RegionDistance.nearestFace(FaceSet(solid: box, faces: [top.id]))
        #expect(isClose(nearest(Vector3(100, 100, 10)), 0), "far beside the face, on its plane")
        #expect(isClose(nearest(Vector3(0, 0, 4)), 6))
        #expect(isClose(nearest(Vector3(0, 0, 13)), 3), "above it counts the same")
    }

    @Test func aCurvedFaceIsRefusedWithTheCount() async throws {
        let kernel = OCCTKernel()
        let tag = NodeTag(node: NodeID(), item: 0)
        let can = try await kernel.extrude(.circle(radius: 5, center: .zero, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
        let wall = try #require(can.topology.faces.first { $0.kind == .cylinder })
        #expect(throws: NodeError.invalidValue("Cull by Region measures from flat faces for now: 1 of the 1 selected face is curved.")) {
            _ = try RegionDistance.nearestFace(FaceSet(solid: can, faces: [wall.id]))
        }
    }

    @Test func theFaceReferenceCullsByDistanceToTheFacePlane() async throws {
        let kernel = OCCTKernel()
        let tag = NodeTag(node: NodeID(), item: 0)
        let box = try await kernel.extrude(.rectangle(width: 40, height: 20, plane: .xy), distance: 10, mode: .oneSided, tag: tag)
        let top = try #require(box.topology.faces.first { $0.kind == .plane && ($0.normal?.z ?? 0) > 0.5 })
        let placements = DataTree.list([-20, -10, 0, 10, 20].map { .plane(.through(Vector3(Double($0), 0, 4))) })
        let node = BuiltInNodes.registry.makeNode(CullByRegionNode.typeID)
        let inputs = NodeInputs(item: 0, slots: [
            "placements": .tree(placements), "reference": .item(.integer(3)), "keep": .item(.integer(0)),
            "distance": .item(.number(7)), "faces": .item(.faceSet(FaceSet(solid: box, faces: [top.id]))),
        ])
        let context = EvalContext(node: node, item: 0, parameters: [:])
        let outputs = try await CullByRegionNode.evaluate(inputs, kernel: kernel, context: context)
        #expect(try #require(outputs.trees["placements"]).itemCount == 5, "all are 6 mm below the top face, within 7")
    }

    // MARK: shape

    @Test func aTreeOfPlacementsKeepsItsBranchesAndPaths() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self, ["countX": .integer(3), "countY": .integer(2), "centred": .bool(false)])
        let placements = h.add(PointsToPlacementsNode.self)
        let rows = h.add(PartitionNode.self, ["size": .integer(3)])
        let cull = h.add(CullByRegionNode.self, ["reference": .integer(1), "keep": .integer(1), "distance": .number(5)])
        let origin = h.add(VectorNode.self)
        h.wire(grid, "points", to: placements, "points")
        h.wire(placements, "placements", to: rows, "tree")
        h.wire(rows, "tree", to: cull, "placements")
        h.wire(origin, "vector", to: cull, "point")
        let report = try await h.run([cull])
        // Points (0,0) (10,0) (20,0) / (0,10) (10,10) (20,10): beyond 5 mm of the origin leaves all but {0;0}.
        #expect(report.positions(cull, "placements") == [[1, 2], [0, 1, 2]])
        #expect(report.tree(cull, "placements")?.depth == 2)
    }
}
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
        #expect(BuiltInNodes.all.count == 43)
```

with:

```swift
        #expect(BuiltInNodes.all.count == 44)
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
.feature: 2, .patterns: 8, .lists: 7
```

with:

```swift
.feature: 2, .patterns: 9, .lists: 7
```


In `Tests/CreatorEditorTests/PatternsLibraryTests.swift`, replace:

```swift
            "Cull Pattern", "Cull Index",
        ])
```

with:

```swift
            "Cull Pattern", "Cull Index", "Cull by Region",
        ])
```


- [ ] **Step 2: Run them**

Run: `swift test --filter "CullByRegionNodeTests|ProfileContainsTests|OutputNodeTests|PatternsLibraryTests|CatalogTests|BuiltInNodesInspectorTests" 2>&1 | grep -v 'ld: warning'`

Expected: FAIL, the tests do not build (`value of type 'Profile2D' has no member 'contains'`).

- [ ] **Step 3: Write the implementation**

Create `Sources/CreatorGeometry/Profile2D+Contains.swift`:

```swift
import Foundation

extension Profile2D {
    /// Whether `point`, in the plane's own coordinates, is on the region: inside the outer loop and outside every hole, or
    /// on a loop's line to `tolerance` (a point on the outline counts as inside). Arcs are walked as chords no more than 2°
    /// long, so an arc is found to within 0.00015 of its radius.
    public func contains(_ point: Vector2, tolerance: Double = 1e-6) -> Bool {
        var crossings = 0
        for loop in loops {
            let outline = Self.outline(of: loop)
            for (p, q) in zip(outline, outline.dropFirst()) {
                if Self.distance(from: point, toSegment: p, q) <= tolerance { return true }
                // Even-odd rule over every loop, so a hole's inside is outside the region.
                if (p.y > point.y) != (q.y > point.y), point.x < p.x + (point.y - p.y) / (q.y - p.y) * (q.x - p.x) {
                    crossings += 1
                }
            }
        }
        return crossings % 2 == 1
    }

    /// The corners of a loop, arcs cut into chords of 2° at most.
    private static func outline(of loop: [Segment2D]) -> [Vector2] {
        guard let first = loop.first else { return [] }
        var points = [first.startPoint]
        for segment in loop {
            switch segment {
            case .line(_, let end):
                points.append(end)
            case .arc(let center, let radius, let start, let end):
                let sweep = end.radians - start.radians
                let steps = max(2, Int((abs(sweep) / (.pi / 90)).rounded(.up)))
                for step in 1..<steps {
                    let angle = start.radians + sweep * Double(step) / Double(steps)
                    points.append(center + Vector2(cos(angle), sin(angle)) * radius)
                }
                points.append(segment.endPoint)
            }
        }
        return points
    }

    private static func distance(from point: Vector2, toSegment a: Vector2, _ b: Vector2) -> Double {
        let (dx, dy) = (b.x - a.x, b.y - a.y)
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (point - a).length }
        let along = min(1, max(0, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared))
        return (point - (a + Vector2(dx, dy) * along)).length
    }
}
```


Create `Sources/CreatorNodes/Patterns/Variation/CullByRegionNode.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Keeps or culls placements by where they are (patterns spec §4): inside or outside a profile, or within or beyond a distance
/// from a point, from an edge set, or from a face. A placement is judged by its origin. A profile is a prism along its plane's
/// normal, so a placement's height above the plane doesn't matter; a distance is taken to the point, to the nearest straight or
/// circular edge, or to the plane of the nearest flat face (a placement beside a small face counts as near it all the same).
/// A placement exactly on the outline or at exactly the distance counts as inside or within. Culling keeps paths: the rest keep
/// the indices they had, so a pick on one follows it (§6).
public enum CullByRegionNode: NodeDefinition {
    public static let typeID = "creator.cullByRegion"
    public static let displayName = "Cull by Region"
    public static let category = NodeCategory.patterns
    public static let references = ["Profile", "Point", "Edges", "Face"]
    public static let sides = ["Inside or within", "Outside or beyond"]
    public static let inputs = [
        SocketSpec("placements", .plane, access: .tree),
        SocketSpec("reference", .integer, defaultValue: .integer(0)),
        SocketSpec("keep", .integer, defaultValue: .integer(0)),
        SocketSpec("profile", .profile, optional: true),
        SocketSpec("point", .vector, optional: true),
        SocketSpec("edges", .edgeSet, optional: true),
        SocketSpec("faces", .faceSet, optional: true),
        SocketSpec("distance", .number, defaultValue: .number(10), unit: .millimetres, range: 0...1000),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static let inspector = [
        InspectorSection(title: "Region", controls: [.segmented("reference", options: references), .slider("distance")]),
        InspectorSection(title: "Keep", controls: [.segmented("keep", options: sides)]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("placements")
        guard tree.items.allSatisfy({ $0.type == .plane }) else { throw NodeError.typeMismatch("placements", expected: .plane) }
        let reference = try inputs.choice("reference", options: references)
        let keepsInside = try inputs.choice("keep", options: sides) == 0
        let distance = try inputs.number("distance")
        guard distance.isFinite, distance >= 0 else { throw NodeError.invalidValue("“distance” can't be negative.") }
        let isInside: @Sendable (Vector3) -> Bool
        switch reference {
        case 0:
            let profile = try inputs.profile("profile")
            isInside = { point in profile.contains(Self.local(point, in: profile.plane)) }
        case 1:
            let center = try inputs.vector("point")
            isInside = { ($0 - center).length <= distance + 1e-9 }
        case 2:
            let nearest = try RegionDistance.nearestEdge(try inputs.edgeSet("edges"))
            isInside = { nearest($0) <= distance + 1e-9 }
        default:
            guard case .faceSet(let faces) = try inputs.scalar("faces") else { throw NodeError.typeMismatch("faces", expected: .faceSet) }
            let nearest = try RegionDistance.nearestFace(faces)
            isInside = { nearest($0) <= distance + 1e-9 }
        }
        let kept = tree.keepingItems { leaf, _, k in
            guard case .plane(let plane) = leaf.items[k] else { return true }
            return isInside(plane.origin) == keepsInside
        }
        return NodeOutputs(trees: ["placements": kept])
    }

    /// `point` in the plane's own coordinates (the height above it dropped).
    private static func local(_ point: Vector3, in plane: Plane) -> Vector2 {
        let offset = point - plane.origin
        return Vector2(offset.dot(plane.xAxis), offset.dot(plane.yAxis))
    }
}
```


Create `Sources/CreatorNodes/Patterns/Variation/RegionDistance.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

/// How far a point is from the things Cull by Region measures from (patterns spec §4): a point, the edges of an edge set, or
/// the flat faces of a face set. Straight and circular edges are measured exactly; a curved face is not measured at all.
enum RegionDistance {
    /// The distance from `point` to the nearest of `edges`, which must all be straight or circular.
    static func nearestEdge(_ edges: EdgeSet) throws -> @Sendable (Vector3) -> Double {
        let found = edges.edges.compactMap { edges.solid.topology.edge($0) }
        guard !found.isEmpty else { throw NodeError.invalidValue("“edges” is empty, so there is nothing to measure from.") }
        let curves = found.compactMap(\.curve)
        guard curves.count == found.count else {
            let other = found.count - curves.count
            throw NodeError.invalidValue("Cull by Region measures from straight and circular edges: \(other.display) of the "
                + "\(found.count.display) selected \(found.count == 1 ? "edge is" : "edges are") another kind of curve.")
        }
        return { point in curves.map { distance(from: point, to: $0) }.min() ?? .infinity }
    }

    /// The distance from `point` to the nearest of the flat faces of `faces`, taken to the face's plane.
    static func nearestFace(_ faces: FaceSet) throws -> @Sendable (Vector3) -> Double {
        let found = faces.faces.compactMap { faces.solid.topology.face($0) }
        guard !found.isEmpty else { throw NodeError.invalidValue("“faces” is empty, so there is nothing to measure from.") }
        let planes = found.compactMap { face -> (origin: Vector3, normal: Vector3)? in
            guard face.kind == .plane, let normal = face.normal?.normalized else { return nil }
            return (face.centroid, normal)
        }
        guard planes.count == found.count else {
            throw NodeError.invalidValue("Cull by Region measures from flat faces for now: \((found.count - planes.count).display) of the "
                + "\(found.count.display) selected \(found.count == 1 ? "face is" : "faces are") curved.")
        }
        return { point in planes.map { abs(($0.normal).dot(point - $0.origin)) }.min() ?? .infinity }
    }

    static func distance(from point: Vector3, to curve: EdgeCurve) -> Double {
        switch curve {
        case .line(let start, let end):
            let direction = end - start
            let lengthSquared = direction.dot(direction)
            guard lengthSquared > 0 else { return (point - start).length }
            let along = min(1, max(0, (point - start).dot(direction) / lengthSquared))
            return (point - (start + direction * along)).length
        case .circle(let center, let axis, let radius, let start, let sweep):
            return distance(from: point, toCircle: center, axis: axis, radius: radius, start: start, sweep: sweep)
        }
    }

    /// To an arc: straight to the circle where the point's angle about the axis is within the sweep, else to the nearer end.
    private static func distance(from point: Vector3, toCircle center: Vector3, axis: Vector3, radius: Double, start: Vector3,
                                 sweep: Double) -> Double {
        guard let normal = axis.normalized, let first = (start - center).normalized else { return (point - center).length }
        let second = normal.cross(first)
        let offset = point - center
        let height = offset.dot(normal)
        let (x, y) = (offset.dot(first), offset.dot(second))
        var angle = atan2(y, x)
        if angle < 0 { angle += 2 * .pi }
        if sweep >= 2 * .pi - 1e-9 || angle <= sweep {
            let across = (x * x + y * y).squareRoot() - radius
            return (height * height + across * across).squareRoot()
        }
        let end = center + first * (radius * cos(sweep)) + second * (radius * sin(sweep))
        return min((point - start).length, (point - end).length)
    }
}
```


In `Sources/CreatorNodes/BuiltInNodes.swift`, replace:

```swift
        OutputNode.self,
    ]
```

with:

```swift
        CullByRegionNode.self,
        OutputNode.self,
    ]
```


- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter "CullByRegionNodeTests|ProfileContainsTests|OutputNodeTests|PatternsLibraryTests|CatalogTests|BuiltInNodesInspectorTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

- [ ] **Step 5: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > /tmp/vtest.log 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,764 = master + 125** (+28 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(7a-3b): Cull by Region, placements inside/outside a profile or near a point, edges or face"
```

---

### Task 7: Random Reduce

**Files:**

- Create: `Sources/CreatorNodes/Patterns/Variation/RandomReduceNode.swift`
- Create: `Sources/CreatorNodes/Patterns/Variation/RandomReduction.swift`
- Modify: `Sources/CreatorNodes/BuiltInNodes.swift`
- Test: `Tests/CreatorNodesTests/Variation/RandomReduceNodeTests.swift` (new)
- Test: `Tests/CreatorEditorTests/PatternsLibraryTests.swift` (modify)
- Test: `Tests/CreatorNodesTests/OutputNodeTests.swift` (modify)

**Interfaces:**

- Consumes: Task 1 `SeededRandom`; Task 2 `keepingItems`, `Leaf.positions`; `NodeInputs.choice`.
- Produces: `RandomReduction.slotsToDrop(in:seed:amount:overall:) -> Set<RandomReduction.Slot>`; `RandomReduceNode` (`creator.randomReduce`;
inputs `tree` (any, tree), `by`, `count`, `fraction`, `scope`, `seed`; output `tree`).

Drop N or a fraction, per branch or overall (Key decision 6). The pinned results in the tests were worked out directly from the generator
(a tiny script of its own, ranking the draws of the `Reduce_1` purpose), not by running the node, so they check the node against the algorithm.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorNodesTests/Variation/RandomReduceNodeTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Random Reduce (patterns spec §4): drop N or a fraction, per branch or overall, always from a seed. The pinned results
/// were worked out straight from the generator (SplitMix64, `SeededRandomTests`, purpose `.reduce`): each item's key is the draw at
/// its index in the stream of its branch's ordinal, and the smallest keys go.
struct RandomReduceNodeTests {
    func reduce(_ settings: [SocketName: ConstantValue], count: Int,
                rows: Int? = nil) async throws -> (report: EvaluationReport, node: Node) {
        var h = Harness()
        let source = h.source(count: count, rows: rows)
        let reduce = h.add(RandomReduceNode.self, settings)
        h.wire(source, to: reduce, "tree")
        return (try await h.run([reduce]), reduce)
    }

    // MARK: pinned results

    @Test func seed42DropsThreeOfTenAtIndices1And2And5() async throws {
        let (report, node) = try await reduce(["count": .integer(3), "seed": .integer(42)], count: 10)
        #expect(report.positions(node) == [[0, 3, 4, 6, 7, 8, 9]])
        #expect(report.value(node, "tree")?.outline == "[0,3,4,6,7,8,9]")
        #expect(report.isOK(node), "a seed never warns")
    }

    @Test func perBranchEveryBranchLosesItsOwnItem() async throws {
        let (report, node) = try await reduce(["seed": .integer(7)], count: 12, rows: 4)
        #expect(report.positions(node) == [[0, 1, 2], [1, 2, 3], [0, 2, 3]])
        let (other, otherNode) = try await reduce(["seed": .integer(8)], count: 12, rows: 4)
        #expect(other.positions(otherNode) == [[0, 1, 3], [1, 2, 3], [0, 2, 3]])
    }

    @Test func overallTheWholeTreeLosesThreeWhereverTheyAre() async throws {
        let (report, node) = try await reduce(["count": .integer(3), "scope": .integer(1), "seed": .integer(7)], count: 12, rows: 4)
        #expect(report.positions(node) == [[1, 2], [0, 1, 2, 3], [0, 2, 3]])
    }

    // MARK: properties

    @Test func theSameSeedGivesTheSameResultEveryTime() async throws {
        let first = try await reduce(["count": .integer(4), "seed": .integer(99)], count: 20)
        let second = try await reduce(["count": .integer(4), "seed": .integer(99)], count: 20)
        #expect(first.report.positions(first.node) == second.report.positions(second.node))
    }

    @Test func anotherSeedDropsOtherItems() async throws {
        var seen = Set<[[Int]]>()
        for seed in 0..<8 {
            let (report, node) = try await reduce(["count": .integer(3), "seed": .integer(seed)], count: 20)
            seen.insert(try #require(report.positions(node)))
        }
        #expect(seen.count > 4, "eight seeds make more than four different choices")
    }

    @Test func aBiggerCountDropsWhatASmallerOneDidAndMore() async throws {
        let two = try await reduce(["count": .integer(2), "seed": .integer(42)], count: 10)
        let three = try await reduce(["count": .integer(3), "seed": .integer(42)], count: 10)
        let keptTwo = Set(try #require(two.report.positions(two.node)?.first))
        let keptThree = Set(try #require(three.report.positions(three.node)?.first))
        #expect(keptThree.isSubset(of: keptTwo))
        #expect(keptTwo.subtracting(keptThree).count == 1)
    }

    @Test func moreItemsAtTheEndNeverChangeWhichEarlierOneIsLowest() async throws {
        let short = try await reduce(["seed": .integer(42)], count: 8)
        let long = try await reduce(["seed": .integer(42)], count: 10)
        let droppedShort = Set(0..<8).subtracting(try #require(short.report.positions(short.node)?.first))
        let droppedLong = Set(0..<10).subtracting(try #require(long.report.positions(long.node)?.first))
        #expect(droppedShort == [5] && droppedLong == [5])
    }

    // MARK: amounts

    @Test func aFractionIsRoundedToTheNearestWholeItemHalvesUp() async throws {
        for (fraction, dropped) in [(0.0, 0), (0.25, 2), (0.5, 3), (0.75, 5), (1.0, 6)] {
            let (report, node) = try await reduce(["by": .integer(1), "fraction": .number(fraction)], count: 6)
            #expect(report.tree(node)?.itemCount == 6 - dropped, "\(fraction) of 6 drops \(dropped)")
        }
    }

    @Test func aFractionPerBranchTakesThatFractionOfEachBranch() async throws {
        let (report, node) = try await reduce(["by": .integer(1), "fraction": .number(0.5)], count: 12, rows: 4)
        #expect(report.positions(node)?.map(\.count) == [2, 2, 2])
    }

    @Test func aCountLargerThanTheBranchDropsItAllWithoutAWarning() async throws {
        let (report, node) = try await reduce(["count": .integer(9)], count: 6, rows: 3)
        #expect(report.positions(node) == [[], []])
        #expect(report.isOK(node))
    }

    @Test func dropNothingChangesNothingAndAPlainListStaysPlain() async throws {
        let (report, node) = try await reduce(["count": .integer(0)], count: 5)
        #expect(report.value(node, "tree")?.isList == true)
    }

    // MARK: paths

    @Test func itWorksOnWhatIsLeftAfterAnotherCullAndKeepsItsPaths() async throws {
        var h = Harness()
        let source = h.source(count: 10)
        let pattern = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])  // {0}, {2}, {4}, {6}, {8}
        let reduce = h.add(RandomReduceNode.self, ["count": .integer(2), "seed": .integer(3)])
        h.wire(source, to: pattern, "tree")
        h.wire(pattern, "tree", to: reduce, "tree")
        let report = try await h.run([reduce])
        let kept = try #require(report.positions(reduce)?.first)
        #expect(kept.count == 3)
        #expect(Set(kept).isSubset(of: [0, 2, 4, 6, 8]), "only paths that were there, none renumbered")
    }

    @Test func anEmptyBranchStaysAndIsNotAnError() async throws {
        var h = Harness()
        let source = h.source(count: 4, rows: 2)
        let none = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("0")])
        let reduce = h.add(RandomReduceNode.self)
        h.wire(source, to: none, "tree")
        h.wire(none, "tree", to: reduce, "tree")
        let report = try await h.run([reduce])
        #expect(report.isOK(reduce))
        #expect(report.positions(reduce) == [[], []])
    }

    // MARK: refusals

    @Test func badAmountsAreRefusedInPlainWords() async throws {
        let (negative, negativeNode) = try await reduce(["count": .integer(-1)], count: 4)
        #expect(negative.error(negativeNode) == "“count” can't be negative.")
        for fraction in [-0.1, 1.5] {
            let (report, node) = try await reduce(["by": .integer(1), "fraction": .number(fraction)], count: 4)
            #expect(report.error(node) == "“fraction” must be between 0 and 1: 0 drops nothing and 1 drops everything.")
        }
        let (choice, choiceNode) = try await reduce(["scope": .integer(5)], count: 4)
        #expect(choice.error(choiceNode) == "Choose Per branch or Overall for “scope”.")
    }
}
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
        #expect(BuiltInNodes.all.count == 44)
```

with:

```swift
        #expect(BuiltInNodes.all.count == 45)
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
.feature: 2, .patterns: 9, .lists: 7
```

with:

```swift
.feature: 2, .patterns: 10, .lists: 7
```


In `Tests/CreatorEditorTests/PatternsLibraryTests.swift`, replace:

```swift
            "Cull Pattern", "Cull Index", "Cull by Region",
        ])
```

with:

```swift
            "Cull Pattern", "Cull Index", "Cull by Region", "Random Reduce",
        ])
```


- [ ] **Step 2: Run them**

Run: `swift test --filter "RandomReduceNodeTests|OutputNodeTests|PatternsLibraryTests|CatalogTests|BuiltInNodesInspectorTests" 2>&1 | grep -v 'ld: warning'`

Expected: FAIL, the tests do not build (`cannot find 'RandomReduceNode' in scope`).

- [ ] **Step 3: Write the implementation**

Create `Sources/CreatorNodes/Patterns/Variation/RandomReduceNode.swift`:

```swift
import CreatorGraph
import CreatorKernel

/// Drops items at random (patterns spec §4): a count or a fraction, from each branch or from the whole tree. It is always
/// seeded: the same seed drops the same items on every machine and in every release (`SeededRandom`, SplitMix64), so an
/// edit elsewhere never reshuffles it, and a new seed is just a different draw, never a warning. Culling keeps paths: the
/// items that stay keep their indices, so a pick on one follows it (§6) and a pick on a dropped item warns naming its path.
public enum RandomReduceNode: NodeDefinition {
    public static let typeID = "creator.randomReduce"
    public static let displayName = "Random Reduce"
    public static let category = NodeCategory.patterns
    public static let amounts = ["Count", "Fraction"]
    public static let scopes = ["Per branch", "Overall"]
    public static let inputs = [
        SocketSpec("tree", .any, access: .tree),
        SocketSpec("by", .integer, defaultValue: .integer(0)),
        SocketSpec("count", .integer, defaultValue: .integer(1), unit: .count),
        SocketSpec("fraction", .number, defaultValue: .number(0.25), range: 0...1),
        SocketSpec("scope", .integer, defaultValue: .integer(0)),
        SocketSpec("seed", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("tree", .any)]
    public static let inspector = [
        InspectorSection(title: "Drop", controls: [.segmented("by", options: amounts), .integer("count"), .slider("fraction")]),
        InspectorSection(title: "Random", controls: [.segmented("scope", options: scopes), .integer("seed")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("tree")
        let amount: RandomReduction.Amount
        if try inputs.choice("by", options: amounts) == 0 {
            let count = try inputs.integer("count")
            guard count >= 0 else { throw NodeError.invalidValue("“count” can't be negative.") }
            amount = .count(count)
        } else {
            let fraction = try inputs.number("fraction")
            guard fraction.isFinite, (0...1).contains(fraction) else {
                throw NodeError.invalidValue("“fraction” must be between 0 and 1: 0 drops nothing and 1 drops everything.")
            }
            amount = .fraction(fraction)
        }
        let overall = try inputs.choice("scope", options: scopes) == 1
        let dropped = RandomReduction.slotsToDrop(in: tree, seed: try inputs.integer("seed"), amount: amount, overall: overall)
        let kept = tree.keepingItems { _, ordinal, k in !dropped.contains(RandomReduction.Slot(ordinal: ordinal, k: k)) }
        return NodeOutputs(trees: ["tree": kept])
    }
}
```


Create `Sources/CreatorNodes/Patterns/Variation/RandomReduction.swift`:

```swift
import CreatorGraph

/// Which items a Random Reduce drops (patterns spec §4). Every item gets a key from the seeded generator (purpose `.reduce`, so
/// the same seed on Random Values or Jitter draws other numbers), drawn by where it
/// is (its branch's ordinal as the stream, its index in the branch as the draw), and the items with the smallest keys go.
/// So the choice depends on the seed and on the items' places alone: the same seed drops the same items on every machine, a
/// bigger amount drops the ones a smaller amount did and more, and adding items to the end never changes which of the
/// earlier ones are lowest.
enum RandomReduction {
    /// How much to drop from a branch (or, overall, from the tree).
    enum Amount {
        case count(Int)
        case fraction(Double)

        /// How many of `items` to drop: a count is capped at the items there are, a fraction is rounded to the nearest whole
        /// number with halves going up (a quarter of 6 items is 2).
        func dropped(of items: Int) -> Int {
            switch self {
            case .count(let count): min(count, items)
            case .fraction(let fraction): min(items, Int((fraction * Double(items)).rounded(.toNearestOrAwayFromZero)))
            }
        }
    }

    /// One item: the ordinal of its branch (`DataTree.rebuildingLeaves`) and its place among that branch's items.
    struct Slot: Hashable {
        let ordinal: Int
        let k: Int
    }

    private struct Ranked {
        let key: UInt64
        let slot: Slot

        /// By key, then by place, so equal keys (which a 64-bit draw makes vanishingly rare) still sort the same everywhere.
        static func before(_ a: Ranked, _ b: Ranked) -> Bool {
            (a.key, a.slot.ordinal, a.slot.k) < (b.key, b.slot.ordinal, b.slot.k)
        }
    }

    /// The items to drop from `tree`: `amount` of each branch, or of the whole tree when `overall`.
    static func slotsToDrop(in tree: DataTree, seed: Int, amount: Amount, overall: Bool) -> Set<Slot> {
        let ranked = tree.leaves.enumerated().map { ordinal, leaf -> [Ranked] in
            let random = SeededRandom(seed: seed, stream: ordinal, purpose: .reduce)
            return leaf.positions.enumerated().map { k, position in
                Ranked(key: random.value(at: position), slot: Slot(ordinal: ordinal, k: k))
            }
        }
        let groups = overall ? [ranked.flatMap { $0 }] : ranked
        var dropped = Set<Slot>()
        for group in groups {
            let ordered = group.sorted(by: Ranked.before)
            dropped.formUnion(ordered.prefix(amount.dropped(of: ordered.count)).map(\.slot))
        }
        return dropped
    }
}
```


In `Sources/CreatorNodes/BuiltInNodes.swift`, replace:

```swift
        OutputNode.self,
    ]
```

with:

```swift
        RandomReduceNode.self,
        OutputNode.self,
    ]
```


- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter "RandomReduceNodeTests|OutputNodeTests|PatternsLibraryTests|CatalogTests|BuiltInNodesInspectorTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

- [ ] **Step 5: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > /tmp/vtest.log 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,778 = master + 139** (+14 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(7a-3b): Random Reduce, seeded and stable, per branch or overall"
```

---

### Task 8: Random Values

**Files:**

- Create: `Sources/CreatorNodes/Patterns/Variation/RandomValuesNode.swift`
- Modify: `Sources/CreatorNodes/BuiltInNodes.swift`
- Test: `Tests/CreatorNodesTests/Variation/RandomValuesNodeTests.swift` (new)
- Test: `Tests/CreatorEditorTests/PatternsLibraryTests.swift` (modify)
- Test: `Tests/CreatorNodesTests/OutputNodeTests.swift` (modify)

**Interfaces:**

- Consumes: Tasks 1 and 2 (`replacingItems`); `Int.display`.
- Produces: `RandomValuesNode` (`creator.randomValues`; inputs `shape` (any, tree, optional), `count`, `min`, `max`, `seed`; outputs `values` (number) and `integers` (integer, optional)).

Per-instance reals or whole numbers in a range, in the shape of a tree or a count (Key decision 7). Because it refills a tree, a culled shape gets
its numbers at the paths it kept, and each number is the one the full shape would have given that path.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorNodesTests/Variation/RandomValuesNodeTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Random Values (patterns spec §4): per-instance reals or whole numbers in a range, in the shape of a tree or a count, from a
/// seed. The pinned numbers come straight from the generator (SplitMix64, `SeededRandomTests`, purpose `.values`): the item at
/// index `i` of a branch with ordinal `n` gets draw `i` of stream `n`.
struct RandomValuesNodeTests {
    func run(_ settings: [SocketName: ConstantValue], shape: Int? = nil, rows: Int? = nil,
             culling pattern: String? = nil) async throws -> (report: EvaluationReport, node: Node) {
        var h = Harness()
        let node = h.add(RandomValuesNode.self, settings)
        if let shape {
            var source = h.source(count: shape, rows: rows)
            if let pattern {
                let cull = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text(pattern)])
                h.wire(source, to: cull, "tree")
                source = TreeSource(node: cull, socket: "tree")
            }
            h.wire(source, to: node, "shape")
        }
        return (try await h.run([node]), node)
    }

    func close(_ actual: [Double]?, _ expected: [Double]) -> Bool {
        guard let actual, actual.count == expected.count else { return false }
        return zip(actual, expected).allSatisfy { isClose($0, $1, relative: 1e-12) }
    }

    // MARK: pinned numbers

    @Test func seed42GivesPinnedRealsFromZeroToOne() async throws {
        let (report, node) = try await run(["count": .integer(4), "seed": .integer(42)])
        #expect(close(report.value(node, "values")?.numbers,
                      [0.975521979100528, 0.6467038549042005, 0.1577190784555612, 0.32818821561135025]))
        #expect(report.isOK(node), "a seed never warns")
    }

    @Test func realsAreScaledIntoTheRange() async throws {
        let (report, node) = try await run(["count": .integer(4), "min": .number(10), "max": .number(20), "seed": .integer(42)])
        #expect(close(report.value(node, "values")?.numbers,
                      [19.75521979100528, 16.467038549042005, 11.577190784555611, 13.281882156113502]))
    }

    @Test func wholeNumbersAreInTheRangeAndPinned() async throws {
        let (report, node) = try await run(["count": .integer(4), "min": .number(0), "max": .number(9), "seed": .integer(42)])
        #expect(report.value(node, "integers")?.integers == [9, 6, 1, 3])
        let (dice, diceNode) = try await run(["count": .integer(4), "min": .number(1), "max": .number(6), "seed": .integer(42)])
        #expect(dice.value(diceNode, "integers")?.integers == [6, 4, 1, 2], "1 to 6 is the draws 5, 3, 0, 1 plus 1")
    }

    @Test func aNegativeSeedIsAValidSeed() async throws {
        let (report, node) = try await run(["count": .integer(3), "seed": .integer(-5)])
        #expect(close(report.value(node, "values")?.numbers, [0.8078499237740443, 0.031857563103228737, 0.5850738692585525]))
    }

    @Test func eachBranchDrawsFromItsOwnStream() async throws {
        let (report, node) = try await run(["min": .number(0), "max": .number(9), "seed": .integer(42)], shape: 4, rows: 2)
        // Branch 0 uses stream 0 (9, 6) and branch 1 stream 1 (5, 2).
        #expect(report.value(node, "integers")?.outline == "[[9,6],[5,2]]")
    }

    // MARK: independence

    @Test func theFirstNumbersDoNotDependOnHowManyThereAre() async throws {
        let few = try await run(["count": .integer(4), "seed": .integer(11)])
        let many = try await run(["count": .integer(9), "seed": .integer(11)])
        let manyNumbers = try #require(many.report.value(many.node, "values")?.numbers)
        #expect(close(few.report.value(few.node, "values")?.numbers, Array(manyNumbers.prefix(4))))
    }

    @Test func anotherSeedGivesOtherNumbers() async throws {
        let first = try await run(["count": .integer(5), "seed": .integer(1)])
        let second = try await run(["count": .integer(5), "seed": .integer(2)])
        #expect(first.report.value(first.node, "values")?.numbers != second.report.value(second.node, "values")?.numbers)
    }

    @Test func theSameSeedGivesTheSameNumbersEveryTime() async throws {
        let first = try await run(["count": .integer(50), "seed": .integer(123)])
        let second = try await run(["count": .integer(50), "seed": .integer(123)])
        #expect(first.report.value(first.node, "values")?.numbers == second.report.value(second.node, "values")?.numbers)
    }

    // MARK: shape

    @Test func aWiredShapeSetsTheNestingAndCountIsIgnored() async throws {
        let (report, node) = try await run(["count": .integer(99)], shape: 7, rows: 3)
        #expect(report.tree(node, "values")?.dimensions == nil)
        #expect(report.value(node, "values")?.outline.hasPrefix("[[") == true)
        #expect(report.tree(node, "values")?.leaves.map(\.items.count) == [3, 3, 1])
    }

    @Test func aCulledShapeGetsNumbersAtThePathsItKeptAndTheOthersKeepTheirNumbers() async throws {
        let all = try await run(["seed": .integer(42)], shape: 6, rows: 3)
        let culled = try await run(["seed": .integer(42)], shape: 6, rows: 3, culling: "1 0")
        let allTree = try #require(all.report.tree(all.node, "values"))
        let culledTree = try #require(culled.report.tree(culled.node, "values"))
        #expect(culledTree.leaves.map(\.positions) == [[0, 2], [0, 2]], "the numbers sit at the paths that were kept")
        // The numbers at the kept paths are the ones the uncilled shape gives those paths.
        let wanted = allTree.leaves.flatMap { leaf in [0, 2].map { leaf.items[$0] } }
        #expect(culledTree.items.map(\.outlineText) == wanted.map(\.outlineText))
    }

    @Test func theNumbersFitStraightIntoASizeInput() async throws {
        var h = Harness()
        let random = h.add(RandomValuesNode.self, ["count": .integer(3), "min": .number(5), "max": .number(15), "seed": .integer(42)])
        let circle = h.add(CircleNode.self)
        h.wire(random, "values", to: circle, "diameter")
        let report = try await h.run([circle])
        #expect(report.value(circle, "profile")?.profiles?.count == 3, "three circles, one diameter each")
    }

    // MARK: range

    @Test func aRangeWithNoWholeNumberLeavesTheIntegersOutButStillGivesReals() async throws {
        let (report, node) = try await run(["count": .integer(3), "min": .number(0.2), "max": .number(0.8)])
        #expect(report.value(node, "values")?.numbers?.count == 3)
        #expect(report.value(node, "integers") == nil)
        #expect(report.isOK(node))
    }

    @Test func aSingleValuedRangeAlwaysGivesIt() async throws {
        let (report, node) = try await run(["count": .integer(3), "min": .number(4), "max": .number(4)])
        #expect(report.value(node, "values")?.numbers == [4, 4, 4])
        #expect(report.value(node, "integers")?.integers == [4, 4, 4])
    }

    @Test func negativeRangesWork() async throws {
        let (report, node) = try await run(["count": .integer(200), "min": .number(-3), "max": .number(3), "seed": .integer(9)])
        let whole = try #require(report.value(node, "integers")?.integers)
        #expect(whole.allSatisfy { (-3...3).contains($0) })
        #expect(Set(whole) == Set(-3...3), "every whole number from −3 to 3 turns up in 200 draws")
        #expect(try #require(report.value(node, "values")?.numbers).allSatisfy { (-3.0..<3.0).contains($0) })
    }

    // MARK: refusals

    @Test func badSettingsAreRefusedInPlainWords() async throws {
        let (backwards, backwardsNode) = try await run(["min": .number(5), "max": .number(1)])
        #expect(backwards.error(backwardsNode) == "“min” can't be more than “max”.")
        let (negative, negativeNode) = try await run(["count": .integer(-1)])
        #expect(negative.error(negativeNode) == "“count” can't be negative.")
        let (huge, hugeNode) = try await run(["count": .integer(100_001)])
        #expect(huge.error(hugeNode) == "Random Values makes at most 100,000 numbers.")
        let (infinite, infiniteNode) = try await run(["max": .number(.infinity)])
        #expect(infinite.error(infiniteNode) == "“min” and “max” must be numbers.")
    }

    @Test func zeroCountMakesAnEmptyList() async throws {
        let (report, node) = try await run(["count": .integer(0)])
        #expect(report.value(node, "values")?.items.isEmpty == true)
    }
}
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
        #expect(BuiltInNodes.all.count == 45)
```

with:

```swift
        #expect(BuiltInNodes.all.count == 46)
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
.feature: 2, .patterns: 10, .lists: 7
```

with:

```swift
.feature: 2, .patterns: 11, .lists: 7
```


In `Tests/CreatorEditorTests/PatternsLibraryTests.swift`, replace:

```swift
            "Cull Pattern", "Cull Index", "Cull by Region", "Random Reduce",
        ])
```

with:

```swift
            "Cull Pattern", "Cull Index", "Cull by Region", "Random Reduce", "Random Values",
        ])
```


- [ ] **Step 2: Run them**

Run: `swift test --filter "RandomValuesNodeTests|OutputNodeTests|PatternsLibraryTests|CatalogTests|BuiltInNodesInspectorTests" 2>&1 | grep -v 'ld: warning'`

Expected: FAIL, the tests do not build (`cannot find 'RandomValuesNode' in scope`).

- [ ] **Step 3: Write the implementation**

Create `Sources/CreatorNodes/Patterns/Variation/RandomValuesNode.swift`:

```swift
import CreatorGraph
import CreatorKernel
import Foundation

/// A random number for every instance (patterns spec §4), reals or whole numbers in a range, in the shape of a tree wired
/// into `shape` or, with nothing wired, a flat list of `count`. Wire `values` into a size (diameters, heights) or `integers`
/// into a count or a Cull Index to vary a pattern. It is always seeded (`SeededRandom`, SplitMix64, purpose `.values`): the same
/// seed gives the same numbers on every machine and in every release, and not the numbers Random Reduce or Jitter draw for it. A number depends on the seed and on where its item is (its branch's
/// ordinal and its index in the branch), never on how many items there are, so more instances or a cull don't change the
/// numbers the others get, and a shape that was culled gets numbers at the paths it kept. A new seed never warns.
///
/// `values` are reals from `min` up to `max`. `integers` are whole numbers from `min` rounded up to `max` rounded down,
/// both ends included; there are none (and the output is left out) when no whole number lies between them.
public enum RandomValuesNode: NodeDefinition {
    public static let typeID = "creator.randomValues"
    public static let displayName = "Random Values"
    public static let category = NodeCategory.patterns
    /// The most numbers made from a count, so a typo gives a message instead of a hang.
    public static let maximumCount = 100_000
    public static let inputs = [
        SocketSpec("shape", .any, access: .tree, optional: true),
        SocketSpec("count", .integer, defaultValue: .integer(8), unit: .count),
        SocketSpec("min", .number, defaultValue: .number(0)),
        SocketSpec("max", .number, defaultValue: .number(1)),
        SocketSpec("seed", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("values", .number), SocketSpec("integers", .integer, optional: true)]
    public static let inspector = [
        InspectorSection(title: "Range", controls: [.number("min"), .number("max")]),
        InspectorSection(title: "Random", controls: [.integer("count"), .integer("seed")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let (low, high) = (try inputs.number("min"), try inputs.number("max"))
        guard low.isFinite, high.isFinite else { throw NodeError.invalidValue("“min” and “max” must be numbers.") }
        guard low <= high else { throw NodeError.invalidValue("“min” can't be more than “max”.") }
        let seed = try inputs.integer("seed")
        let shape = try shape(of: inputs)
        let reals = shape.replacingItems { leaf, ordinal, k in
            let random = SeededRandom(seed: seed, stream: ordinal, purpose: .values)
            return .number(low + random.unit(at: leaf.positions[k]) * (high - low))
        }
        var trees: [SocketName: DataTree] = ["values": reals]
        let (first, last) = (low.rounded(.up), high.rounded(.down))
        if first <= last, abs(first) < 1e15, abs(last) < 1e15 {
            let (lowest, span) = (Int(first), Int(last - first) + 1)
            trees["integers"] = shape.replacingItems { leaf, ordinal, k in
                .integer(lowest + SeededRandom(seed: seed, stream: ordinal, purpose: .values).below(span, at: leaf.positions[k]))
            }
        }
        return NodeOutputs(trees: trees)
    }

    /// The tree to fill: the wired shape, or a flat list of `count` placeholders.
    private static func shape(of inputs: NodeInputs) throws -> DataTree {
        if inputs.has("shape") { return try inputs.tree("shape") }
        let count = try inputs.integer("count")
        guard count >= 0 else { throw NodeError.invalidValue("“count” can't be negative.") }
        guard count <= maximumCount else {
            throw NodeError.invalidValue("Random Values makes at most \(maximumCount.display) numbers.")
        }
        return .list(Array(repeating: .integer(0), count: count))
    }
}
```


In `Sources/CreatorNodes/BuiltInNodes.swift`, replace:

```swift
        OutputNode.self,
    ]
```

with:

```swift
        RandomValuesNode.self,
        OutputNode.self,
    ]
```


- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter "RandomValuesNodeTests|OutputNodeTests|PatternsLibraryTests|CatalogTests|BuiltInNodesInspectorTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

- [ ] **Step 5: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > /tmp/vtest.log 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,794 = master + 155** (+16 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(7a-3b): Random Values, seeded reals and whole numbers in the shape of a tree"
```

---

### Task 9: Jitter

**Files:**

- Create: `Sources/CreatorNodes/Patterns/Variation/JitterNode.swift`
- Create: `Sources/CreatorNodes/Patterns/Variation/PlaneJitter.swift`
- Modify: `Sources/CreatorNodes/BuiltInNodes.swift`
- Test: `Tests/CreatorNodesTests/Variation/JitterNodeTests.swift` (new)
- Test: `Tests/CreatorEditorTests/PatternsLibraryTests.swift` (modify)
- Test: `Tests/CreatorNodesTests/OutputNodeTests.swift` (modify)

**Interfaces:**

- Consumes: Tasks 1 and 2.
- Produces: `PlaneJitter.jittered(_:random:index:distance:turn:) -> Plane`; `JitterNode` (`creator.jitter`; inputs `placements` (plane, tree), `distance` (mm), `turn` (degrees), `seed`; output `placements`).

A random offset in each placement's own plane and a random turn about its normal, within limits (Key decision 5; User decision U8). The first
test pins three placements' moves to numbers worked out from the generator (by a script of its own, for the `Jitter_1` purpose); the property tests check the limits over 200 tilted placements.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorNodesTests/Variation/JitterNodeTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import Foundation
import Testing

/// Jitter (patterns spec §4): a random offset in each placement's own plane and a random turn about its normal, within limits,
/// from a seed. The pinned moves come straight from the generator (SplitMix64, `SeededRandomTests`, purpose `.jitter`): placement
/// `p` of a branch uses draws `3p`, `3p + 1` and `3p + 2` of the stream of its branch's ordinal.
struct JitterNodeTests {
    /// `count` placements in a row 20 mm apart facing `direction`, through Points to Placements, and a Jitter after them.
    struct Fixture {
        var h = Harness()
        let placements: Node
        let jitter: Node

        init(count: Int = 3, direction: Vector3 = .unitZ, rows: Int? = nil, _ settings: [SocketName: ConstantValue] = [:]) {
            let grid = h.add(GridPointsNode.self, ["countX": .integer(count), "countY": .integer(1), "spacingX": .number(20)])
            placements = h.add(PointsToPlacementsNode.self, ["direction": .vector(direction)])
            jitter = h.add(JitterNode.self, settings)
            h.wire(grid, "points", to: placements, "points")
            if let rows {
                let partition = h.add(PartitionNode.self, ["size": .integer(rows)])
                h.wire(placements, "placements", to: partition, "tree")
                h.wire(partition, "tree", to: jitter, "placements")
            } else {
                h.wire(placements, "placements", to: jitter, "placements")
            }
        }

        func planes(_ source: Node, _ socket: SocketName = "placements") async throws -> [Plane] {
            let report = try await h.run([source])
            return try #require(report.value(source, socket)?.planes)
        }
    }

    /// How far `plane` is from `original` along `original`'s own x and y axes, and how many degrees it is turned about its normal.
    func move(_ plane: Plane, from original: Plane) -> (x: Double, y: Double, along: Double, turn: Double) {
        let offset = plane.origin - original.origin
        let turn = atan2(plane.xAxis.dot(original.yAxis), plane.xAxis.dot(original.xAxis)) * 180 / .pi
        return (offset.dot(original.xAxis), offset.dot(original.yAxis), offset.dot(original.normal), turn)
    }

    // MARK: pinned moves

    @Test func seed42MovesThreePlacementsByPinnedAmounts() async throws {
        let f = Fixture(["distance": .number(2), "turn": .number(10), "seed": .integer(42)])
        let before = try await f.planes(f.placements)
        let after = try await f.planes(f.jitter)
        let moves = zip(after, before).map { move($0, from: $1) }
        let expected: [(Double, Double, Double)] = [
            (1.3832763664803966, -0.6613081950817091, 5.572337181192553),
            (1.0336785380656945, -0.029146096083390582, -0.640825595687553),
            (-1.105362466263014, 1.4331253961810904, 7.491161609836691),
        ]
        for (actual, wanted) in zip(moves, expected) {
            #expect(isClose(actual.x, wanted.0, relative: 1e-9) && isClose(actual.y, wanted.1, relative: 1e-9))
            #expect(isClose(actual.turn, wanted.2, relative: 1e-9))
            #expect(isClose(actual.along, 0, relative: 1e-9))
        }
    }

    @Test func anotherBranchDrawsFromItsOwnStream() async throws {
        let f = Fixture(count: 4, rows: 2, ["distance": .number(2), "turn": .number(0), "seed": .integer(42)])
        let report = try await f.h.run([f.jitter])
        let tree = try #require(report.tree(f.jitter, "placements"))
        let first = try #require(tree.leaves[1].items.first)
        guard case .plane(let plane) = first else { throw NodeError.invalidValue("not a plane") }
        let original = try await f.planes(f.placements)[2]
        let stream1 = SeededRandom(seed: 42, stream: 1, purpose: .jitter)
        let radius = 2 * stream1.unit(at: 0).squareRoot()
        #expect(isClose((plane.origin - original.origin).length, radius, relative: 1e-9), "branch 1 uses stream 1")
    }

    // MARK: limits

    @Test func everyMoveStaysInsideItsPlaneAndWithinTheLimits() async throws {
        let f = Fixture(count: 200, direction: Vector3(1, 1, 0), ["distance": .number(3), "turn": .number(25), "seed": .integer(5)])
        let before = try await f.planes(f.placements)
        let after = try await f.planes(f.jitter)
        #expect(after.count == 200)
        for (shaken, original) in zip(after, before) {
            let m = move(shaken, from: original)
            #expect(abs(m.along) < 1e-9, "never out of its plane")
            #expect((m.x * m.x + m.y * m.y).squareRoot() <= 3 + 1e-9)
            #expect(abs(m.turn) <= 25 + 1e-9)
            #expect(isClose(shaken.normal, original.normal))
            #expect(abs(shaken.xAxis.length - 1) < 1e-9 && abs(shaken.xAxis.dot(shaken.normal)) < 1e-9, "still a clean frame")
        }
        let moves = zip(after, before).map { move($0, from: $1) }
        #expect(moves.contains { $0.x > 1 } && moves.contains { $0.x < -1 }, "it moves both ways")
        #expect(moves.contains { $0.turn > 10 } && moves.contains { $0.turn < -10 }, "it turns both ways")
    }

    @Test func noDistanceAndNoTurnLeaveTheSamePlacements() async throws {
        let f = Fixture(["distance": .number(0), "turn": .number(0), "seed": .integer(9)])
        let before = try await f.planes(f.placements)
        let after = try await f.planes(f.jitter)
        for (a, b) in zip(after, before) {
            #expect(isClose(a.origin, b.origin) && isClose(a.xAxis, b.xAxis) && isClose(a.normal, b.normal))
        }
    }

    @Test func onlyTheTurnOrOnlyTheDistanceCanBeUsed() async throws {
        let turnOnly = Fixture(["distance": .number(0), "turn": .number(30), "seed": .integer(1)])
        let before = try await turnOnly.planes(turnOnly.placements)
        let turned = try await turnOnly.planes(turnOnly.jitter)
        #expect(zip(turned, before).allSatisfy { isClose($0.origin, $1.origin) })
        #expect(zip(turned, before).contains { abs(move($0, from: $1).turn) > 1 })
        let moveOnly = Fixture(["distance": .number(2), "turn": .number(0), "seed": .integer(1)])
        let moved = try await moveOnly.planes(moveOnly.jitter)
        #expect(zip(moved, before).allSatisfy { isClose($0.xAxis, $1.xAxis) })
    }

    // MARK: seeds

    @Test func theSameSeedGivesTheSamePlacementsEveryTime() async throws {
        let first = Fixture(count: 30, ["seed": .integer(77)])
        let second = Fixture(count: 30, ["seed": .integer(77)])
        #expect(try await first.planes(first.jitter) == second.planes(second.jitter))
    }

    @Test func anotherSeedMovesThemElsewhereAndNeverWarns() async throws {
        let first = Fixture(["seed": .integer(1)])
        let second = Fixture(["seed": .integer(2)])
        #expect(try await first.planes(first.jitter) != second.planes(second.jitter))
        let report = try await second.h.run([second.jitter])
        #expect(report.isOK(second.jitter))
    }

    @Test func addingPlacementsDoesNotMoveTheEarlierOnes() async throws {
        let few = Fixture(count: 3, ["seed": .integer(8)])
        let many = Fixture(count: 6, ["seed": .integer(8)])
        // The grid is centred, so the rows start in different places; what must match is how far each placement moved.
        let fewMoves = zip(try await few.planes(few.jitter), try await few.planes(few.placements)).map { move($0, from: $1) }
        let manyMoves = zip(try await many.planes(many.jitter), try await many.planes(many.placements)).map { move($0, from: $1) }
        for (a, b) in zip(fewMoves, manyMoves.prefix(3)) {
            #expect(isClose(a.x, b.x) && isClose(a.y, b.y) && isClose(a.turn, b.turn))
        }
    }

    // MARK: shape

    @Test func aCulledInputStaysCulledAndTheSurvivorsMoveAsTheyWouldHave() async throws {
        let plain = Fixture(count: 3, ["seed": .integer(42)])
        let everyone = try await plain.planes(plain.jitter)
        var h = plain.h
        let cull = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])
        let jitter = h.add(JitterNode.self, ["seed": .integer(42)])
        h.wire(plain.placements, "placements", to: cull, "tree")
        h.wire(cull, "tree", to: jitter, "placements")
        let report = try await h.run([jitter])
        #expect(report.positions(jitter, "placements") == [[0, 2]])
        let survivors = try #require(report.value(jitter, "placements")?.planes)
        #expect(survivors == [everyone[0], everyone[2]], "the draws follow the indices, not the order")
    }

    @Test func aTreeKeepsItsBranches() async throws {
        let f = Fixture(count: 6, rows: 3)
        let report = try await f.h.run([f.jitter])
        #expect(report.tree(f.jitter, "placements")?.leaves.map(\.items.count) == [3, 3])
    }

    // MARK: use

    @Test func jitteredPlacementsPlaceCopiesWhereTheyAre() async throws {
        var f = Fixture(count: 2, ["distance": .number(2), "turn": .number(0), "seed": .integer(3)])
        let tool = f.h.box(4, 4, 4)
        let place = f.h.add(PlaceNode.self)
        f.h.wire(tool, "solid", to: place, "tool")
        f.h.wire(f.jitter, "placements", to: place, "placements")
        let report = try await f.h.run([place])
        let copies = try #require(report.value(place, "solids")?.solids)
        let planes = try await f.planes(f.jitter)
        #expect(copies.count == 2)
        for (copy, plane) in zip(copies, planes) {
            let centre = (copy.bounds.min + copy.bounds.max) * 0.5
            #expect(isClose(centre.x, plane.origin.x) && isClose(centre.y, plane.origin.y))
        }
    }

    // MARK: refusals

    @Test func badLimitsAreRefusedInPlainWords() async throws {
        let distance = Fixture(["distance": .number(-1)])
        #expect(try await distance.h.run([distance.jitter]).error(distance.jitter) == "“distance” can't be negative.")
        let turn = Fixture(["turn": .number(-1)])
        #expect(try await turn.h.run([turn.jitter]).error(turn.jitter) == "“turn” can't be negative.")
    }
}
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
        #expect(BuiltInNodes.all.count == 46)
```

with:

```swift
        #expect(BuiltInNodes.all.count == 47)
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
.feature: 2, .patterns: 11, .lists: 7
```

with:

```swift
.feature: 2, .patterns: 12, .lists: 7
```


In `Tests/CreatorEditorTests/PatternsLibraryTests.swift`, replace:

```swift
            "Cull Pattern", "Cull Index", "Cull by Region", "Random Reduce", "Random Values",
        ])
```

with:

```swift
            "Cull Pattern", "Cull Index", "Cull by Region", "Random Reduce", "Random Values", "Jitter",
        ])
```


- [ ] **Step 2: Run them**

Run: `swift test --filter "JitterNodeTests|OutputNodeTests|PatternsLibraryTests|CatalogTests|BuiltInNodesInspectorTests" 2>&1 | grep -v 'ld: warning'`

Expected: FAIL, the tests do not build (`cannot find 'JitterNode' in scope`).

- [ ] **Step 3: Write the implementation**

Create `Sources/CreatorNodes/Patterns/Variation/JitterNode.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Shakes placements a little (patterns spec §4): each one moves a random distance in its own plane, up to `distance`, and
/// turns a random angle about its own normal, up to `turn` either way. Wire the result into Place or a shortcut for a pattern
/// that looks hand-placed. It is always seeded (`SeededRandom`, SplitMix64, purpose `.jitter`, `PlaneJitter`): the same seed gives the same
/// placements on every machine and in every release, a placement's move depends on the seed and its place alone (so more
/// placements, or a cull, don't move the others), and a new seed never warns. Culling keeps paths: a culled input stays
/// culled, with the same indices.
public enum JitterNode: NodeDefinition {
    public static let typeID = "creator.jitter"
    public static let displayName = "Jitter"
    public static let category = NodeCategory.patterns
    public static let inputs = [
        SocketSpec("placements", .plane, access: .tree),
        SocketSpec("distance", .number, defaultValue: .number(1), unit: .millimetres, range: 0...50),
        SocketSpec("turn", .number, defaultValue: .number(5), unit: .degrees, range: 0...180),
        SocketSpec("seed", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static let inspector = [
        InspectorSection(title: "Jitter", controls: [.slider("distance"), .slider("turn"), .integer("seed")]),
    ]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let tree = try inputs.tree("placements")
        guard tree.items.allSatisfy({ $0.type == .plane }) else { throw NodeError.typeMismatch("placements", expected: .plane) }
        let (distance, turn) = (try inputs.number("distance"), try inputs.number("turn"))
        guard distance.isFinite, distance >= 0 else { throw NodeError.invalidValue("“distance” can't be negative.") }
        guard turn.isFinite, turn >= 0 else { throw NodeError.invalidValue("“turn” can't be negative.") }
        let seed = try inputs.integer("seed")
        let shaken = tree.replacingItems { leaf, ordinal, k in
            guard case .plane(let plane) = leaf.items[k] else { return leaf.items[k] }
            let random = SeededRandom(seed: seed, stream: ordinal, purpose: .jitter)
            return .plane(PlaneJitter.jittered(plane, random: random, index: leaf.positions[k], distance: distance, turn: turn))
        }
        return NodeOutputs(trees: ["placements": shaken])
    }
}
```


Create `Sources/CreatorNodes/Patterns/Variation/PlaneJitter.swift`:

```swift
import CreatorGeometry
import Foundation

/// One placement nudged at random inside its own plane and turned about its own normal (patterns spec §4).
///
/// Three draws of the item's stream make the move: draw `3p` picks the distance, `3p + 1` the direction and `3p + 2` the turn,
/// `p` being the item's index in its branch. The offset is a point in a disc of radius `distance` (the distance is the
/// square root of the first draw times the limit, so the points spread evenly over the disc rather than crowding its middle);
/// the turn is anywhere from −`turn` to `turn`. The offset goes along the plane's own axes, before the turn.
enum PlaneJitter {
    static func jittered(_ plane: Plane, random: SeededRandom, index: Int, distance: Double, turn: Double) -> Plane {
        let radius = distance * random.unit(at: 3 * index).squareRoot()
        let direction = 2 * Double.pi * random.unit(at: 3 * index + 1)
        let angle = (2 * random.unit(at: 3 * index + 2) - 1) * turn * Double.pi / 180
        let (x, y) = (plane.xAxis, plane.yAxis)
        let origin = plane.origin + x * (radius * cos(direction)) + y * (radius * sin(direction))
        return Plane(origin: origin, normal: plane.normal, xAxis: x * cos(angle) + y * sin(angle))
    }
}
```


In `Sources/CreatorNodes/BuiltInNodes.swift`, replace:

```swift
        OutputNode.self,
    ]
```

with:

```swift
        JitterNode.self,
        OutputNode.self,
    ]
```


- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter "JitterNodeTests|OutputNodeTests|PatternsLibraryTests|CatalogTests|BuiltInNodesInspectorTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

- [ ] **Step 5: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > /tmp/vtest.log 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,806 = master + 167** (+12 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(7a-3b): Jitter, seeded offsets and turns for placements"
```

---

### Task 10: The pipeline test and the records

**Files:**

- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/roadmap.md`
- Modify: `docs/superpowers/specs/2026-10-10-patterns-trees-design.md`
- Modify: `docs/verification/human-checks.md`
- Test: `Tests/CreatorNodesTests/Variation/VariationPipelineTests.swift` (new)

**Interfaces:**

- Consumes: Tasks 1–9; `PatternPlate`, `OCCTKernel`.
- Produces: Nothing the code depends on.

One integration test of the six nodes together on a real plate on OCCT (a region cull, a random drop, Jitter, and a Hole Pattern whose diameters are
Random Values in the shape of what is left): the volume equals the plate minus the holes the random choices made, each hole is named by the index
its placement had, the same seed gives the same part and another gives another without a warning. It passes as soon as it is written (it exercises
Tasks 1–9), so there is no red step. Then the records: CLAUDE.md, roadmap, the spec's Errata and the human checks (group VA). No benchmark is run or
added.

- [ ] **Step 1: Write the test**

Create `Tests/CreatorNodesTests/Variation/VariationPipelineTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Foundation
import Testing

/// The variation nodes working together on a real plate (patterns spec §4): 4 × 3 placements, those within 12 mm of the middle
/// culled by region, three more dropped at random, the rest jittered, and a Hole Pattern whose diameters are random numbers in
/// the shape of what is left. Every number comes from the seed, so the same graph gives the same part.
struct VariationPipelineTests {
    struct Pipeline {
        var plate = PatternPlate(columns: 4, rows: 3, spacingX: 15, spacingY: 15)
        let region: Node, reduce: Node, jitter: Node, diameters: Node, holes: Node

        init(seed: Int) {
            let origin = plate.h.add(VectorNode.self)
            region = plate.h.add(CullByRegionNode.self, ["reference": .integer(1), "keep": .integer(1), "distance": .number(12)])
            reduce = plate.h.add(RandomReduceNode.self, ["count": .integer(3), "scope": .integer(1), "seed": .integer(seed)])
            jitter = plate.h.add(JitterNode.self, ["distance": .number(1), "turn": .number(30), "seed": .integer(seed)])
            diameters = plate.h.add(RandomValuesNode.self, ["min": .number(4), "max": .number(6), "seed": .integer(seed)])
            holes = plate.h.add(HolePatternNode.self, ["depth": .number(6)])
            plate.h.wire(origin, "vector", to: region, "point")
            plate.h.wire(plate.placements, "placements", to: region, "placements")
            plate.h.wire(region, "placements", to: reduce, "tree")
            plate.h.wire(reduce, "tree", to: jitter, "placements")
            plate.h.wire(jitter, "placements", to: diameters, "shape")
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            plate.h.wire(jitter, "placements", to: holes, "placements")
            plate.h.wire(diameters, "values", to: holes, "diameter")
        }
    }

    @Test func theGraphMakesTheHolesItsRandomChoicesSay() async throws {
        let kernel = OCCTKernel()
        let p = Pipeline(seed: 5)
        let report = try await p.plate.h.run([p.holes], kernel: kernel)
        for node in [p.region, p.reduce, p.jitter, p.diameters, p.holes] {
            #expect(report.isOK(node), "\(node.name): \(String(describing: report.state(node)))")
        }
        let survivors = try #require(report.positions(p.jitter, "placements")?.first)
        #expect(survivors.count == 7, "12 placements, 2 culled by region, 3 dropped at random")
        #expect(Set(survivors).isDisjoint(with: [5, 6]), "the two beside the middle (x = ±7.5, y = 0) are gone first")
        let solid = try onlySolid(report, p.holes)
        let items = Set(solid.topology.faces.flatMap(\.tags).filter(\.node.isInstanceQualified).map(\.item))
        #expect(items == Set(survivors), "each hole is named by the index its placement had")
        let widths = try #require(report.value(p.diameters, "values")?.numbers)
        let removed = widths.reduce(0) { $0 + Double.pi * $1 * $1 / 4 * 6 }
        #expect(isClose(try await volume(solid, kernel), PatternPlate.plateVolume - removed, relative: 1e-4))
    }

    @Test func theSameSeedMakesTheSamePartAndAnotherSeedAnotherOneWithoutAWarning() async throws {
        let kernel = OCCTKernel()
        let first = Pipeline(seed: 5), again = Pipeline(seed: 5), other = Pipeline(seed: 6)
        let a = try onlySolid(try await first.plate.h.run([first.holes], kernel: kernel), first.holes)
        let b = try onlySolid(try await again.plate.h.run([again.holes], kernel: kernel), again.holes)
        let otherReport = try await other.plate.h.run([other.holes], kernel: kernel)
        let c = try onlySolid(otherReport, other.holes)
        #expect(isClose(try await volume(a, kernel), try await volume(b, kernel), relative: 1e-12))
        #expect(!isClose(try await volume(a, kernel), try await volume(c, kernel), relative: 1e-9))
        #expect(otherReport.isOK(other.holes) && otherReport.isOK(other.reduce) && otherReport.isOK(other.jitter))
    }

    /// With every random node on the default seed 0, Random Reduce and Random Values must not draw the same numbers at the same place
    /// (User decision U7): unsalted, the three items dropped here would be exactly the three smallest random values.
    @Test func withTheSameSeedTheItemsRandomReduceDropsAreNotTheSmallestRandomValues() async throws {
        var h = Harness()
        let source = h.source(count: 12)
        let reduce = h.add(RandomReduceNode.self, ["count": .integer(3), "seed": .integer(0)])
        let values = h.add(RandomValuesNode.self, ["count": .integer(12), "seed": .integer(0)])
        h.wire(source, to: reduce, "tree")
        let report = try await h.run([reduce, values])
        let dropped = Set(0..<12).subtracting(try #require(report.positions(reduce)?.first))
        let numbers = try #require(report.value(values, "values")?.numbers)
        let smallest = Set(numbers.indices.sorted { numbers[$0] < numbers[$1] }.prefix(3))
        #expect(dropped == [0, 4, 8] && smallest == [5, 8, 11], "pinned; unsalted both were {2, 4, 6}")
        #expect(dropped != smallest)
    }
}
```


- [ ] **Step 2: Run them (they pass at once)**

Run: `swift test --filter "VariationPipelineTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS. This test exercises the code of Tasks 1–9, so there is no red step.

- [ ] **Step 3: Write the records**

Add the following. Keep any text another track has put in the same places (see Merge order).

In `CLAUDE.md`, replace:

```markdown
`depth` (1 is a flat list, which is why `Value(_ tree:)` makes a `.list` of it)
```

with:

```markdown
`depth` (1 is a flat list, which is why `Value(_ tree:)` makes a `.list` of it, except a culled list, below)
```

In `CLAUDE.md`, directly after:

```markdown
§6, §7) code is done; its human checks (group PA) are pending and its benchmark numbers (`PatternBench`) await an idle run.
```

add:

```markdown

Patterns, sub-project 7a-3 part B (variation and culling: Cull Pattern, Cull Index, Cull by Region, Random Reduce, Random Values and
Jitter; plan `docs/superpowers/plans/2026-10-12-7a-variation.md`, spec `2026-10-10-patterns-trees-design.md` §4) code is done; its human
checks (group VA) are pending. The layouts, previews and acceptance test are part A (7a-layouts).
```


In `CLAUDE.md`, directly after:

```markdown
    nodes' sockets only. Iteration `item` numbers (the tag's item) are flat, row by row.
```

add:

```markdown
    Culling keeps paths (patterns spec §4): a flat list or branch that has had items taken out holds the survivors at the indices
    they had (`DataTree.culledList(_:at:)`, `isCulled`, `itemPositions`; `DataTree.keepingItems(where:)` and
    `replacingItems(_:)` are how nodes cull and refill), and since a `.list` cannot say that it is a `Value.tree` of depth 1 (`Value(_:)`
    makes any other flat tree a `.list`). It broadcasts as a list: an item socket pairs by place and drops the gaps, a `list` socket
    gets the items and their indices through `NodeInputs.positions(_:)`, a `tree` socket gets the tree whole. Reshaping nodes
    (Flatten, Graft, Partition, Path Mapper) renumber, as reshaping does, and List Item, Branch by Path and Tree Statistics
    count a culled list's survivors by rank; Cull Index alone names the places items had.
```


In `CLAUDE.md`, replace:

```markdown
- `CreatorNodes`: the 41 built-in node definitions (`BuiltInNodes.registry`: the slice's 26, Plane from Face and Sketch, the six
  `Patterns` nodes below,
```

with:

```markdown
- `CreatorNodes`: the 47 built-in node definitions (`BuiltInNodes.registry`: the slice's 26, Plane from Face and Sketch, the twelve
  `Patterns` nodes below,
```


In `CLAUDE.md`, replace:

```markdown
pathRule, branchPath, itemPath, and `projection(reference)` per projected edge)
```

with:

```markdown
pathRule, branchPath, itemPath, cullPattern, cullIndices, and `projection(reference)` per projected edge)
```


In `CLAUDE.md`, directly after:

```markdown
    outside it keeps instance picks stored in the definition from matching.
```

add:

```markdown
  - Variation (`Sources/CreatorNodes/Patterns/Variation`, category `Patterns`; patterns spec §4): Cull Pattern (a text mask `1 0 1`
    or a wired `keep` list, repeated along each branch over the items it has now), Cull Index (indices and `{0;3}` paths as text, or
    wired numbers; an index or path names the place an item had before any cull), Cull by Region (placements inside or outside a
    profile, within or beyond a distance of a point, an edge set's straight and circular edges, or flat faces' planes;
    `RegionDistance`, `Profile2D.contains`), Random Reduce (`RandomReduction`), Random Values (reals and `integers`, in the shape of
    a tree or a count) and Jitter (`PlaneJitter`). Each takes a tree whole (`tree` access) and returns the same nesting with a
    culled list where items went. **All randomness is `SeededRandom`: SplitMix64, written out in the repo and pinned by
    `SeededRandomTests`, never the system's generator.** A draw depends on the seed, the item's branch ordinal (the stream) and its
    index in the branch, never on how many items there are, so a cull or a longer list reshuffles nothing; a seed never warns.
    Each node draws for its own `SeededRandom.Purpose` (the seed is mixed with a fixed per-node constant), so equal seeds on
    different nodes give unrelated numbers; the constants are pinned like the algorithm. Points to Placements passes a culled
    list of points on as culled placements (inside a tree run it renumbers a culled branch and warns), so a cull may sit before
    or after it. Place and the shortcuts read culled placements (`PlacementSet`): the instances are exactly the surviving indices, each copy's
    tags carry that index (`PlacementMoves.copies` renumbers what `Kernel.place` numbered 0, 1, 2…, `Topology.renumberingInstance`)
    and sizes and tools are read by the index (`PerInstance` with `positions`; a culled size list never sets the number of
    instances, `PerInstance.span`), so a pick on one instance survives a cull of another and a pick on a culled one warns naming
    its path.
```


In `docs/superpowers/roadmap.md`, replace:

```markdown
next 7a-3 (layouts, culling, random, Jitter, previews, the acceptance test, tree paths in picks) |
```

with:

```markdown
7a-3 part B (culling, random and Jitter: plan `2026-10-12-7a-variation.md`) code done, human checks VA pending; next 7a-3 part A (layouts, previews, the acceptance test, tree paths in picks) |
```


In `docs/superpowers/specs/2026-10-10-patterns-trees-design.md`, replace:

```markdown
`Value.tree` holds depth 2 or more; a depth-1 tree is always a `.list`.
```

with:

```markdown
`Value.tree` holds depth 2 or more; a depth-1 tree is a `.list`, except a culled list (Errata 7a-3 part B).
```


In `docs/superpowers/specs/2026-10-10-patterns-trees-design.md`, directly after:

```markdown
  instance with no warning, and undo restores it in the same step. Still open: a Place inside a group whose tool is made
  outside it doesn't match picks stored in the definition.
```

add:

```markdown


## Errata (7a-3 part B: variation and culling)

Plan `2026-10-12-7a-variation.md`. Where the build settled what §4 left open:

- **§4 Culling keeps paths: a culled list.** `Value.tree` could hold a gap only as an empty branch. A cull leaves gaps inside a
  branch, so a `DataTree` of depth 1 may now carry the indices its items keep (`culledList(_:at:)`, `isCulled`), and such a
  list is a `Value.tree` of depth 1 (`Value(_:)` makes every other flat tree a `.list`). A list that has been culled stays
  culled even when its indices are 0, 1, 2…, because what was taken off its end must not come back. It broadcasts as a list:
  an item socket pairs by place and so drops the gaps, a `list` socket gets the items and `NodeInputs.positions(_:)`, a `tree`
  socket the whole tree. The reshaping nodes (Flatten, Graft, Partition, Path Mapper) renumber, as reshaping does, and List Item,
  Branch by Path and Tree Statistics count a culled list's survivors by rank (List Item 2 of a list culled to {0, 2, 4} is the
  item at {4}); only Cull Index names the places items had. The tooltip and Data section say "culled" ("3, culled"). This
  amends the 7a-1 entry above: a depth-1 tree is a `.list` unless it is culled.
- **§4 Cull Pattern.** The mask is the saved text `cullPattern` (`1 0 1`, `T F T`, commas allowed; 1 or T keeps, 0 or F culls;
  default `1 0`), or a list of booleans wired into `keep`, which takes its place. It starts again at each branch and counts the
  items the branch has now, so a second Cull Pattern works on what is left.
- **§4 Cull Index.** The saved text `cullIndices` holds indices (`3`: that place in every branch) and paths (`{0;3}`: one item;
  `{1}`: the whole second branch, which stays as an empty branch); numbers wired into `indices` add to them. An index or path
  names the place an item had before any cull. `{}` (the whole tree) refuses, pointing at Cull Pattern `0`. A path with more
  indices than the tree has levels refuses naming the shape;
  a path that names nothing warns once ("{0;9} names nothing in this tree."); an index past the end is not a problem.
- **§4 Cull by Region.** `reference` (Profile, Point, Edges, Face) says which of `profile`, `point`, `edges` or `faces` is
  measured from, `keep` (Inside or within, Outside or beyond) says which side stays, and `distance` is the limit for the other
  three. A placement is judged by its origin. A profile is a prism along its plane's normal; a point exactly on the outline or at
  exactly the distance counts as inside. Edges are measured exactly when straight or circular (another curve refuses, with the
  count); faces are measured to their **plane**, not their outline (a placement far beside a small flat face counts as near it),
  and a curved face refuses, with the count.
- **§4 Random Reduce.** `by` (Count, Fraction), `count`, `fraction`, `scope` (Per branch, Overall) and `seed`. Each item's key is the
  generator's draw at its index in the stream of its branch's ordinal, and the smallest keys go: a bigger amount drops what a
  smaller one did and more, and adding items to the end changes nothing earlier. A fraction rounds to the nearest item, halves up.
- **§4 Random Values.** `shape` (any tree), else a flat list of `count` (at most 100,000); `min`, `max`, `seed`. `values` are reals
  from `min` up to `max`; `integers` are whole numbers from `min` rounded up to `max` rounded down, both included, and the output is
  left out when there are none. A number depends on the seed, the branch ordinal and the index in the branch only.
- **§4 Jitter.** `distance` (a point in a disc of that radius in the placement's own plane, spread evenly over it), `turn` (degrees,
  either way, about the placement's normal) and `seed`. Draw `3p`, `3p + 1`, `3p + 2` of the branch's stream move placement `p`.
- **§4 The generator.** SplitMix64 (`SeededRandom`): the state starts at the seed (a negative seed is its two's complement) and
  each draw adds 0x9E3779B97F4A7C15 and scrambles. Each random node mixes a constant of its own into the seed first
  (`mix(seed ^ salt)`; the salt is the node's name in ASCII ending `_1`: `Reduce_1`, `Values_1`, `Jitter_1`), so two nodes given
  the same seed, the default 0 included, draw unrelated numbers; the bare generator keeps the published sequence. Stream `n`
  starts at `mix(start + n × step)`, `start` being the mixed seed. A real is the top 53 bits over 2⁵³;
  a whole number below `b` is the high word of the draw times `b`. The sequence for seed 0 is the published one, and the first
  draws of other seeds and of each node's purpose are pinned in `SeededRandomTests`; changing the algorithm or a salt changes every
  saved file's random results.
- **§6 Culled instances keep their index.** Place and the shortcuts make exactly the instances a culled placement list holds (a
  longer size list adds none), tag each copy with the index its placement had (`PlacementSet`, `PlacementMoves.copies`), and read
  sizes and tools by that index (`PerInstance`: a culled size list gives instance `i` its value at `i`, else the nearest one before
  it, else its first). A pick on `{4}` therefore survives a cull of `{1}`, and a pick on a culled instance warns naming its path.
  Place outputs the copies of culled placements as a culled list too. A culled size or tool list never adds instances, however many
  survivors it holds, and one with everything culled makes none.
- **§3, §4 Points to Placements and a cull.** A culled list of points makes a culled list of placements at the same indices, so a
  cull of the Grid Points and a cull of the placements number the instances alike; a direction list is read by that index. Inside a
  tree run (a culled branch of a deeper tree) the node returns one plain list per branch, renumbered from 0, and warns that
  culling after it keeps the paths.
```


In `docs/verification/human-checks.md`, directly after:

```markdown
  `aMissingBranchOrItemInAPathSaysHowManyThereAre`, `aMissingBranchSaysHowManyThereAre`. **Observed:**
```

add:

```markdown


## Group VA — variation and culling (7a-3 part B)

**Status: NOT RUN.** Plan `2026-10-12-7a-variation.md`, spec `2026-10-10-patterns-trees-design.md` §4 and §6. Run
`swift run MetalCreatorApp`. The tests pin the nodes, the generator and the naming; these check what a real window shows. Build a
plate (Rectangle 60 × 40 on a plane at z = −6, Extrude 6) and a Grid Points (4 × 3, 15 mm) into Points to Placements into a Hole
Pattern (Ø5, depth 6) into an Output; then put the nodes below between Points to Placements and the Hole Pattern.

- [ ] **VA-1 The library.** The "Patterns" section ends with Cull Pattern, Cull Index, Cull by Region, Random Reduce, Random Values and
  Jitter after Pattern Feature (or after the layouts, if 7a-layouts has merged). Typing "cull" in the add-node palette finds three.
  Pinned: `thePatternsSectionHoldsThePatternNodes`. **Observed:**
- [ ] **VA-2 Cull Pattern.** The Pattern row shows `1 0` in a text field: every other hole is gone. Type `1 1 0` and press Return: every
  third is gone. Type `1 2`: the badge reads "“1 2” isn't a pattern. Use 1 to keep an item and 0 to cull it, like 1 0 1." The
  Edit menu names each change. A long pattern scrolls inside the field. Pinned: `CullPatternNodeTests`. **Observed:**
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
  re-rolls them without a badge. Selecting Jitter shows no preview triads yet; they arrive with 7a-layouts, so record that nothing shows.
  Pinned: `JitterNodeTests`. **Observed:**
- [ ] **VA-10 The same file twice.** Save the graph, quit, reopen it: the holes are exactly where they were (the seed is saved, nothing
  else is random). On a second machine, if there is one, the same file gives the same part. Pinned: `SeededRandomTests`.
  **Observed:**
- [ ] **VA-11 Undo.** Undoing a pattern or a path edit puts the previous mask back and the holes with it; the Edit menu names the step.
  **Observed:**
- [ ] **VA-12 A cull before Points to Placements.** Move the Cull Index to sit between Grid Points and Points to Placements (wire Grid
  Points into it and it into Points to Placements) and type `0`: the first point's hole is gone and the others stay where they are,
  exactly as when the cull came after Points to Placements. Fillet the rim of the fifth hole (index 4): it stays on that hole when you
  change the cull to `1`, and with the cull changed to `4` the badge reads "Instance {4} no longer exists, so the edge picked on it
  isn't selected." Pinned: `CulledPickTests` (both stages), `pointsToPlacementsKeepsACulledListsIndices`. **Observed:**
- [ ] **VA-13 Equal seeds.** Random Reduce (Count 3, Seed 0) and Random Values (Seed 0, wired into the Hole Pattern's `diameter`): the
  holes Random Reduce drops are not simply the smallest ones. Pinned: `withTheSameSeedTheItemsRandomReduceDropsAreNotTheSmallestRandomValues`.
  **Observed:**
```


- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter "VariationPipelineTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

- [ ] **Step 5: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > /tmp/vtest.log 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' /tmp/vtest.log | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,809 = master + 170** (+3 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "docs(7a-3b): variation pipeline test, CLAUDE.md, roadmap, spec Errata and human checks VA"
```

---

## Self-review

**Spec coverage (§4, §6, §8, §9).**
- Cull Pattern: Task 4. Cull Index (indices and paths such as `{0;3}`): Task 5. Cull by Region (profile inside/outside; point, edge set, face within/beyond): Task 6. Random Reduce (N or fraction, per branch or overall): Task 7. Random Values (integers or reals in a range, in the shape of a tree or a count): Task 8. Jitter (offset in the placement's plane, turn about its normal, within limits): Task 9. All in the Patterns category and tree-aware (`access: .tree`).
- Culling keeps paths, including item gaps inside a branch: Tasks 2 (representation) and 3 (instances and tags, and Points to Placements passing a cull through), pinned per node in Tasks 4–9.
- Randomness seeded by a `seed` input, a fixed documented repo algorithm, pinned values, never the system generator, seed change never warns: Task 1 (generator, one purpose per random node, and their pins), Tasks 7–9 (`report.isOK` after a seed change; pinned results per branch and overall), Task 10 (same seed, same part; equal seeds on different nodes decorrelated).
- Naming (§6, §9): a pick on an instance survives a cull of another and a pick on a culled instance warns naming its path: Task 5 (`CulledPickTests`, flat branch, `{i}` = item index, valid unchanged after 7a-layouts); the tags themselves: Task 3.
- Errors (§8): path shapes named (Task 5), refused values name their socket (Tasks 4–9), unmatched paths named (Task 5), no warning for a seed.
- Layout nodes, previews, lifting the tree refusal, tree-path picks and the acceptance test are out of scope (7a-layouts); no benchmark is run or added.

**Placeholder scan.** Every code block was applied, task by task, to a scratch copy of master (`9e5d2d5`) and built, tested and linted; the plan text is generated from those same files, so there is no pseudo-code and no "similar to Task N". The steps name the files; the code is in the plan.

**Type consistency.** `culledList(_:at:)`, `isCulled`, `itemPositions`, `culledPositions`, `Leaf.positions`, `keepingItems(where:)`, `replacingItems(_:)` (Task 2) are the names Tasks 3–9 call; `PlacementSet.instances(alongside:)`, `planes(for:)`, `PlacementMoves.copies(of:at:instances:placedBy:kernel:tag:)`, `PerInstance(_:positions:)`, `NodeInputs.perInstance*` (Task 3) are used by every shortcut as written; `SeededRandom.value(at:)/unit(at:)/below(_:at:)` (Task 1) by Tasks 7–9; `NodeSetting.cullPattern/cullIndices` by their nodes and the tests.

**Review Focus.** Each of the seven has its test in the task named in the list at the top; none is left uncovered.

**Verification record.** The plan was revised after a review that replayed it on master `9e5d2d5`. The revision was re-verified by applying every
edit of Tasks 1–10 in order to a scratch copy of master (a sibling `MetalUI` symlink), then `swift build --build-tests` (no new warnings beyond
master's `ContextMenuTests.swift:140`), a full `swift test` (exit 0, 0 lines saying "recorded an issue" or "failed after", 11 "Test run with" lines,
2,809 tests = 231 + 73 + 187 + 197 + 149 + 499 + 141 + 415 + 48 + 591 + 278) and `swiftlint lint --strict` (0 violations). Every pinned random
value was recomputed with a separate implementation of SplitMix64 and the purpose salts, never by running the nodes. The tests-only (RED) state
of each task does not build, as each task's Step 2 says (the symbols are missing); the earlier replay measured those error counts and the
revision did not change which symbols are missing. Per-task new tests and running totals:

| Task | What | New tests | Total |
|---|---|---|---|
| 1 | SeededRandom, the one generator, one purpose per random node | +11 | 2,650 (master + 11) |
| 2 | Culled lists in trees (paths kept through a cull) | +20 | 2,670 (master + 31) |
| 3 | Surviving instances keep their index (and Points to Placements passes a cull on) | +29 | 2,699 (master + 60) |
| 4 | Cull Pattern | +13 | 2,712 (master + 73) |
| 5 | Cull Index, and the naming test (spec §9), the cull on both sides of Points to Placements | +24 | 2,736 (master + 97) |
| 6 | Cull by Region | +28 | 2,764 (master + 125) |
| 7 | Random Reduce | +14 | 2,778 (master + 139) |
| 8 | Random Values | +16 | 2,794 (master + 155) |
| 9 | Jitter | +12 | 2,806 (master + 167) |
| 10 | The pipeline test and the records | +3 | 2,809 (master + 170) |

Every task: `swift build --build-tests` with no new warnings (master's `ContextMenuTests.swift:140` aside), full `swift test` exit 0 with no "recorded an issue" or "failed after" line and 11 "Test run with" lines, `swiftlint lint --strict` with 0 violations.
