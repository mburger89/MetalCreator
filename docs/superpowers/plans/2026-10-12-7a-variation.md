# Variation and Culling (7a-3 part B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Six tree-aware nodes in the Patterns category (Cull Pattern, Cull Index, Cull by Region, Random Reduce, Random Values, Jitter) whose culls keep paths, whose randomness is one fixed, documented, seeded generator, and whose survivors keep their original tree path (`{3}`, `{1;2}`) in Place's and the shortcuts' instance tags, so a pick on one instance survives a cull of another and a pick on a culled instance warns naming its path.

**Architecture:** A cull cannot renumber, so a flat list or branch gains the one thing it lacked, item-level gaps: a `DataTree` of depth 1 may carry the indices its items keep (a "culled list", a `Value.tree` of depth 1), which broadcasts as a list everywhere and arrives whole on a `tree` socket. 7a-3 part A already names an instance by its tree path and reads placements, sizes and tools whole through `InstanceGrid`; this plan teaches that one rule to make exactly the instances a culled list or branch holds, at the index each item kept (so the packed path in the copy's tags is the item's original path), to read every other input at that index, and to give the copies back with the same gaps. Points to Placements takes its `points` as a whole tree and returns placements at the same paths, so a cull anywhere before it keeps them. The six nodes take a tree whole (`tree` access) and return the same nesting; all randomness is `SeededRandom`, SplitMix64 written out in the repo, drawn by an item's place (branch ordinal and index), never by how many items there are.

**Tech Stack:** Swift 6.4 strict concurrency, Swift Testing, `FakeKernel` and `OCCTKernel` in tests, `swiftlint lint --strict`. No third-party code. No MetalUI change, no new MetalUI gap.

**Spec:** `docs/superpowers/specs/2026-10-10-patterns-trees-design.md` §4 (culling and randomness), §6 (naming), §8 (errors), §9 (testing) and its Errata for 7a-1 and 7a-2, under `docs/superpowers/specs/2026-10-07-metalcreator-vertical-slice-design.md` with all its Errata; the merged plans `docs/superpowers/plans/2026-10-10-7a-trees.md`, `2026-10-10-7a-place.md` and `2026-10-12-7a-layouts.md` (its Tasks 1 to 8 are in this branch's base: `InstancePath`, `InstanceGrid`, Place and the shortcuts over trees, picks by tree path, the Linear, Grid, Circular and Curve Patterns). Executors read the spec's §4 and §6 first. This plan adds an Errata section to the spec in Task 10.

**Base:** branch `7a-variation` off master `6dda4d6` (2741 tests; the merge of 7a-layouts Tasks 1 to 8). Face Pattern, the layout previews, Pattern on Face, the acceptance test and the layouts' documentation (7a-layouts Tasks 9 to 14) are built in parallel on `7a-layouts` and merge **before** this track; none is needed here. Never run the release benchmark.

**What 7a-3 part A made unnecessary.** The first version of this plan (written against master `9e5d2d5`) carried its own instance-numbering machinery. None of it is built any more: no `PlacementSet`, no `PerInstance` (that file was removed in part A) with `positions` or `span`, no `NodeInputs.positions(_:)` or culled-list slot in `BroadcastPlan` and `TreeCursor`, no `Topology.renumberingInstance` and no `PlacementMoves.copies`, no `instances:` on `PatternApply.Request` or `PatternMisses`, and no edit to Place or the four shortcuts: `InstanceGrid` is the one matching rule and already names each copy by `grid.items`. What stays is the culled list itself (Task 2), the generator (Task 1) and the six nodes (Tasks 4 to 9).

## Merge order and shared files

7a-layouts merges **first**, this track **second**, harness independently. The side that merges second (this one) resolves every conflict below by keeping both sides' additions and re-deriving the numbers noted.

| Shared file | Others touching it | What this track keeps / what to re-derive |
|---|---|---|
| `Sources/CreatorNodes/BuiltInNodes.swift` | 7a-layouts (Task 9 adds `FacePatternNode.self` beside the other layouts) | This track adds six lines **above `OutputNode.self`** (one per node). Keep both. |
| `Tests/CreatorNodesTests/OutputNodeTests.swift` | 7a-layouts (Task 9) | Node count and the category dictionary: after both, 45 + 1 (Face Pattern) + 6 = **52** nodes and `.patterns` = 10 + 1 + 6 = **17**. Each task here edits the numbers by one; re-derive them from the merged base, not from this plan's. |
| `Tests/CreatorEditorTests/PatternsLibraryTests.swift` | 7a-layouts (Task 9) | The Patterns names list: layouts first (library order is `BuiltInNodes.all` order within the category), then Place … Pattern Feature, then this track's six in the order Cull Pattern, Cull Index, Cull by Region, Random Reduce, Random Values, Jitter. |
| `Sources/CreatorGraph/NodeSetting.swift` | 7a-layouts only if it adds a setting | `cullPattern` and `cullIndices` are added to `all`; keep every other track's. |
| `Sources/CreatorGraph/{DataTree,DataTree+Items,DataTree+Shape,Value,BroadcastPlan}.swift` | none planned (7a-layouts Tasks 9 to 14 add nodes, previews, a menu entry, tests and docs) | **Keep the culled list**: `slots` in `DataTree` and the `slots:` parameter of its `init`, `culledList`, `isCulled`, `Leaf.positions`, `replacingItems` keeping the slots, `Value(_:)` returning `.tree` for a culled depth-1 tree, `meetsTree` looking only at trees of depth 2 or more, and `droppingCulls` on an item socket. |
| `Sources/CreatorNodes/Patterns/InstanceGrid.swift` | none planned (Face Pattern reads `LayoutChecks`, `PatternLimit` and `FaceRegion`, not the grid) | Task 3 replaces the file. If 7a-layouts changed it, keep that change and re-apply the culled-lead support: `flatCells`/`treeCells`, `Column`, `culledIndices`, `tree(of:)` returning a culled list, `vectors(_:)`. |
| `Sources/CreatorNodes/Patterns/PointsToPlacementsNode.swift` | none planned | **Keep `points` and `direction` on `.tree` access**, read through `InstanceGrid`, returning `grid.tree(of: planes)` (Task 3). |
| `Tests/CreatorNodesTests/Variation/{CulledPickTests,CulledTreePickTests,InstanceGridCullTests,CulledInstancesTests,PointsToPlacementsCullTests,VariationPipelineTests}.swift` | — | **Must pass unchanged after 7a-layouts merges.** If one fails, the merge broke "culling keeps paths", not the test. They read `PatternPlate`'s `h`, `plate`, `grid`, `placements`, `init(columns:rows:spacingX:spacingY:)` and `plateVolume` (and the `Harness.box`, `onlySolid`, `volume`, `isClose` helpers): if 7a-layouts changes that fixture, adapt the fixture's use in these files, never the expectations. |
| `CLAUDE.md` | 7a-layouts (its Task 14) **and harness** (it edits the testing paragraphs for MetalUITesting and the human-checks sentence) | Each track appends its own paragraph/section; keep all. This track's: the CLAUDE.md paragraph, the "Culling keeps paths" bullet and the Variation bullet. The node count becomes 52 and the `Patterns` nodes seventeen (7a-layouts writes 46 and eleven; this plan writes 51 and sixteen for a branch without Face Pattern); the settings list gains `cullPattern, cullIndices` and the file-format sentence is **not** touched (format stays 6, User decision U17). |
| `docs/superpowers/roadmap.md`, the spec's Errata | 7a-layouts (its Task 14), harness | Append only: this track's roadmap row 7a-3b and "Errata (7a-3 part B)". Keep the other tracks' rows and Errata. |
| `docs/verification/human-checks.md` | 7a-layouts (its Task 14: group PA/LA text) **and harness (it adds the CT group)** | Group VA is inserted directly after the existing paragraph ending `aMissingBranchOrItemInAPathSaysHowManyThereAre`, … **Observed:** (text this branch already has). Keep the other tracks' groups wherever they put them; re-number nothing. |
| `Tests/CreatorNodesTests/Support/VariationFixtures.swift` and every test that calls `Harness`, `EvaluationReport` or `PatternPlate` (all of `Tests/CreatorNodesTests/Variation/`, `Tests/CreatorEditorTests/VariationSettingTests.swift`) | harness (test support: MetalUITesting adoption, it may rename or reshape `Harness` and `EvaluationReport` in `NodeTestSupport.swift`) | This track only **extends** `Harness` (`source(count:rows:)`, `wire(_:to:_:)`) and `EvaluationReport` (`tree`, `positions`) in `VariationFixtures.swift` and uses the existing helpers. **The side that merges second (this one) re-checks `VariationFixtures.swift` and the tests above against any rename or signature change of `Harness`, `EvaluationReport`, `onlySolid`, `volume` and `isClose`**, adapting the fixture's and tests' *use* of them, never an expectation. |
| `Tests/CreatorNodesTests/PatternTreePickTests.swift`, `InstanceGridTests.swift`, `PlaceTreeTests.swift`, `Support/PatternPlate.swift` | 7a-layouts | **Not edited here.** |

## Global Constraints

- Swift 6 strict concurrency, Swift Testing, the repo's `CLAUDE.md` rules: one type per file, behaviour in models and thin views (this plan touches no views), no force unwraps, no GCD, `FormatStyle` for text (`.formatted(.number.locale(.messages))`, `.list(type:)`), no C-style formatting.
- `swiftlint lint --strict` reports zero violations before every commit (line length 140, trailing commas in multi-line literals).
- Randomness is **always seeded** through a `seed` input, by one fixed, documented algorithm implemented in the repo (`SeededRandom`, SplitMix64), **never the system generator**. Each random node draws for its own `SeededRandom.Purpose`, which is mixed into the seed, so two nodes with the same seed do not draw the same numbers (User decision U7). The same seed gives the same result on every machine and in every release, a seed change never warns, and fixed seeds are pinned in tests, per branch and overall.
- Culling keeps paths: survivors keep their original paths (a sparse result), never renumbered, in the value and in instance tags; a pick on an instance survives a cull of another instance and a pick on a culled instance warns naming its path (spec §4, §6).
- Messages are plain and actionable (spec §8): a path error names the shape, a refused value names the socket and the limit, a path that names nothing is named.
- All six nodes are in `NodeCategory.patterns`, tree-aware, and take lists or trees (`access: .tree`).
- `GraphFile.currentFormatVersion` stays 6: the two new settings are `.text` values of new node types (Key decision 10, User decision U17: a deliberate departure from 7a-1, which bumped for its three text settings).
- MetalUI gaps go in `docs/metalui-gaps.md` (entry **and** summary table row) and are never worked around. This plan finds none.
- A full `swift test` run passes only if the exit code is 0, no line says "recorded an issue" or "failed after", and 11 "Test run with" lines appear. Never run the release benchmark (`scripts/bench.sh`).
- Run every command from the worktree root. Do not edit `Package.swift`'s MetalUI path or anything under `../MetalUI`.
- **Reading the edits.** "Create" writes a whole file. "replace … with" swaps one block of text that occurs exactly once. "directly after … add" puts the block on **new lines straight after the anchor's last line** (never on the same line); a block that opens with a blank line leaves one blank line between them.

## Review Focus

The inputs and conditions the spec implies but no node's own happy-path tests would exercise, most likely first. Each has its test in the task that owns the code.

1. **A size or tool list longer than the culled placements.** A culled tail must not come back as repeats of the last placement ("ghost" instances), and a survivor must keep its own size, not the size of its rank. Tests: `aCulledListMakesExactlyTheInstancesItKeepsAtTheirIndices`, `aLongerListAddsNoInstancesToCulledOnes`, `aSurvivorKeepsItsOwnSizeNotTheSizeOfItsRank`, `aCulledSizeListIsReadByTheInstancesIndex`, `aCulledSizeListWithMoreSurvivorsThanPlacementsSetsNoNumberOfInstances` (`InstanceGridCullTests`), `aCulledSizeListLongerThanThePlacementsMakesNoExtraHoles`, `aCulledToolListGivesEachSurvivorItsOwnTool` (`CulledInstancesTests`), all Task 3.
2. **A cull inside a tree of placements** (a Grid Pattern's rows, a Circular Pattern's rings). A gap inside one row must leave the rest of the row where it was, a whole branch culled must leave the other branches' numbers alone, and a size per row must still be read at the instance's place. Tests: `aCulledBranchKeepsItsIndicesInEveryPath`, `aWholeBranchCulledLeavesAGapAndTheOthersKeepTheirNumbers`, `aCulledTreeOfPlacementsKeepsEveryTreePath`, `aSizePerRowAndACullTogetherReadTheRowsSizeAtTheInstancesPlace` (Task 3), `CulledTreePickTests` (Task 5: `aPickOnOneInstanceSurvivesACullOfAnother`, `aWholeBranchCulledNamesEveryPickOnIt`).
3. **Everything culled, and culling a list that was already culled.** A cull that removes every placement leaves the part untouched with no error and no warning, and Place makes no copies; the mask counts the items left, indices and paths name the places items had at the start, nothing renumbers. Tests: `aCullThatRemovesEveryPlacementLeavesThePartAloneAndMakesNoCopies`, `everyPlacementCulledMakesNoInstancesAndGivesBackAnEmptyCulledList` (Task 3), `aMaskThatCullsEverythingLeavesEmptyBranches`, `aSecondCullCountsTheSurvivorsAndKeepsTheFirstOnesIndices` (Task 4), `indicesNameThePlacesTheItemsHadBeforeAnyCull`, `aPathOnAnItemAlreadyCulledWarns` (Task 5).
4. **A cull placed before Points to Placements.** Grid Points → Cull → Points to Placements is the most natural graph, and Points to Placements used to read `points` as a plain list, so the placements came out renumbered and every pick shifted to a neighbour. It now reads `points` as a tree and returns placements at the same paths (User decision U15). Tests: `pointsToPlacementsKeepsACulledListsIndices`, `aTreeOfPointsIsATreeOfPlacementsAtTheSamePaths`, `aCulledDirectionListIsReadByTheInstancesIndexAndSetsNoNumberOfPlacements`, `aCullThatRemovesEveryPointMakesAnEmptyCulledListOfPlacements` (Task 3), and `CulledPickTests` and `CulledTreePickTests` run with the cull on **both sides** of Points to Placements (Task 5).
5. **Numbers must not depend on how many items there are.** More placements, a longer list, a cull, or a changed count must not reshuffle the others: `moreItemsAtTheEndNeverChangeWhichEarlierOneIsLowest` (Task 7), `theFirstNumbersDoNotDependOnHowManyThereAre`, `aCulledShapeGetsNumbersAtThePathsItKeptAndTheOthersKeepTheirNumbers` (Task 8), `addingPlacementsDoesNotMoveTheEarlierOnes`, `aCulledInputStaysCulledAndTheSurvivorsMoveAsTheyWouldHave` (Task 9).
6. **A reshaping node or an ordinary node after a cull** (Partition, Flatten, Path Mapper; Extrude, Rectangle…) renumbers or drops the gaps, as reshaping does; pinned, so a change is deliberate: `aReshapingNodeAfterACullRenumbersAsReshapingDoes` (Task 4), `aCulledListOnAnItemSocketPairsItemsByTheirPlaceInTheList`, `aCulledListOnAListSocketRunsOnceAndGetsItsItems` (Task 2).
7. **Equal seeds on different nodes.** Random Reduce, Random Values and Jitter all default to seed 0; unsalted, the items Random Reduce drops would be exactly the ones with the smallest Random Values. Each node draws for its own `SeededRandom.Purpose` (Task 1: `eachPurposeHasItsOwnPinnedNumbers`, `equalSeedsOnDifferentPurposesDrawDifferentNumbers`; Task 10: `withTheSameSeedTheItemsRandomReduceDropsAreNotTheSmallestRandomValues`).
8. **A tree three deep, `{row;column;0}`** (Face Pattern's shape, one item per branch, which Place, the shortcuts and every node here must handle). A bare index and Cull Pattern's per-branch mask count places *within a branch*, so there they are degenerate (bare `1` culls nothing, `0` culls every cell, `1 0` keeps every cell) and Random Reduce Per branch empties the tree: pinned, with the ways to reach cells (paths, Cull Pattern Overall, Random Reduce Overall) pinned beside them (User decision U16). Tests, built by hand from a Series, Partition and Graft (never Face Pattern): `CellTreeTests` (Cull Index, Cull Pattern, Random Reduce, Random Values and Jitter ordinals), `CellTreePickTests` (Place's instance paths and tags after a cull of one cell; a pick survives a cull of another cell, a pick on a culled cell warns naming `{1;1;0}`), all Task 11.

---

## Key decisions

1. **Item-level gaps: `Value.tree` could not express them, so it is extended minimally.** 7a-1 holds a sparse tree's gaps as empty branches, which only says "branch 2 has nothing", not "item 1 of this branch is gone". `InstanceGrid` reads those branch gaps already (an instance's path is its leaf's path plus the item's index, so `{2;0}` stays `{2;0}` with `{1}` empty), so only the item level is new. The extension: a `DataTree` of depth 1 may carry `slots`, the index each item keeps (`DataTree.culledList(_:at:)`, `isCulled`, `itemPositions`); `Value(_:)` makes it a `Value.tree` of depth 1 (a `.list` cannot say it), and every other flat tree stays a `.list`, so no existing value changes form. Deeper trees carry gaps in their depth-1 leaves, so a cull of a 3 × 8 tree leaves 3 culled branches. *Why not a null item:* arithmetic nodes would fail with type errors on it, and counts would include it. A list culled only at its end is still marked culled (`slots` held even when 0, 1, 2…) so the culled tail cannot come back as repeated placements.
2. **A culled list broadcasts as a list.** `BroadcastPlan.meetsTree` now looks only at trees of depth 2 or more, so a culled list on a `list` or `item` socket runs the node as a list would, seeing its survivors in order (a rank; the gaps are dropped, User decision U6), and on a `tree` socket it arrives whole with its indices. Nothing reads indices through a `list` socket, because every pattern node takes its placements whole.
3. **Surviving instances keep their path with no kernel change and no renumbering.** `InstanceGrid` builds each instance's path from the index its item kept (`leaf.path + [index]`, or `[index]` for a flat list) and `PlacementMoves.place` already renames a copy `Kernel.place` numbered by position to `grid.items[i]` (`InstancePath.item(for:)`). So a survivor's copy carries its original path in every tag, a flat survivor `{3}` keeps the tag item 3 exactly as before trees (saved picks resolve unchanged), and `Topology.vanishedInstances` already names a culled path in the pick's warning.
4. **Instances are exactly the surviving indices, and everything else is read at the index.** A culled flat lead makes its indices' instances (a plain list makes `0..<` the longest plain list, as before); a tree lead makes an instance per item at `leaf.path + [index]`. A size, tool or direction input is read at the instance's index: its own value if it has one there, else the nearest one before it, else its first, which is how a plain shorter list repeating its last item already behaved (User decision U12). A culled input that is not the lead never sets the number of instances, however many survivors it holds, and one with everything culled makes none (the rule "any input with no items makes no instances" is unchanged). `InstanceGrid.tree(of:)` returns the copies in the placements' shape with the same gaps, so Place's `solids` output of culled placements is culled alike.
5. **One generator, drawn by place.** `SeededRandom` is SplitMix64: draw `k` of a stream is `mix(start + (k + 1) × 0x9E3779B97F4A7C15)`, so any draw is reachable directly and sequential and direct access agree. Stream 0 starts at the seed; stream `n` at `mix(seed + n × step)`. Nodes draw item `(branch ordinal n, index i)` from stream `n` at draw `i` (Jitter: draws `3i`, `3i + 1`, `3i + 2`), so counts, culls and longer lists reshuffle nothing. Seed 0 reproduces the published SplitMix64 vector (pinned, `Purpose.plain`), and other seeds' first draws are pinned. **Each random node draws for its own `SeededRandom.Purpose`** (`reduce`, `values`, `jitter`): the seed is first mixed with a fixed per-purpose constant (`mix(seed ^ salt)`, the salt being the node's name in ASCII ending `_1`), so equal seeds on different nodes draw unrelated numbers (User decision U7). The salts are part of the contract and pinned in `SeededRandomTests`.
6. **Random Reduce ranks, it does not shuffle.** Every item gets its draw as a key and the smallest keys go: a bigger amount drops what a smaller one did and more, and the choice depends on the seed and the items' places alone. Per branch ranks within each branch (stream = branch ordinal); overall ranks all items together. A fraction rounds to the nearest whole item, halves up.
7. **Random Values has two outputs.** `values` (reals, `min` up to `max`) and `integers` (both ends included, `min` rounded up to `max` rounded down), the second an optional output left out when no whole number is in range (the existing "isn't produced" wire message covers it). With a `shape` wired it fills that tree (culled gaps included); with none it makes a flat list of `count` (at most 100,000).
8. **Cull Pattern and Cull Index take their lists as saved text** (`cullPattern`: `1 0 1`; `cullIndices`: `1, 4, {0;3}`) because no node today makes a list of booleans or integers by hand; each also takes a wired list (`keep` booleans; `indices` numbers, so a Series or Random Values' `integers` works). A bare index names that place *within* every branch (the last level: on a `{row;column;0}` tree only 0 is a place, User decision U16); a path names one item or, when short, a whole branch (left as an empty branch). Cull Pattern also has a `scope` (Per branch, the default: the mask restarts at every branch; Overall: it runs on along the whole tree in order).
9. **Cull by Region judges a placement by its origin**; a profile is a prism along its plane's normal; the boundary counts as inside/within; distances use exact straight and circular edges (anything else refuses with the count) and the **plane** of a flat face (a curved face refuses with the count; User decision U3, chosen). Choices are integer sockets with segmented controls (`reference`: Profile, Point, Edges, Face; `keep`: Inside or within, Outside or beyond), the same way `Pattern Feature`'s operation is.
10. **No file-format bump, a deliberate departure from 7a-1 (User decision U17).** 7a-1 bumped to 6 for its three text settings, so a build without them would refuse the file. Here the format stays 6: the settings belong to new node types, no `ConstantValue` kind is added (CLAUDE.md's bump rule does not apply), and 7a-2 and 7a-3 part A added nodes without a bump. What an older build does with such a file is *not* "refuse": a format-6 file opens, and each unknown node type is an error on that node when it is evaluated (`EvaluatorTests.unknownNodeTypeIsAnErrorNotACrash`); only a file of a *newer* format is refused (`TreeFileTests.aNewerFileIsStillRefusedWithItsVersion`). `NodeSetting.all` gains the two names (so Group sockets cannot be named like them). `VariationFileTests` (Task 11) pins a save and reopen of both settings and that a format-5 file still opens.
11. **The nodes are `tree`-access and `any`-typed** (like the Lists & Trees nodes), except Cull by Region and Jitter, whose placements are `plane`-typed, and Random Values, whose outputs are `number` and `integer`: a typed wire connects them to size and placement inputs, and `Value.converted(to:)` keeps the culled indices.
12. **Points to Placements takes trees (User decision U15, chosen by the user: "fix it properly now").** `points` and `direction` move to `.tree` access and are matched by `InstanceGrid`, the same rule Place uses, and the placements come back in the shape of the points with the same paths (`grid.tree(of:)`). A cull anywhere before the node therefore keeps paths and no renumbering warning exists. Side effects, pinned: a tree of points gives a tree of placements (as the per-branch runs it replaces did), the 2,000-instance limit now counts the whole tree rather than each branch, and a zero direction names the instance's tree path (`The direction of placement {1;2} can't be zero.`).

## User decisions (the plan takes the recommended default; change them before executing if you disagree)

| # | Open product behaviour | Options | Recommended and planned |
|---|---|---|---|
| U1 | Cull Pattern polarity | (a) `1`/true **keeps**, `0`/false culls, the wired socket is called `keep`; (b) Grasshopper's: true culls | (a): "keep" says what the socket does; a designer reads `1 0` as "every other one stays". |
| U2 | What a repeating mask counts | (a) the items the branch has **now** (a second Cull Pattern works on what is left); (b) the places they had | (a), like a list pattern in Grasshopper. Indices and paths in Cull Index always use places. |
| U3 | Distance to a face | (a) to the face's **plane**, flat faces only, a curved face refused (a placement far beside a small face counts as near it); (b) Face refuses altogether until a kernel distance to the face's outline exists; (c) to the face's real outline (needs a kernel query) | **(a), chosen by the user (2026-10-12).** (c) when a kernel distance exists; the docs, the node's comment and the Errata say "to the plane". `FaceInfo` has no bounds beyond area and centroid, so "also inside the face's bounds" cannot be done without that query. |
| U4 | A placement exactly on a boundary or at exactly the distance | (a) inside/within; (b) outside/beyond | (a). |
| U5 | Paths through reshaping and selecting | (a) Partition, Flatten, Graft and Path Mapper renumber a culled list (reshaping makes new branches), and **List Item, Branch by Path and Tree Statistics count a culled list's survivors by rank** (List Item index 2 on a list culled to {0, 2, 4} returns the item at {4}), while Cull Index always names the places items had; (b) they carry or name the old indices | (a): cull last, or cull after reshaping; the same rule as U2 (a node that works on "what is there now" counts the survivors). (b) would need each node to decide what a path means after a reshape, and would change 7a-1's nodes. |
| U6 | An arbitrary node (Extrude, Rectangle…) fed a culled list | (a) pairs by place and returns a plain list (gaps dropped); (b) keeps the gaps in its output (the "outputs keep the deepest nesting" rule extended to gaps) | (a) now: only the pattern, cull and random nodes keep gaps. Wire the cull after the sizes, or feed sizes into the pattern node (it reads them by index). |
| U7 | Two random nodes with the same seed | (a) the same draws (correlated: with equal seeds Random Reduce drops exactly the items with the smallest Random Values, and Jitter's offsets follow the same numbers); (b) each node type salts the seed (`SeededRandom.Purpose`) so equal seeds decorrelate | **(b), planned.** Nothing has shipped with these nodes, so the salt costs nothing now, and adding one later would change every pinned value and every saved file's result, which is the property the spec makes a promise. The cost: one more constant per node to document and pin. Choose (a) only if "the seed is the seed" matters more than independence. |
| U8 | Jitter's shape | (a) a disc of radius `distance` in the placement's plane and a symmetric turn; (b) a square (independent X and Y limits) | (a): one number, direction-free. |
| U9 | Random Values' `integers` when no whole number is in range | (a) output left out (a wire says it isn't produced); (b) error | (a): the reals still work. |
| U10 | A bare number in Cull Index | (a) names that place in **every** branch; (b) is refused unless it is a full path | (a): the common case for a flat list or "the third of every row". A bare `{}` (the empty path, the whole tree) is refused with a message pointing at Cull Pattern `0`, since a stray `{}` must not empty a graph silently. |
| U11 | Where Cull by Region judges a placement | (a) by its **origin** only, a profile being a prism along its plane's normal (a tilted placement's footprint and height are ignored); (b) by the placement's footprint or the tool's extent | (a): one point, easy to predict and explain; a designer who needs margins adds the tool's radius to `distance`. |
| U12 | An instance whose own size or tool was culled | (a) takes the nearest earlier surviving value, else the first (a plain shorter list repeats its last); (b) is refused, naming its path; (c) is skipped | (a): never a surprise failure after a cull, and it is how a shorter plain list already behaves. |
| U13 | Rounding a fraction in Random Reduce | (a) to the nearest whole item, halves up (a quarter of 6 is 2); (b) always down; (c) always up | (a). |
| U14 | Defaults | Random Reduce drops 1 from the whole tree (scope Overall, seed 0); Cull Pattern starts at `1 0` (every other item stays, scope Per branch); Jitter 1 mm and 5 degrees; Random Values 8 values from 0 to 1 | As planned: each does something visible when dropped on the canvas, and 0 is the empty default only for Cull Index. Random Reduce's scope was Per branch until this revision: on branches of one item (a Face Pattern's cells) a default of "1 per branch" emptied the graph (U16). The alternative is dropping nothing by default. |
| U15 | Points to Placements and a cull before it | (a) a culled branch inside a tree run is returned renumbered with a warning; (b) refused; (c) `points` taken as a whole tree and the tree of placements returned with the same paths | **(c), chosen by the user (2026-10-12): "fix it properly now".** Done in Task 3 on top of 7a-3 part A's `InstanceGrid`; no renumbering and no warning exist. |
| U16 | Reaching cells in a tree three deep, `{row;column;0}` (Face Pattern's shape: one item in every branch). Checked on a 2 × 3 × 1 tree: a bare Cull Index `1` culls **nothing** (a bare index is a place within a branch, and the only place is 0), `0` culls **every** cell, Cull Pattern `1 0` per branch keeps **every** cell, and Random Reduce Per branch with Count 1 drops **all six**; only path lists (`{0;1}`, `{0;1;0}`, `{1}`) and Cull by Region work as they do on rows. (An earlier version of this row said Cull Index `1` keeps every other vent: that was wrong.) | (a) keep one rule (places within a branch) and give the nodes a way to reach cells: Cull Pattern gets a `scope` (Per branch, Overall), Random Reduce defaults to Overall, Cull Index reaches cells by paths; (b) also level-aware indices or a wildcard in Cull Index (`{*;1}`, "column 1 of every row" in one entry); (c) make a bare index and the mask count the whole tree by default (changes rows: `1` would no longer mean "the second of every row"); (d) change nothing and document that these nodes want paths on cells | **(a), planned.** With it: Cull Pattern `1 0` with scope Overall keeps cells 0, 2, 4 of the six; Random Reduce drops one cell by default and Per branch stays available (and documented as emptying such a tree); paths cull a cell (`{0;1}` or `{0;1;0}`) or a row (`{1}`). Bare indices stay as U10 says and are pinned on this shape. What (a) cannot do is "this column of every row" in one entry (list `{0;1}, {1;1}`, or use Cull by Region); a wildcard (b) is a small later addition if designers ask for it. (c) would break the rule rows already have. |
| U17 | The file format when these nodes (and their two text settings) are saved | (a) stay at 6, as 7a-2 and 7a-3 part A did: no `ConstantValue` kind is added, a format-6 file opens in an older build and shows the new nodes as unknown types; (b) bump to 7 as 7a-1 did for its text settings, so older builds refuse the file by version | **(a), planned.** It is a departure from 7a-1's precedent and from the spec's line "older builds refuse format-6 files": that refusal would come from a newer *format*, which these nodes do not need. (b) would also edit five test files that spell the version, `TreeFileTests.aNewerFileIsStillRefusedWithItsVersion` (which uses 7), CLAUDE.md's format sentence and collide with whichever parallel track also bumps. Choose (b) only if an older build must refuse to open such files rather than show unknown nodes. |
| U18 | Cull by Region's Face reference when no node can produce a face set | (a) keep it as built: the node, its distance maths (to the face's plane) and its tests exist, the `faces` socket can't be wired from the window until a node outputs a face set, and VA-17 records that; (b) leave "Face" out of the segmented control until a face-set node exists; (c) add a face-set node now (new scope: a Faces by Tag, say) | **(a), planned.** The spec (§4) lists a face as a reference; a producer belongs with face selection, not with variation; hiding it and bringing it back later changes a saved `reference` value. Until then the Face option on the canvas reports a missing `faces` input. |

---

## File structure

Source (all new files unless marked), by responsibility:

| File | Responsibility |
|---|---|
| `Sources/CreatorNodes/Patterns/Variation/SeededRandom.swift` | SplitMix64: the only generator; draws by place; a `Purpose` per random node |
| `Sources/CreatorGraph/DataTree.swift` (edit), `DataTree+Culling.swift`, `DataTree+Items.swift` (edit), `Value+Culled.swift` | culled lists: per-item indices, `keepingItems`, `mappingItems`, `rebuildingLeaves`, `replacingItems` keeping them |
| `Sources/CreatorGraph/{Value,DataTree+Shape,BroadcastPlan}.swift` (edits) | `Value(_:)` form, "culled" in shape text, a culled list broadcasts as a list |
| `Sources/CreatorNodes/Patterns/InstanceGrid.swift` (edit) | the instances culled placements make; every other input read at the instance's index; copies back with the same gaps |
| `Sources/CreatorNodes/Patterns/PointsToPlacementsNode.swift` (edit) | points and directions as trees; placements at the same paths |
| `Sources/CreatorNodes/Patterns/Variation/CullMask.swift`, `CullPatternNode.swift` | Cull Pattern |
| `Sources/CreatorNodes/Patterns/Variation/CullTargets.swift`, `CullIndexNode.swift` | Cull Index |
| `Sources/CreatorGeometry/Profile2D+Contains.swift`, `Sources/CreatorNodes/Patterns/Variation/RegionDistance.swift`, `CullByRegionNode.swift` | Cull by Region |
| `Sources/CreatorNodes/Patterns/Variation/RandomReduction.swift`, `RandomReduceNode.swift` | Random Reduce |
| `Sources/CreatorNodes/Patterns/Variation/RandomValuesNode.swift` | Random Values |
| `Sources/CreatorNodes/Patterns/Variation/PlaneJitter.swift`, `JitterNode.swift` | Jitter |
| `Sources/CreatorGraph/NodeSetting.swift`, `Sources/CreatorNodes/BuiltInNodes.swift` (edits) | `cullPattern`, `cullIndices`; six registrations |

Tests: `Tests/CreatorNodesTests/Variation/*` (one file per node, `InstanceGridCullTests`, `CulledInstancesTests`, `PointsToPlacementsCullTests`, `CulledPickTests`, `CulledTreePickTests`, `VariationPipelineTests`),
`Tests/CreatorGraphTests/Trees/CulledTreeTests.swift`, `Tests/CreatorGeometryTests/ProfileContainsTests.swift`, `Tests/CreatorNodesTests/Support/VariationFixtures.swift`,
`Tests/CreatorNodesTests/Variation/{CellTreeTests,CellTreePickTests,VariationFileTests}.swift` (Task 11), `Tests/CreatorEditorTests/VariationSettingTests.swift` (Task 11), and edits to
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
swift test > "${TMPDIR:-/tmp}/vtest.log" 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,752 = master + 11** (+11 in this task; the Swift Testing total counts a parameterised test once).

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
- Modify: `Sources/CreatorGraph/DataTree+Items.swift`
- Modify: `Sources/CreatorGraph/DataTree+Shape.swift`
- Modify: `Sources/CreatorGraph/DataTree.swift`
- Modify: `Sources/CreatorGraph/Value.swift`
- Test: `Tests/CreatorGraphTests/Trees/CulledTreeTests.swift` (new)

**Interfaces:**

- Consumes: 7a-1: `DataTree`, `Value.tree`, `TreePath`, `BroadcastPlan`, `NodeInputs.tree`; 7a-3 part A: `DataTree.replacingItems(_ scalars:)` (`DataTree+Items.swift`).
- Produces: `DataTree.culledList(_ scalars: [Scalar], at positions: [Int]) -> DataTree?` (nil unless one non-negative, strictly increasing index per
item); `isCulled: Bool`; `itemPositions: [Int]` (a flat list's indices; empty for a deeper tree); `culledPositions: [Int]?`;
`DataTree.Leaf` gains `positions: [Int]`, `isCulled: Bool` and `itemPath(_ k: Int) -> TreePath`;
`rebuildingLeaves(_ transform: (Leaf, _ ordinal: Int) -> LeafRewrite) -> DataTree`;
`keepingItems(where keep: (Leaf, _ ordinal: Int, _ k: Int) -> Bool) -> DataTree` (survivors keep their indices; an unchanged plain list stays plain);
`mappingItems(_ transform: (Leaf, _ ordinal: Int, _ k: Int) -> Scalar) -> DataTree`; `replacingItems(_ scalars:)` now keeps a culled list's indices;
`Value(_:)` returns `.tree` for a culled depth-1 tree; `DataTree.shapeText` adds ", culled".

This is the key extension (Key decisions 1 and 2): a flat list or branch that has had items taken out holds the survivors at the indices
they had. `DataTree` gains the optional per-item indices of a depth-1 tree, `Value(_:)` makes a culled depth-1 tree a `.tree`, and two builders
(`keepingItems`, `mappingItems`) are how every later node culls or refills a tree while keeping its nesting. Nothing existing changes form: a
plain flat tree is still a `.list`. Broadcasting treats a culled list as a list (a node on a `list` or `item` socket sees its survivors in
order, as a rank: User decision U6); only a `tree`-access socket sees the indices, and that is how `InstanceGrid` (Task 3) reads them.
Nothing reads the indices through a `list` socket, because after 7a-3 part A every pattern node reads its placements whole.

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

    @Test func mappingItemsKeepsTheNestingAndTheIndices() throws {
        let tree = try #require(DataTree(depth: 2, branches: [culled([1, 2], at: [1, 4]), .list(numbers([3]))]))
        let replaced = tree.mappingItems { leaf, ordinal, k in .integer(ordinal * 100 + leaf.positions[k]) }
        #expect(replaced.outline == "[[1,4],[100]]")
        #expect(replaced.leaves.map(\.positions) == [[1, 4], [0]])
    }

    @Test func replacingItemsKeepsTheIndicesOfACulledList() throws {
        let flat = try culled([1, 2], at: [1, 4])
        let replaced = try #require(flat.replacingItems(numbers([8, 9])))
        #expect(replaced.isCulled && replaced.itemPositions == [1, 4])
        let deep = try #require(DataTree(depth: 2, branches: [culled([1], at: [2]), .list(numbers([3, 4]))]))
        #expect(try #require(deep.replacingItems(numbers([5, 6, 7]))).leaves.map(\.positions) == [[2], [0, 1]])
    }

    // MARK: broadcasting

    let specs = [SocketSpec("a", .number, access: .list), SocketSpec("b", .number)]

    @Test func aCulledListOnAListSocketRunsOnceAndGetsItsItems() throws {
        let plan = BroadcastPlan.make(inputs: ["a": Value(try culled([1, 2, 3], at: [0, 2, 5]))], specs: specs)
        #expect(!plan.isTreeRun)
        #expect(plan.iterations == 1)
        #expect(try plan.inputs(at: 0).list("a").count == 3, "a list socket sees the survivors in order, as a rank")
    }

    @Test func aCulledListOnAnItemSocketPairsItemsByTheirPlaceInTheList() throws {
        let reals = try #require(DataTree.culledList([5, 6, 7].map { .number(Double($0)) }, at: [1, 2, 8]))
        let plan = BroadcastPlan.make(inputs: ["a": .one(.number(0)), "b": Value(reals)], specs: specs)
        #expect(!plan.isTreeRun)
        #expect(plan.iterations == 3)
        #expect(try (0..<3).map { try plan.inputs(at: $0).number("b") } == [5, 6, 7])
    }

    @Test func aCulledListBesideARealTreeBroadcastsLikeAList() throws {
        let tree = try #require(DataTree(depth: 2, branches: [.list(numbers([1, 2])), .list(numbers([3, 4]))]))
        let plan = BroadcastPlan.make(inputs: ["a": Value(try culled([1, 2], at: [0, 4])), "b": .tree(tree)], specs: specs)
        #expect(plan.isTreeRun)
        #expect(plan.iterations == 4)
        #expect(try plan.inputs(at: 3).list("a").count == 2)
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
    public func mappingItems(_ transform: (_ leaf: Leaf, _ ordinal: Int, _ k: Int) -> Scalar) -> DataTree {
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
    let slots: [Int]?
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


In `Sources/CreatorGraph/DataTree+Items.swift`, replace:

```swift
            let taken = Array(scalars[next..<next + count])
            next += count
            return .list(taken)
```

with:

```swift
            let taken = Array(scalars[next..<next + count])
            next += count
            return DataTree(depth: 1, scalars: taken, children: [], slots: slots)
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
            case .item:
                itemInputs[spec.name] = value
                if case .list(let scalars) = value { counts.append(scalars.count) }
```

with:

```swift
            case .item:
                let flat = value.droppingCulls
                itemInputs[spec.name] = flat
                if case .list(let scalars) = flat { counts.append(scalars.count) }
```


- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter "CulledTreeTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

- [ ] **Step 5: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > "${TMPDIR:-/tmp}/vtest.log" 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,772 = master + 31** (+20 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(7a-3b): culled lists, a flat tree whose items keep the indices they had"
```

---

### Task 3: Surviving instances keep their path

**Files:**

- Modify (the whole file is given): `Sources/CreatorNodes/Patterns/InstanceGrid.swift`
- Modify (the whole file is given): `Sources/CreatorNodes/Patterns/PointsToPlacementsNode.swift`
- Test: `Tests/CreatorNodesTests/Variation/InstanceGridCullTests.swift` (new)
- Test: `Tests/CreatorNodesTests/Variation/CulledInstancesTests.swift` (new)
- Test: `Tests/CreatorNodesTests/Variation/PointsToPlacementsCullTests.swift` (new)

**Interfaces:**

- Consumes: Task 2: `DataTree.culledList`, `isCulled`, `itemPositions`, `culledPositions`, `Leaf.positions`, `keepingItems`; 7a-3 part A: `InstanceGrid`, `InstancePath.item(for:)` / `indices(ofItem:)` / `text(_:)`, `PlaceNode`, the four shortcuts, `PlacementMoves.place` (which names each copy by `grid.items[i]`), `PatternMisses`, `PatternLimit`.
- Produces: `InstanceGrid` reads culled trees: a culled flat lead makes exactly its indices' instances (`paths == [[i]]`, `items == [i]`), a tree lead makes an instance per item at `leaf.path + [the index the item kept]`, every other input is read at the instance's index (`Column.scalar(at:)`: its own value, else the nearest one before it, else its first; a plain list repeats its last), a culled input that is not the lead sets no number of instances, and `tree(of:)` returns the instances in the placements' shape with the same gaps (a culled list at the same indices for a flat lead); `InstanceGrid.vectors(_:) throws -> [Vector3]`; `PointsToPlacementsNode` with `points` and `direction` on `.tree` access, returning `NodeOutputs(trees: ["placements": grid.tree(of: planes)])`.

After 7a-3 part A an instance is named by its tree path (`{3}`, `{1;2}`), placements, sizes and tools are read whole through one rule, and the copies are renamed by `grid.items`. So culling needs no instance-numbering machinery of its own: if the rule reads the index each item kept instead of its rank, a survivor keeps its path in its tags, its messages, its tool and its size, and a pick on it follows it. This task is that one change to `InstanceGrid`, plus Points to Placements reading its `points` whole: it used to read them as a list and return a plain list (and, in a tree run, one list per branch), which would renumber any cull placed before it (Grid Points, then a Cull, then Points to Placements, is as natural a graph as the cull after it; User decision U15). Place and the four shortcuts are **not edited**: they already read `InstanceGrid` and give `grid.tree(of:)` back, which now carries the gaps. Dense graphs behave exactly as before, so the 7a-2 and 7a-3 part A tests pass untouched; run them after Step 3.

After Step 3 also run the existing pattern suites, which the change must not move:
`swift test --filter "HolePatternNodeTests|BossPatternNodeTests|SlotPatternNodeTests|PatternFeatureNodeTests|PlaceNodeTests|PlaceTreeTests|InstanceGridTests|PointsToPlacementsNodeTests|PatternTreePickTests|PatternPickStabilityTests|GroupPatternNamingTests"`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/CreatorNodesTests/Variation/InstanceGridCullTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Culling keeps paths (patterns spec §4, §6) where instances are named: `InstanceGrid` makes exactly the instances a culled
/// list or branch holds, at the indices they had, and reads every other input at those indices.
struct InstanceGridCullTests {
    func numbers(_ values: Double...) -> DataTree { .list(values.map(Scalar.number)) }

    /// `values`, with only the items at `kept` left, as a Cull node leaves them.
    func culled(_ values: [Double], keeping kept: [Int]) throws -> DataTree {
        try #require(DataTree.culledList(kept.map { .number(values[$0]) }, at: kept))
    }

    func rows(_ rows: [[Double]]) throws -> DataTree {
        try #require(DataTree(depth: 2, branches: rows.map { .list($0.map(Scalar.number)) }))
    }

    func grid(_ trees: [(SocketName, DataTree)]) throws -> InstanceGrid {
        try InstanceGrid(trees.map { (name: $0.0, tree: $0.1) })
    }

    // MARK: A culled flat list

    @Test func aCulledListMakesExactlyTheInstancesItKeepsAtTheirIndices() throws {
        let grid = try grid([("placements", try culled([0, 10, 20, 30], keeping: [1, 3]))])
        #expect(grid.count == 2)
        #expect(grid.paths == [[1], [3]])
        #expect(grid.items == [1, 3], "a flat instance is named by its index, so {3} is still {3}")
        #expect(try grid.numbers("placements") == [10, 30])
    }

    @Test func aLongerListAddsNoInstancesToCulledOnes() throws {
        let grid = try grid([("placements", try culled([0, 1, 2, 3, 4], keeping: [0, 1])), ("size", numbers(5, 6, 7, 8, 9, 10))])
        #expect(grid.count == 2, "what was culled off the end stays gone")
        #expect(try grid.numbers("size") == [5, 6])
    }

    @Test func aSurvivorKeepsItsOwnSizeNotTheSizeOfItsRank() throws {
        let grid = try grid([("placements", try culled([0, 1, 2, 3], keeping: [1, 3])), ("size", numbers(10, 20, 30, 40))])
        #expect(try grid.numbers("size") == [20, 40])
    }

    @Test func aCulledSizeListIsReadByTheInstancesIndex() throws {
        let sizes = try culled([5, 0, 0, 9], keeping: [0, 3])
        let grid = try grid([("placements", numbers(0, 0, 0, 0)), ("size", sizes)])
        #expect(try grid.numbers("size") == [5, 5, 5, 9], "its own value at its index, else the nearest one before it")
        let late = try self.grid([("placements", numbers(0, 0, 0)), ("size", try culled([0, 0, 0, 7], keeping: [3]))])
        #expect(try late.numbers("size") == [7, 7, 7], "before its first survivor, the first")
    }

    @Test func aCulledSizeListWithMoreSurvivorsThanPlacementsSetsNoNumberOfInstances() throws {
        let sizes = try #require(DataTree.culledList(Array(repeating: Scalar.number(5), count: 10), at: Array(10..<20)))
        let grid = try grid([("placements", numbers(0, 0, 0, 0)), ("size", sizes)])
        #expect(grid.count == 4, "ten survivors do not make ten instances")
        #expect(grid.items == [0, 1, 2, 3])
    }

    @Test func aCulledSizeListWithNothingLeftMakesNoInstances() throws {
        let nothing = try #require(DataTree.culledList([], at: []))
        let grid = try grid([("placements", numbers(0, 0, 0)), ("size", nothing)])
        #expect(grid.count == 0)
    }

    @Test func everyPlacementCulledMakesNoInstancesAndGivesBackAnEmptyCulledList() throws {
        let grid = try grid([("placements", try #require(DataTree.culledList([], at: []))), ("size", numbers(1, 2))])
        #expect(grid.count == 0 && grid.items.isEmpty)
        let back = grid.tree(of: [])
        #expect(back.isCulled && back.itemCount == 0)
    }

    @Test func theOutputIsCulledAtTheSameIndices() throws {
        let grid = try grid([("placements", try culled([0, 1, 2, 3, 4], keeping: [0, 2, 3]))])
        let back = grid.tree(of: [.integer(7), .integer(8), .integer(9)])
        #expect(back.isCulled && back.itemPositions == [0, 2, 3])
        #expect(back.items.map(\.outlineText) == ["7", "8", "9"])
    }

    @Test func aPlainListIsStillPlain() throws {
        let grid = try grid([("placements", numbers(1, 2))])
        #expect(!grid.tree(of: [.integer(7), .integer(8)]).isCulled)
    }

    // MARK: A culled tree

    @Test func aCulledBranchKeepsItsIndicesInEveryPath() throws {
        let tree = try rows([[0, 1, 2, 3], [4, 5, 6]]).keepingItems { leaf, _, k in !(leaf.path == TreePath([0]) && k == 1) }
        let grid = try grid([("placements", tree)])
        #expect(grid.paths == [[0, 0], [0, 2], [0, 3], [1, 0], [1, 1], [1, 2]], "{0;2} is still {0;2} with {0;1} gone")
        #expect(grid.items == grid.paths.compactMap { InstancePath.item(for: $0) })
        #expect(try grid.numbers("placements") == [0, 2, 3, 4, 5, 6])
    }

    @Test func aFlatListAppliesByIndexToACulledBranch() throws {
        let tree = try rows([[0, 0, 0, 0], [0, 0, 0]]).keepingItems { leaf, _, k in !(leaf.path == TreePath([0]) && k == 1) }
        let grid = try grid([("placements", tree), ("size", numbers(10, 20, 30, 40))])
        #expect(try grid.numbers("size") == [10, 30, 40, 10, 20, 30], "{0;2} takes the third size, not the second")
    }

    @Test func aWholeBranchCulledLeavesAGapAndTheOthersKeepTheirNumbers() throws {
        let tree = try rows([[0, 0], [0, 0, 0]]).keepingItems { leaf, _, _ in leaf.path != TreePath([0]) }
        let grid = try grid([("placements", tree)])
        #expect(grid.paths == [[1, 0], [1, 1], [1, 2]])
        let back = grid.tree(of: grid.paths.map { _ in .integer(1) })
        #expect(back.outline == "[[],[1,1,1]]")
    }

    @Test func theOutputOfACulledTreeHasTheSameGaps() throws {
        let tree = try rows([[0, 0, 0, 0], [0, 0]]).keepingItems { leaf, _, k in !(leaf.path == TreePath([0]) && k % 2 == 1) }
        let grid = try grid([("placements", tree)])
        let back = grid.tree(of: (0..<grid.count).map { .integer($0) })
        #expect(back.leaves.map(\.positions) == [[0, 2], [0, 1]])
        #expect(back.items.map(\.outlineText) == ["0", "1", "2", "3"])
    }

    @Test func aCulledTreeOfSizesIsReadAtTheInstancesPlace() throws {
        let sizes = try rows([[1, 2, 3], [4, 5, 6]]).keepingItems { _, _, k in k != 1 }
        let grid = try grid([("placements", try rows([[0, 0, 0], [0, 0, 0]])), ("size", sizes)])
        #expect(try grid.numbers("size") == [1, 1, 3, 4, 4, 6], "{r;1} takes the nearest size before it")
    }

    @Test func aCulledFirstItemInATreeOfSizesIsStoodInForByTheFirstSurvivor() throws {
        let sizes = try rows([[1, 2], [3, 4]]).keepingItems { _, _, k in k != 0 }
        let grid = try grid([("placements", try rows([[0, 0], [0, 0]])), ("size", sizes)])
        #expect(try grid.numbers("size") == [2, 2, 4, 4], "the first survivor stands in for the culled first item")
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

/// Points to Placements takes its points whole and gives back placements with the same paths (patterns spec §4, User decision
/// U15), so a cull anywhere before it, on the Grid Points say, numbers the instances as a cull of the placements would.
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

    func context() -> EvalContext {
        EvalContext(node: BuiltInNodes.registry.makeNode(PointsToPlacementsNode.typeID), item: 0, parameters: [:])
    }

    func point(_ index: Int) -> Scalar { .vector(Vector3(Double(index) * 20, 0, 0)) }

    /// Points at x = 0, 20, 40, 60 with the ones in `kept` left, as a Cull node leaves them.
    func culledPoints(_ kept: [Int]) throws -> Value {
        Value(try #require(DataTree.culledList(kept.map(point), at: kept)))
    }

    @Test func pointsToPlacementsKeepsACulledListsIndices() async throws {
        let outputs = try await PointsToPlacementsNode.evaluate(inputs(["points": try culledPoints([1, 2, 3])]), kernel: kernel,
                                                                context: context())
        let tree = try #require(outputs.trees["placements"])
        #expect(tree.itemPositions == [1, 2, 3], "the first survivor is still {1}, not {0}")
        #expect(Value(tree).planes?.map(\.origin.x) == [20, 40, 60])
        #expect(outputs.warnings.isEmpty)
    }

    @Test func aCulledDirectionListIsReadByTheInstancesIndexAndSetsNoNumberOfPlacements() async throws {
        let directions = try #require(DataTree.culledList([.vector(.unitX), .vector(.unitY)], at: [0, 2]))
        let points = Value.list((0..<3).map(point))
        let outputs = try await PointsToPlacementsNode.evaluate(inputs(["points": points, "direction": Value(directions)]),
                                                                kernel: kernel, context: context())
        let tree = try #require(outputs.trees["placements"])
        let planes = try #require(Value(tree).planes)
        #expect(planes.count == 3, "three points, three placements")
        #expect(zip(planes.map(\.normal), [Vector3.unitX, .unitX, .unitY]).allSatisfy { isClose($0, $1) }, "{1} takes {0}'s direction")
    }

    @Test func aCullThatRemovesEveryPointMakesAnEmptyCulledListOfPlacements() async throws {
        let outputs = try await PointsToPlacementsNode.evaluate(inputs(["points": try culledPoints([])]), kernel: kernel,
                                                                context: context())
        let tree = try #require(outputs.trees["placements"])
        #expect(tree.isCulled && tree.itemCount == 0)
    }

    @Test func aTreeOfPointsIsATreeOfPlacementsAtTheSamePaths() async throws {
        let rows = try #require(DataTree(depth: 2, branches: [.list((0..<3).map(point)), .list((3..<5).map(point))]))
        let culled = rows.keepingItems { leaf, _, k in !(leaf.path == TreePath([0]) && k == 1) }
        let outputs = try await PointsToPlacementsNode.evaluate(inputs(["points": Value(culled)]), kernel: kernel, context: context())
        let tree = try #require(outputs.trees["placements"])
        #expect(tree.depth == 2)
        #expect(tree.leaves.map(\.positions) == [[0, 2], [0, 1]], "{0;2} is still {0;2}")
        #expect(Value(tree).planes?.map(\.origin.x) == [0, 40, 60, 80])
    }

    @Test func aDirectionPerRowIsMatchedToTheRowsOfPoints() async throws {
        let rows = try #require(DataTree(depth: 2, branches: [.list((0..<2).map(point)), .list((2..<4).map(point))]))
        let facing = try #require(DataTree(depth: 2, branches: [.list([.vector(.unitX)]), .list([.vector(.unitY)])]))
        let outputs = try await PointsToPlacementsNode.evaluate(inputs(["points": .tree(rows), "direction": .tree(facing)]),
                                                                kernel: kernel, context: context())
        let tree = try #require(outputs.trees["placements"])
        let planes = try #require(Value(tree).planes)
        #expect(zip(planes.map(\.normal), [Vector3.unitX, .unitX, .unitY, .unitY]).allSatisfy { isClose($0, $1) })
    }

    @Test func aZeroDirectionOnACulledPointNamesItsPath() async throws {
        let directions = try #require(DataTree.culledList([.vector(.unitZ), .vector(.zero)], at: [0, 5]))
        let given = inputs(["points": .list((0..<6).map(point)), "direction": Value(directions)])
        await #expect(throws: NodeError.invalidValue("The direction of placement {5} can't be zero.")) {
            _ = try await PointsToPlacementsNode.evaluate(given, kernel: kernel, context: context())
        }
    }

    @Test func aPlainListOfPointsStillMakesAPlainListOfPlacements() async throws {
        let outputs = try await PointsToPlacementsNode.evaluate(inputs(["points": .list((0..<3).map(point))]), kernel: kernel,
                                                                context: context())
        let tree = try #require(outputs.trees["placements"])
        #expect(!tree.isCulled && tree.depth == 1 && tree.itemCount == 3)
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

/// Culling keeps paths (patterns spec §4, §6): an instance whose placement survived a cull keeps its path in its tags,
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
        let tree = try #require(outputs.trees["solids"])
        #expect(!tree.isCulled, "nothing was culled, so nothing is marked")
        #expect(try copies(outputs).map { items(of: $0) } == [[0], [1], [2]])
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
        let placed = try copies(outputs)
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

    // MARK: trees

    /// Two rows of three placements, 20 mm apart along x and 20 mm along y, with `culling` taken out as a Cull node would.
    func rows(culling drop: (DataTree.Leaf, Int) -> Bool = { _, _ in false }) throws -> Value {
        let branches = (0..<2).map { row in
            DataTree.list((0..<3).map { .plane(.through(Vector3(Double($0) * 20, Double(row) * 20, 0))) })
        }
        let tree = try #require(DataTree(depth: 2, branches: branches))
        return Value(tree.keepingItems { leaf, _, k in !drop(leaf, k) })
    }

    func paths(of solid: Solid) -> Set<[Int]> {
        Set(items(of: solid).compactMap { InstancePath.indices(ofItem: $0) })
    }

    @Test func aCulledTreeOfPlacementsKeepsEveryTreePath() async throws {
        let placements = try rows { leaf, k in leaf.path == TreePath([0]) && k == 1 }
        let outputs = try await HolePatternNode.evaluate(
            inputs(HolePatternNode.self, ["part": .one(.solid(try await plate())), "placements": placements]),
            kernel: kernel, context: context(HolePatternNode.self))
        let solid = try resultSolid(outputs)
        #expect(paths(of: solid) == [[0, 0], [0, 2], [1, 0], [1, 1], [1, 2]], "{0;2} is still {0;2}, and {0;1} is gone")
        #expect(outputs.warnings.isEmpty, "\(outputs.warnings)")
    }

    @Test func aWholeBranchCulledLeavesTheOtherBranchesNumbersAlone() async throws {
        let placements = try rows { leaf, _ in leaf.path == TreePath([0]) }
        let outputs = try await HolePatternNode.evaluate(
            inputs(HolePatternNode.self, ["part": .one(.solid(try await plate())), "placements": placements]),
            kernel: kernel, context: context(HolePatternNode.self))
        #expect(paths(of: try resultSolid(outputs)) == [[1, 0], [1, 1], [1, 2]])
    }

    @Test func placeOnACulledTreeGivesCopiesBackInTheSameGaps() async throws {
        let placements = try rows { leaf, k in leaf.path == TreePath([1]) && k == 0 }
        let outputs = try await PlaceNode.evaluate(
            inputs(PlaceNode.self, ["tool": .one(.solid(try await block())), "placements": placements]),
            kernel: kernel, context: context(PlaceNode.self))
        let tree = try #require(outputs.trees["solids"])
        #expect(tree.leaves.map(\.positions) == [[0, 1, 2], [1, 2]])
        #expect(try copies(outputs).map { paths(of: $0) } == [[[0, 0]], [[0, 1]], [[0, 2]], [[1, 1]], [[1, 2]]])
    }

    @Test func aSizePerRowAndACullTogetherReadTheRowsSizeAtTheInstancesPlace() async throws {
        let placements = try rows { _, k in k == 0 }
        let diameters = try #require(DataTree(depth: 2, branches: [.list([.number(4)]), .list([.number(-1)])]))
        let given = inputs(HolePatternNode.self, [
            "part": .one(.solid(try await plate())), "placements": placements, "diameter": Value(diameters),
        ])
        var message: String?
        do {
            _ = try await HolePatternNode.evaluate(given, kernel: kernel, context: context(HolePatternNode.self))
        } catch let error as NodeError {
            message = error.message
        }
        #expect(message == "Hole {1;1}: the diameter must be greater than 0 mm.", "got \(String(describing: message))")
    }
}
```


- [ ] **Step 2: Run them**

Run: `swift test --filter "InstanceGridCullTests|CulledInstancesTests|PointsToPlacementsCullTests" 2>&1 | grep -v 'ld: warning'`

Expected: FAIL. The three suites build and run, and `Test run with 42 tests in 3 suites failed` with 37 issues (`InstanceGridCullTests` 13, `CulledInstancesTests` 17, `PointsToPlacementsCullTests` 7): a culled list is still read by rank (`grid.paths == [[1], [3]]` fails) and Points to Placements still returns lists, so `outputs.trees["placements"]` is `nil`.

- [ ] **Step 3: Write the implementation**

This replaces the whole file ("Create" writes a whole file).

Create `Sources/CreatorNodes/Patterns/InstanceGrid.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// The instances a pattern node makes, and what each one's inputs are (patterns spec §3 and §5, with trees). The
/// inputs are matched by the same rules broadcasting uses, and the node still makes one kernel call for all of them:
///
/// - The deepest input sets the shape: when all are flat, the longest sets the number of instances and a shorter list
///   repeats its last item (as before trees); when one is a tree, its items are the instances and the instance at
///   `{r;c}` is item `c` of branch `r`. Ties go to the first name asked for, which is the placements.
/// - A flat list applies to every branch and matches that branch's items (a flat list of 8 against 3 rows of 8).
/// - A tree as deep as the shape is matched level by level, a shorter side repeating its last branch (a tree of three
///   one-item branches gives each of three rings one value: Graft a list of diameters).
/// - A tree of another depth is refused, naming both shapes, and so is a branch with no items to take from.
///
/// Any input with no items at all makes no instances, as an empty list always has.
///
/// Culling keeps paths (patterns spec §4): an instance is named by the place its placement had, not by its rank among the
/// survivors, so a branch or list that has had items taken out (`DataTree.isCulled`) makes exactly the instances it holds,
/// at the indices it kept; the gaps make none, and the output comes back with the same gaps (`tree(of:)`). The other inputs
/// are read at an instance's index: its own value if the input has one there, else the nearest one before it, else its first
/// (a plain list repeating its last item is the same rule). A culled list that is not the lead sets no number of instances,
/// however many survivors it holds, so a culled tail never comes back as repeats.
struct InstanceGrid {
    /// Each instance's indices in the tree: `[i]` for a flat list, `[r, c]` for item `c` of branch `r`.
    let paths: [[Int]]
    /// Each instance's tag item (`InstancePath.item(for:)`): its flat index for `[i]`, a packed negative number deeper.
    let items: [Int]
    private let shape: DataTree?
    /// The indices a culled flat lead keeps, so the output can be culled alike.
    private let culledIndices: [Int]?
    private let depth: Int
    private let columns: [SocketName: [Scalar]]

    var count: Int { paths.count }

    /// The instances of the inputs `names`, each read as a whole tree (`.tree` access, so a flat list arrives as a tree
    /// of depth 1 and a single value as a list of one).
    init(_ inputs: NodeInputs, _ names: [SocketName]) throws {
        try self.init(names.map { (name: $0, tree: try inputs.tree($0)) })
    }

    init(_ trees: [(name: SocketName, tree: DataTree)]) throws {
        guard var lead = trees.first else { throw NodeError.invalidValue("A pattern needs placements.") }
        for entry in trees where entry.tree.depth > lead.tree.depth { lead = entry }
        if trees.contains(where: { $0.tree.itemCount == 0 }) {
            (paths, items, shape, depth, columns) = ([], [], nil, lead.tree.depth, [:])
            culledIndices = lead.tree.depth == 1 && lead.tree.isCulled ? [] : nil
            return
        }
        let cells = lead.tree.depth == 1 ? try Self.flatCells(trees, lead: lead.tree) : try Self.treeCells(trees, lead: lead)
        var items: [Int] = []
        items.reserveCapacity(cells.count)
        for cell in cells {
            guard let item = InstancePath.item(for: cell.path) else {
                throw NodeError.invalidValue("Instance \(InstancePath.text(indices: cell.path)) can't be named: patterns take trees up "
                    + "to \(InstancePath.maximumDepth) levels deep, with branch numbers below \((InstancePath.maximumIndex + 1).display).")
            }
            items.append(item)
        }
        var columns: [SocketName: [Scalar]] = [:]
        let leaves = lead.tree.depth == 1 ? [] : lead.tree.leaves
        for entry in trees {
            columns[entry.name] = try Self.values(of: entry, matching: cells.map { ($0.leaf, $0.position, $0.path) }, leaves: leaves)
        }
        (self.paths, self.items, self.depth, self.columns) = (cells.map(\.path), items, lead.tree.depth, columns)
        shape = lead.tree.depth == 1 ? nil : lead.tree
        culledIndices = lead.tree.depth == 1 && lead.tree.isCulled ? lead.tree.itemPositions : nil
    }

    private typealias Cell = (path: [Int], leaf: Int, position: Int)

    /// The instances of flat inputs: a culled lead's own indices, else 0 up to the longest plain list (a culled list that
    /// is not the lead sets no number of instances).
    private static func flatCells(_ trees: [(name: SocketName, tree: DataTree)], lead: DataTree) throws -> [Cell] {
        guard lead.isCulled else {
            let count = trees.filter { !$0.tree.isCulled }.map(\.tree.itemCount).max() ?? 0
            try PatternLimit.check(count)
            return (0..<count).map { ([$0], 0, $0) }
        }
        try PatternLimit.check(lead.itemCount)
        return lead.itemPositions.map { ([$0], 0, $0) }
    }

    /// The instances of a tree lead: its items, each at the path of its branch and the index the item kept there.
    private static func treeCells(_ trees: [(name: SocketName, tree: DataTree)],
                                  lead: (name: SocketName, tree: DataTree)) throws -> [Cell] {
        for entry in trees where entry.tree.depth != 1 && entry.tree.depth != lead.tree.depth {
            throw NodeError.invalidValue("“\(entry.name)” (\(entry.tree.shapeText)) and “\(lead.name)” "
                + "(\(lead.tree.shapeText)) are nested differently. Use a flat list, or trees of the same depth.")
        }
        try PatternLimit.check(lead.tree.itemCount)
        var cells: [Cell] = []
        for (leaf, entry) in lead.tree.leaves.enumerated() {
            for position in entry.positions { cells.append((entry.path.indices + [position], leaf, position)) }
        }
        return cells
    }

    /// The input's item for each cell: the one at the cell's own place in the branch it is matched with.
    private static func values(of entry: (name: SocketName, tree: DataTree), matching cells: [(leaf: Int, position: Int, path: [Int])],
                               leaves: [DataTree.Leaf]) throws -> [Scalar] {
        let tree = entry.tree
        if tree.depth == 1 {
            let column = Column(tree)
            return cells.map { column.scalar(at: $0.position) }
        }
        var byLeaf: [Int: Column] = [:]
        var result: [Scalar] = []
        result.reserveCapacity(cells.count)
        for cell in cells {
            if byLeaf[cell.leaf] == nil {
                byLeaf[cell.leaf] = Column(try branch(of: entry, at: leaves[cell.leaf].path))
            }
            if let column = byLeaf[cell.leaf] { result.append(column.scalar(at: cell.position)) }
        }
        return result
    }

    /// The branch a leaf is matched with: level by level, a shorter side repeating its last branch.
    private static func branch(of entry: (name: SocketName, tree: DataTree), at path: TreePath) throws -> DataTree {
        var branch = entry.tree
        for index in path.indices {
            let branches = branch.branches
            guard let last = branches.indices.last else { throw empty(entry.name, path) }
            branch = branches[min(index, last)]
        }
        guard !branch.items.isEmpty else { throw empty(entry.name, path) }
        return branch
    }

    /// One input's items in the branch an instance is matched with, and the places they have there.
    private struct Column {
        let items: [Scalar]
        /// The places of a culled branch's items; `nil` for a plain one, whose items are 0, 1, 2….
        let places: [Int]?

        init(_ branch: DataTree) {
            items = branch.items
            places = branch.culledPositions
        }

        /// The item at `place`: a plain branch repeats its last item past the end; a culled one gives the item that has
        /// that place, else the nearest one before it, else its first.
        func scalar(at place: Int) -> Scalar {
            guard let places else { return items[min(place, items.count - 1)] }
            var (low, high) = (0, places.count)
            while low < high {
                let middle = (low + high) / 2
                if places[middle] <= place { low = middle + 1 } else { high = middle }
            }
            return items[max(low - 1, 0)]
        }
    }

    private static func empty(_ name: SocketName, _ path: TreePath) -> NodeError {
        NodeError.invalidValue("“\(name)” has no items for the branch \(path).")
    }

    /// A tree holding `scalars`, one per instance, in the shape the instances came in: a flat list for a flat pattern (a culled
    /// list, at the same indices, when the placements were culled), else the tree (the empty branches and culled gaps too) the
    /// instances sit in.
    func tree(of scalars: [Scalar]) -> DataTree {
        if let shape { return shape.replacingItems(scalars) ?? .empty(depth: depth) }
        if let culledIndices { return DataTree.culledList(scalars, at: culledIndices) ?? .list(scalars) }
        return depth > 1 && scalars.isEmpty ? .empty(depth: depth) : .list(scalars)
    }

    // MARK: Typed inputs, one value per instance

    func numbers(_ name: SocketName) throws -> [Double] {
        try typed(name, .number) { if case .number(let value) = $0 { value } else { nil } }
    }

    func integers(_ name: SocketName) throws -> [Int] {
        try typed(name, .integer) { if case .integer(let value) = $0 { value } else { nil } }
    }

    func bools(_ name: SocketName) throws -> [Bool] {
        try typed(name, .bool) { if case .bool(let value) = $0 { value } else { nil } }
    }

    func vectors(_ name: SocketName) throws -> [Vector3] {
        try typed(name, .vector) { if case .vector(let value) = $0 { value } else { nil } }
    }

    func planes(_ name: SocketName) throws -> [Plane] {
        try typed(name, .plane) { if case .plane(let value) = $0 { value } else { nil } }
    }

    func solids(_ name: SocketName) throws -> [Solid] {
        try typed(name, .solid) { if case .solid(let value) = $0 { value } else { nil } }
    }

    private func typed<T>(_ name: SocketName, _ type: SocketType, _ extract: (Scalar) -> T?) throws -> [T] {
        try (columns[name] ?? []).map { scalar in
            guard let value = extract(scalar) else { throw NodeError.typeMismatch(name, expected: type) }
            return value
        }
    }
}
```


This replaces the whole file ("Create" writes a whole file).

Create `Sources/CreatorNodes/Patterns/PointsToPlacementsNode.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Points in, placements out (patterns spec §3): each point becomes a plane through it facing `direction`, with the
/// x axis Plane from Face would give (`FacePlane`: world X projected onto the plane, else world Y). It moves graphs
/// built on Grid Points over to Place without redrawing them. Points and directions are read whole and matched as
/// `InstanceGrid` matches placements (the longer flat list sets the number of placements and the shorter repeats its last
/// item; a tree of points gives a tree of placements), and the placements come back in the shape of the points with the
/// same paths, so a cull anywhere before this node (on the points, say) keeps the paths of the instances that stay: a
/// culled list of points is a culled list of placements at the same indices.
public enum PointsToPlacementsNode: NodeDefinition {
    public static let typeID = "creator.pointsToPlacements"
    public static let displayName = "Points to Placements"
    public static let category = NodeCategory.patterns
    public static let inputs = [
        SocketSpec("points", .vector, access: .tree),
        SocketSpec("direction", .vector, access: .tree, defaultValue: .vector(.unitZ)),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static let inspector = [InspectorSection(title: "Facing", controls: [.vector("direction")])]

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let grid = try InstanceGrid(inputs, ["points", "direction"])
        guard grid.count > 0 else { return NodeOutputs(trees: ["placements": grid.tree(of: [])]) }
        let (points, directions) = (try grid.vectors("points"), try grid.vectors("direction"))
        var planes: [Scalar] = []
        planes.reserveCapacity(grid.count)
        for index in 0..<grid.count {
            guard let normal = directions[index].normalized else {
                throw NodeError.invalidValue("The direction of placement \(InstancePath.text(grid.items[index])) can't be zero.")
            }
            planes.append(.plane(FacePlane.plane(origin: points[index], normal: normal)))
        }
        return NodeOutputs(trees: ["placements": grid.tree(of: planes)])
    }
}
```


- [ ] **Step 4: Run the task's tests, then the existing pattern suites**

Run: `swift test --filter "InstanceGridCullTests|CulledInstancesTests|PointsToPlacementsCullTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

Run: `swift test --filter "HolePatternNodeTests|BossPatternNodeTests|SlotPatternNodeTests|PatternFeatureNodeTests|PlaceNodeTests|PlaceTreeTests|InstanceGridTests|PointsToPlacementsNodeTests|PatternTreePickTests|PatternPickStabilityTests|GroupPatternNamingTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, untouched.

- [ ] **Step 5: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > "${TMPDIR:-/tmp}/vtest.log" 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,814 = master + 73** (+42 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(7a-3b): InstanceGrid keeps the paths of culled items; Points to Placements takes its points as a tree"
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
- Produces: `CullPatternNode` (`creator.cullPattern`, inputs `tree` (any, tree), `keep` (bool list, optional), `scope` (integer: Per branch, Overall; default Per branch), output `tree`; setting `NodeSetting.cullPattern`, default `"1 0"`);
`CullMask.parse(_:)`; test fixtures `TreeSource`, `Harness.source(count:rows:)`, `Harness.wire(_ source:to:_:)`, `EvaluationReport.tree(_:_:)`, `EvaluationReport.positions(_:_:)`.

The first node, and the shared test fixtures (`TreeSource`, `Harness.source(count:rows:)`, `EvaluationReport.positions`). The mask is the saved text
`cullPattern` (`1 0`, `T F T`), or a wired `keep` list; it repeats across each branch over the items the branch has now (User decision U2), or,
with `scope` Overall, runs on along the whole tree in order (U16: it is how one mask reaches the cells of a `{row;column;0}` tree), and
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
    func run(_ pattern: String, count: Int = 6, rows: Int? = nil,
             overall: Bool = false) async throws -> (report: EvaluationReport, cull: Node) {
        var h = Harness()
        let source = h.source(count: count, rows: rows)
        let cull = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text(pattern), "scope": .integer(overall ? 1 : 0)])
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

    @Test func overallTheMaskRunsOnFromBranchToBranch() async throws {
        let (report, cull) = try await run("1 0 0", count: 8, rows: 4, overall: true)
        #expect(report.positions(cull) == [[0, 3], [2]], "items 0, 3 and 6 of the tree: {0;0}, {0;3} and {1;2}")
        let (flat, flatCull) = try await run("1 0", count: 6, overall: true)
        #expect(flat.positions(flatCull) == [[0, 2, 4]], "on a flat list both scopes say the same")
    }

    @Test func overallCountsTheItemsLeftByAnEarlierCull() async throws {
        var h = Harness()
        let source = h.source(count: 6, rows: 2)
        let first = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])  // keeps {0;0}, {1;0}, {2;0}
        let second = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0"), "scope": .integer(1)])
        h.wire(source, to: first, "tree")
        h.wire(first, "tree", to: second, "tree")
        let report = try await h.run([second])
        #expect(report.positions(second) == [[0], [], [0]], "the three survivors are counted 1 0 1; the middle one goes")
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

    @Test func aScopeThatIsNeitherIsRefused() async throws {
        var h = Harness()
        let source = h.source(count: 4)
        let cull = h.add(CullPatternNode.self, ["scope": .integer(5)])
        h.wire(source, to: cull, "tree")
        let report = try await h.run([cull])
        #expect(report.error(cull) == "Choose Per branch or Overall for “scope”.")
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
        let slots: [SocketName: NodeInputs.Slot] = [
            "tree": .tree(tree), "keep": .list([.bool(false), .bool(true)]), "scope": .item(.integer(0)),
        ]
        let outputs = try await evaluate(NodeInputs(item: 0, slots: slots))
        #expect(try #require(outputs.trees["tree"]).itemPositions == [1, 3])
    }

    @Test func anEmptyWiredListIsRefused() async throws {
        let inputs = NodeInputs(item: 0, slots: ["tree": .tree(.list([.integer(1)])), "keep": .list([]), "scope": .item(.integer(0))])
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
        #expect(CullPatternNode.inputs.first { $0.name == "scope" }?.defaultValue == .integer(0), "per branch, as for rows")
        #expect(CullPatternNode.category == .patterns)
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
        #expect(names == [
            "Linear Pattern", "Grid Pattern", "Circular Pattern", "Curve Pattern", "Place", "Points to Placements", "Hole Pattern",
            "Boss / Pin Pattern", "Slot Pattern", "Pattern Feature",
        ])
```

with:

```swift
        #expect(names == [
            "Linear Pattern", "Grid Pattern", "Circular Pattern", "Curve Pattern", "Place", "Points to Placements", "Hole Pattern",
            "Boss / Pin Pattern", "Slot Pattern", "Pattern Feature",
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
/// culls every third. Per branch (the default) the mask starts again at the first item of each branch; Overall it runs on
/// along the whole tree, branch after branch, which is how one mask reaches every other cell of a `{row;column;0}` tree whose
/// branches hold one item each (User decision U16). Either way it counts the items there are now, so a second Cull Pattern
/// after a first works on what is left. Culling keeps paths: a survivor keeps the index it had, so
/// `{3}` is still `{3}` when `{1}` is gone and a pick on it follows it (§6). The mask is a saved text setting, or a list of
/// true and false wired into `keep`, which takes its place.
public enum CullPatternNode: NodeDefinition {
    public static let typeID = "creator.cullPattern"
    public static let displayName = "Cull Pattern"
    public static let category = NodeCategory.patterns
    public static let scopes = ["Per branch", "Overall"]
    public static let inputs = [
        SocketSpec("tree", .any, access: .tree),
        SocketSpec("keep", .bool, access: .list, optional: true),
        SocketSpec("scope", .integer, defaultValue: .integer(0)),
    ]
    public static let outputs = [SocketSpec("tree", .any)]
    public static let defaultSettings: [SocketName: ConstantValue] = [NodeSetting.cullPattern: .text("1 0")]
    public static let inspector = [
        InspectorSection(title: "Pattern", controls: [.text(NodeSetting.cullPattern), .segmented("scope", options: scopes)]),
    ]

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
        // Where each branch's first item falls in the mask: the start for every branch, or after the items before it.
        var starts = Array(repeating: 0, count: tree.leaves.count)
        if try inputs.choice("scope", options: scopes) == 1 {
            var before = 0
            for (ordinal, leaf) in tree.leaves.enumerated() {
                starts[ordinal] = before
                before += leaf.items.count
            }
        }
        return NodeOutputs(trees: ["tree": tree.keepingItems { _, ordinal, k in mask[(starts[ordinal] + k) % mask.count] }])
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
swift test > "${TMPDIR:-/tmp}/vtest.log" 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,830 = master + 89** (+16 in this task; the Swift Testing total counts a parameterised test once).

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
- Test: `Tests/CreatorNodesTests/Variation/CulledTreePickTests.swift` (new)
- Test: `Tests/CreatorEditorTests/PatternsLibraryTests.swift` (modify)
- Test: `Tests/CreatorNodesTests/OutputNodeTests.swift` (modify)

**Interfaces:**

- Consumes: Tasks 2–4; `EdgesByTagNode`, `FilletNode`, `HolePatternNode`, `GridPatternNode`, `PartitionNode`, `PointsToPlacementsNode`, `PatternPlate`, `OCCTKernel` (tests).
- Produces: `CullIndexNode` (`creator.cullIndex`, inputs `tree` (any, tree), `indices` (number list, optional), output `tree`; setting `NodeSetting.cullIndices`, default `""`);
`CullTargets` (parses `1, 4, {0;3}`, `drops(_:at:depth:)`, `unmatched(in:)`).

Indices and paths such as `{0;3}` come out of a list or tree; everything else keeps its path. The same task adds the spec §9 naming tests. `CulledPickTests`
works on a single flat list (Grid Points and Points to Placements, with the Cull Index either after Points to Placements or before it on the Grid Points,
then a Hole Pattern and a fillet on a picked rim) and `CulledTreePickTests` on a tree of placements (a Grid Pattern's rows, or Grid Points cut into rows
by Partition, culled before Points to Placements): a pick on one instance survives a cull of another and does not move to a neighbour; a pick on a culled
instance warns "Instance {1;1} no longer exists…" naming its path and selects nothing; a whole branch culled names every pick on it; undoing the cull
brings the pick back. If culling changed a survivor's path, `aPickOnOneInstanceSurvivesACullOfAnother` and `aCullLeavesTheSurvivorsAtTheirIndices` fail,
which is the bug to avoid. These tests pass unchanged after 7a-layouts' remaining tasks merge (they read only `PatternPlate`'s `h`, `plate`, `grid` and `placements`).

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
/// Placements → Cull Index), so an instance's path is `{i}`, its index in the list; `CulledTreePickTests` does the same over
/// a tree of placements.
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


Create `Tests/CreatorNodesTests/Variation/CulledTreePickTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import Testing

/// Patterns spec §6 and §9 for culling a tree of placements: an instance is named by its tree path, culling keeps the path of
/// every survivor, a pick on one survives a cull of another and does not move to a neighbour, and a pick on a culled instance
/// warns, naming its path, and selects nothing.
struct CulledTreePickTests {
    /// Where the cull sits: after a Grid Pattern's tree of placements, or on the Grid Points before Points to Placements.
    enum Stage: CaseIterable, Sendable {
        case afterLayout, beforePlacements
    }

    /// 3 × 2 Ø5 holes 15 mm apart in rows of 3 (`{row;column}`), a Cull Index on them, a Hole Pattern, an Edges by Tag on the
    /// result and a Fillet on its edges.
    struct Fixture {
        var plate: PatternPlate
        let cull: Node, holes: Node, rule: Node, fillet: Node

        init(_ stage: Stage = .afterLayout, culler: any NodeDefinition.Type = CullIndexNode.self) {
            plate = PatternPlate(columns: 3, rows: 2, spacingX: 15, spacingY: 15)
            cull = plate.h.add(culler)
            holes = plate.h.add(HolePatternNode.self, ["diameter": .number(5), "depth": .number(6)])
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            switch stage {
            case .afterLayout:
                let layout = plate.h.add(GridPatternNode.self, ["countX": .integer(3), "countY": .integer(2),
                                                                "spacingX": .number(15), "spacingY": .number(15),
                ])
                plate.h.wire(layout, "placements", to: cull, "tree")
                plate.h.wire(cull, "tree", to: holes, "placements")
            case .beforePlacements:
                let rows = plate.h.add(PartitionNode.self, ["size": .integer(3)])
                let placed = plate.h.add(PointsToPlacementsNode.self)
                plate.h.wire(plate.grid, "points", to: rows, "tree")
                plate.h.wire(rows, "tree", to: cull, "tree")
                plate.h.wire(cull, "tree", to: placed, "points")
                plate.h.wire(placed, "placements", to: holes, "placements")
            }
            rule = plate.h.add(EdgesByTagNode.self)
            plate.h.wire(holes, "solid", to: rule, "solid")
            fillet = plate.h.add(FilletNode.self, ["radius": .number(0.5)])
            plate.h.wire(rule, "edges", to: fillet, "edges")
        }

        /// Culls what `text` names (Cull Index's setting) or keeps what it says (Cull Pattern's).
        mutating func cull(_ text: String) {
            let setting = plate.h.nodes[cull.id]?.typeID == CullPatternNode.typeID ? NodeSetting.cullPattern : NodeSetting.cullIndices
            plate.h.set(cull, setting, .text(text))
        }

        /// The tag of the bore of the hole at `path`, the way Hole Pattern names it.
        func bore(_ path: [Int]) -> TopoTag {
            TopoTag(node: NodeID.instanceScoped([holes.id, holes.id]), item: InstancePath.item(for: path) ?? -1, role: .side(segment: 1))
        }

        /// The rim of the hole at `path` on the plate's top.
        func rim(of path: [Int], in solid: Solid) -> EdgeInfo? {
            let top = TopoTag(node: plate.plate.id, item: 0, role: .endCap)
            return solid.topology.edges.first { edge in
                guard edge.kind == .circle, !edge.isSeam, edge.faces.count == 2 else { return false }
                let sides = edge.faces.compactMap { solid.topology.face($0) }
                return sides.contains { $0.tags.contains(bore(path)) } && sides.contains { $0.tags.contains(top) }
            }
        }

        /// Picks the rims of the holes at `paths` on the rule, from a run with nothing culled.
        mutating func pick(_ paths: [[Int]], kernel: any Kernel) async throws {
            let culled = plate.h.nodes[cull.id]?.typeID == CullPatternNode.typeID
            cull(culled ? "1" : "")
            let solid = try onlySolid(try await plate.h.run([holes], kernel: kernel), holes)
            let edges = try paths.map { try #require(rim(of: $0, in: solid)).id }
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

        func touches(_ path: [Int], _ edge: EdgeInfo, in solid: Solid) -> Bool {
            edge.faces.compactMap { solid.topology.face($0) }.contains { $0.tags.contains(bore(path)) }
        }

        /// The paths of the holes the Hole Pattern made.
        func holePaths(_ report: EvaluationReport) throws -> Set<[Int]> {
            let solid = try onlySolid(report, holes)
            let items = solid.topology.faces.flatMap(\.tags).filter(\.node.isInstanceQualified).map(\.item)
            return Set(items.compactMap { InstancePath.indices(ofItem: $0) })
        }
    }

    @Test(arguments: ["0", "2", "{0;0}", "{1;0}", "{0}", "0, {1;2}"], Stage.allCases)
    func aPickOnOneInstanceSurvivesACullOfAnother(_ cull: String, _ stage: Stage) async throws {
        let kernel = OCCTKernel()
        var f = Fixture(stage)
        try await f.pick([[1, 1]], kernel: kernel)
        let before = try f.selected(try await f.plate.h.run([f.rule], kernel: kernel))
        f.cull(cull)
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(report.isOK(f.rule) && report.isOK(f.fillet), "after culling \(cull) \(stage): \(String(describing: report.state(f.rule)))")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { f.touches([1, 1], $0, in: solid) }, "still the rim of {1;1}")
        #expect(isClose(try f.center(of: try #require(edges.first)), try f.center(of: try #require(before.edges.first))),
                "the same physical hole: a cull never moves a pick to a neighbour")
    }

    @Test(arguments: Stage.allCases)
    func aCullLeavesTheSurvivorsAtTheirTreePaths(_ stage: Stage) async throws {
        let kernel = OCCTKernel()
        var f = Fixture(stage)
        f.cull("1")
        let report = try await f.plate.h.run([f.holes], kernel: kernel)
        #expect(try f.holePaths(report) == [[0, 0], [0, 2], [1, 0], [1, 2]], "{0;2} and {1;2}, not {0;1} and {1;1}: \(stage)")
        #expect(report.isOK(f.holes), "a cull never warns")
    }

    @Test(arguments: ["{1;1}", "1", "{1}"], Stage.allCases)
    func aPickOnACulledPathWarnsNamingItAndSelectsNothing(_ cull: String, _ stage: Stage) async throws {
        let kernel = OCCTKernel()
        var f = Fixture(stage)
        try await f.pick([[1, 1]], kernel: kernel)
        f.cull(cull)
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instance {1;1} no longer exists, so the edge picked on it isn't selected.", "\(cull) \(stage)")
        #expect(try f.selected(report).edges.isEmpty, "never a neighbour's rim")
    }

    @Test func aWholeBranchCulledNamesEveryPickOnIt() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([[0, 0], [0, 2], [1, 1]], kernel: kernel)
        f.cull("{0}")
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instances {0;0} and {0;2} no longer exist, so the edges picked on them aren't selected.")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { f.touches([1, 1], $0, in: solid) })
    }

    @Test func aPickComesBackWhenTheCullIsUndone() async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([[1, 1]], kernel: kernel)
        f.cull("1")
        _ = try await f.plate.h.run([f.rule], kernel: kernel)
        f.cull("")
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.isOK(f.rule))
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { f.touches([1, 1], $0, in: solid) })
    }

    @Test func aCullPatternKeepsTheTreePathsOfTheItemsItKeeps() async throws {
        let kernel = OCCTKernel()
        var f = Fixture(.afterLayout, culler: CullPatternNode.self)
        try await f.pick([[1, 2], [1, 1]], kernel: kernel)
        f.cull("1 0")
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(try f.holePaths(try await f.plate.h.run([f.holes], kernel: kernel)) == [[0, 0], [0, 2], [1, 0], [1, 2]])
        #expect(report.warning(f.rule) == "Instance {1;1} no longer exists, so the edge picked on it isn't selected.")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { f.touches([1, 2], $0, in: solid) }, "{1;2} keeps its place")
    }

    @Test func aPickSurvivesACullAndARowLengthChangeTogether() async throws {
        let kernel = OCCTKernel()
        var f = Fixture(.beforePlacements)
        try await f.pick([[1, 1]], kernel: kernel)
        f.cull("0")
        f.plate.h.set(f.plate.grid, "spacingX", .number(18))
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(report.isOK(f.rule) && report.isOK(f.fillet))
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { f.touches([1, 1], $0, in: solid) })
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
            "Cull Pattern",
        ])
```

with:

```swift
            "Cull Pattern", "Cull Index",
        ])
```


- [ ] **Step 2: Run them**

Run: `swift test --filter "CullIndexNodeTests|CulledPickTests|CulledTreePickTests|OutputNodeTests|PatternsLibraryTests|CatalogTests|BuiltInNodesInspectorTests" 2>&1 | grep -v 'ld: warning'`

Expected: FAIL, the tests do not build (`cannot find 'CullIndexNode' in scope`).

- [ ] **Step 3: Write the implementation**

Create `Sources/CreatorNodes/Patterns/Variation/CullIndexNode.swift`:

```swift
import CreatorGraph
import CreatorKernel
import Foundation

/// Takes listed items out of a list or tree (patterns spec §4). An index such as `3` drops that place from every branch (the
/// place within the branch: in a tree whose branches hold one item each, like a Face Pattern's `{row;column;0}` cells, only 0
/// is a place, so name cells by path); a path such as `{0;3}` drops one item, and a shorter one such as `{1}` drops everything
/// under it. They go in the saved text
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
/// `{1;3}`, …; always the last level, so on `{row;column;0}` cells only `0` names anything), and paths, which name one item (`{0;3}`) or, when they stop short of the items, everything under them (`{1}`
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

Run: `swift test --filter "CullIndexNodeTests|CulledPickTests|CulledTreePickTests|OutputNodeTests|PatternsLibraryTests|CatalogTests|BuiltInNodesInspectorTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

- [ ] **Step 5: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > "${TMPDIR:-/tmp}/vtest.log" 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,861 = master + 120** (+31 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(7a-3b): Cull Index, and picks that survive a cull of another instance (flat and in rows)"
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
        #expect(BuiltInNodes.all.count == 47)
```

with:

```swift
        #expect(BuiltInNodes.all.count == 48)
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
.feature: 2, .patterns: 12, .lists: 7
```

with:

```swift
.feature: 2, .patterns: 13, .lists: 7
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
swift test > "${TMPDIR:-/tmp}/vtest.log" 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,889 = master + 148** (+28 in this task; the Swift Testing total counts a parameterised test once).

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

Drop N or a fraction, overall (the default) or per branch (Key decision 6, User decision U16: per branch on branches of one item drops everything). The pinned results in the tests were worked out directly from the generator
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
        let (report, node) = try await reduce(["scope": .integer(0), "seed": .integer(7)], count: 12, rows: 4)
        #expect(report.positions(node) == [[0, 1, 2], [1, 2, 3], [0, 2, 3]])
        let (other, otherNode) = try await reduce(["scope": .integer(0), "seed": .integer(8)], count: 12, rows: 4)
        #expect(other.positions(otherNode) == [[0, 1, 3], [1, 2, 3], [0, 2, 3]])
    }

    @Test func overallTheWholeTreeLosesThreeWhereverTheyAre() async throws {
        let (report, node) = try await reduce(["count": .integer(3), "scope": .integer(1), "seed": .integer(7)], count: 12, rows: 4)
        #expect(report.positions(node) == [[1, 2], [0, 1, 2, 3], [0, 2, 3]])
    }

    @Test func theDefaultDropsOneItemFromTheWholeTreeNotOnePerBranch() async throws {
        let (report, node) = try await reduce([:], count: 12, rows: 4)
        #expect(report.tree(node)?.itemCount == 11)
        let (ones, onesNode) = try await reduce([:], count: 6, rows: 1)
        #expect(ones.tree(onesNode)?.itemCount == 5, "branches of one item each are not emptied (User decision U16)")
    }

    @Test func theScopeStartsOnOverall() {
        #expect(RandomReduceNode.inputs.first { $0.name == "scope" }?.defaultValue == .integer(1))
    }

    @Test func perBranchOnBranchesOfOneItemDropsEveryItemAsItSays() async throws {
        let (report, node) = try await reduce(["scope": .integer(0)], count: 6, rows: 1)
        #expect(report.tree(node)?.itemCount == 0, "one from each branch of one is all of them: choose Overall for such a tree")
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
        let (report, node) = try await reduce(["by": .integer(1), "fraction": .number(0.5), "scope": .integer(0)], count: 12, rows: 4)
        #expect(report.positions(node)?.map(\.count) == [2, 2, 2])
    }

    @Test func aCountLargerThanTheBranchDropsItAllWithoutAWarning() async throws {
        let (report, node) = try await reduce(["count": .integer(9), "scope": .integer(0)], count: 6, rows: 3)
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
        #expect(BuiltInNodes.all.count == 48)
```

with:

```swift
        #expect(BuiltInNodes.all.count == 49)
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
.feature: 2, .patterns: 13, .lists: 7
```

with:

```swift
.feature: 2, .patterns: 14, .lists: 7
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

/// Drops items at random (patterns spec §4): a count or a fraction, from the whole tree (the default) or from each branch.
/// Overall is the default because it does the same at every depth: per branch, a tree whose branches hold one item each (a
/// Face Pattern's `{row;column;0}` cells) loses every item (User decision U16). It is always
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
        SocketSpec("scope", .integer, defaultValue: .integer(1)),
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
swift test > "${TMPDIR:-/tmp}/vtest.log" 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,906 = master + 165** (+17 in this task; the Swift Testing total counts a parameterised test once).

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

- Consumes: Tasks 1 and 2 (`mappingItems`); `Int.display`.
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
        #expect(BuiltInNodes.all.count == 49)
```

with:

```swift
        #expect(BuiltInNodes.all.count == 50)
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
.feature: 2, .patterns: 14, .lists: 7
```

with:

```swift
.feature: 2, .patterns: 15, .lists: 7
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
        let reals = shape.mappingItems { leaf, ordinal, k in
            let random = SeededRandom(seed: seed, stream: ordinal, purpose: .values)
            return .number(low + random.unit(at: leaf.positions[k]) * (high - low))
        }
        var trees: [SocketName: DataTree] = ["values": reals]
        let (first, last) = (low.rounded(.up), high.rounded(.down))
        if first <= last, abs(first) < 1e15, abs(last) < 1e15 {
            let (lowest, span) = (Int(first), Int(last - first) + 1)
            trees["integers"] = shape.mappingItems { leaf, ordinal, k in
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
swift test > "${TMPDIR:-/tmp}/vtest.log" 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,922 = master + 181** (+16 in this task; the Swift Testing total counts a parameterised test once).

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
        #expect(BuiltInNodes.all.count == 50)
```

with:

```swift
        #expect(BuiltInNodes.all.count == 51)
```


In `Tests/CreatorNodesTests/OutputNodeTests.swift`, replace:

```swift
.feature: 2, .patterns: 15, .lists: 7
```

with:

```swift
.feature: 2, .patterns: 16, .lists: 7
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
        let shaken = tree.mappingItems { leaf, ordinal, k in
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
swift test > "${TMPDIR:-/tmp}/vtest.log" 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,934 = master + 193** (+12 in this task; the Swift Testing total counts a parameterised test once).

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

- Consumes: Tasks 1–9; `PatternPlate`, `GridPatternNode`, `OCCTKernel`.
- Produces: Nothing the code depends on.

One integration test of the six nodes together on a real plate on OCCT (a region cull, a random drop, Jitter, and a Hole Pattern whose diameters are
Random Values in the shape of what is left), once over a flat list of placements and once over a Grid Pattern's rows: the volume equals the plate minus
the holes the random choices made, each hole is named by the path its placement had (`{i}` or `{row;column}`), the same seed gives the same part and
another gives another without a warning. It passes as soon as it is written (it exercises Tasks 1–9), so there is no red step. Then the records:
CLAUDE.md, roadmap, the spec's Errata and the human checks (group VA). No benchmark is run or added.

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

        /// `inRows`: the placements are a Grid Pattern's tree of rows (`{row;column}`) instead of one flat list from Grid Points.
        init(seed: Int, inRows: Bool = false) {
            let origin = plate.h.add(VectorNode.self)
            let placements: Node
            if inRows {
                placements = plate.h.add(GridPatternNode.self, ["countX": .integer(4), "countY": .integer(3),
                                                                "spacingX": .number(15), "spacingY": .number(15),
                ])
            } else {
                placements = plate.placements
            }
            region = plate.h.add(CullByRegionNode.self, ["reference": .integer(1), "keep": .integer(1), "distance": .number(12)])
            reduce = plate.h.add(RandomReduceNode.self, ["count": .integer(3), "scope": .integer(1), "seed": .integer(seed)])
            jitter = plate.h.add(JitterNode.self, ["distance": .number(1), "turn": .number(30), "seed": .integer(seed)])
            diameters = plate.h.add(RandomValuesNode.self, ["min": .number(4), "max": .number(6), "seed": .integer(seed)])
            holes = plate.h.add(HolePatternNode.self, ["depth": .number(6)])
            plate.h.wire(origin, "vector", to: region, "point")
            plate.h.wire(placements, "placements", to: region, "placements")
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

    /// The same graph over a tree of placements: every hole is named by its tree path, and the survivors keep the path they had.
    @Test func theGraphOnATreeOfPlacementsNamesEveryHoleByItsOwnTreePath() async throws {
        let kernel = OCCTKernel()
        let p = Pipeline(seed: 5, inRows: true)
        let report = try await p.plate.h.run([p.holes], kernel: kernel)
        for node in [p.region, p.reduce, p.jitter, p.diameters, p.holes] {
            #expect(report.isOK(node), "\(node.name): \(String(describing: report.state(node)))")
        }
        let tree = try #require(report.tree(p.jitter, "placements"))
        let survivors = Set(tree.leaves.flatMap { leaf in leaf.positions.map { leaf.path.indices + [$0] } })
        #expect(survivors.count == 7, "12 placements, 2 culled by region, 3 dropped at random")
        #expect(survivors.isDisjoint(with: [[1, 1], [1, 2]]), "the two beside the middle are gone first")
        let solid = try onlySolid(report, p.holes)
        let items = solid.topology.faces.flatMap(\.tags).filter(\.node.isInstanceQualified).map(\.item)
        let paths = Set(items.compactMap { InstancePath.indices(ofItem: $0) })
        #expect(paths == survivors, "each hole is named by the tree path its placement had")
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
    `mappingItems(_:)` are how nodes cull and refill, `replacingItems(_:)` keeps the indices), and since a `.list` cannot say that it is
    a `Value.tree` of depth 1 (`Value(_:)` makes any other flat tree a `.list`). It broadcasts as a list: an item or list socket sees
    the survivors in order, as a rank, and a `tree` socket gets the tree whole with its indices, which is how `InstanceGrid` reads
    them. Reshaping nodes (Flatten, Graft, Partition, Path Mapper) renumber, as reshaping does, and List Item, Branch by Path and
    Tree Statistics count a culled list's survivors by rank; Cull Index alone names the places items had.
```


In `CLAUDE.md`, replace:

```markdown
- `CreatorNodes`: the 41 built-in node definitions (`BuiltInNodes.registry`: the slice's 26, Plane from Face and Sketch, the six
  `Patterns` nodes below,
```

with:

```markdown
- `CreatorNodes`: the 51 built-in node definitions (`BuiltInNodes.registry`: the slice's 26, Plane from Face and Sketch, the sixteen
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
    or a wired `keep` list, repeated along each branch, or with scope Overall along the whole tree, over the items it has now), Cull Index (indices and `{0;3}` paths as text, or
    wired numbers; an index or path names the place an item had before any cull; a bare index is a place within a branch, so on a
    `{row;column;0}` tree of one item per branch use paths), Cull by Region (placements inside or outside a
    profile, within or beyond a distance of a point, an edge set's straight and circular edges, or flat faces' planes;
    `RegionDistance`, `Profile2D.contains`), Random Reduce (`RandomReduction`; scope Overall by default), Random Values (reals and `integers`, in the shape of
    a tree or a count) and Jitter (`PlaneJitter`). Each takes a tree whole (`tree` access) and returns the same nesting with a
    culled list where items went. **All randomness is `SeededRandom`: SplitMix64, written out in the repo and pinned by
    `SeededRandomTests`, never the system's generator.** A draw depends on the seed, the item's branch ordinal (the stream) and its
    index in the branch, never on how many items there are, so a cull or a longer list reshuffles nothing; a seed never warns.
    Each node draws for its own `SeededRandom.Purpose` (the seed is mixed with a fixed per-node constant), so equal seeds on
    different nodes give unrelated numbers; the constants are pinned like the algorithm. `InstanceGrid` makes exactly the instances
    a culled list or branch of placements holds, at the paths they had (`{0;2}` is still `{0;2}` when `{0;1}` is gone: the tag
    item is `InstancePath.item(for:)` of the item's branch path and the index it kept), reads every other input at an instance's
    index (its own value, else the nearest one before it, else its first; a culled size or tool list that is not the lead sets no
    number of instances, however many survivors it holds) and gives Place's copies back in the placements' shape with the same
    gaps. Points to Placements takes `points` and `direction` whole and returns placements at the same paths, so a cull may sit
    anywhere before it. So a pick on one instance survives a cull of another and a pick on a culled one warns naming its path.
```


In `docs/superpowers/roadmap.md`, directly after:

```markdown
| 7a-2 (Place, shortcuts) merged; 7a-3 (layouts, naming by tree path) follows |
```

add:

```markdown
| 7a-3b | Variation and culling (7a spec §4): Cull Pattern, Cull Index, Cull by Region, Random Reduce, Random Values, Jitter; culls keep paths (a culled list in `Value.tree`, instances named by their original tree path), all randomness one seeded SplitMix64 (plan `2026-10-12-7a-variation.md`) | ✅ code done; human checks VA pending | Builds on 7a-3 part A's tree-path instances; merges after it |
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
  an item or list socket sees the survivors in order, as a rank, and a `tree` socket (every pattern node) gets the tree whole,
  indices included. The reshaping nodes (Flatten, Graft, Partition, Path Mapper) renumber, as reshaping does, and List Item,
  Branch by Path and Tree Statistics count a culled list's survivors by rank (List Item 2 of a list culled to {0, 2, 4} is the
  item at {4}); only Cull Index names the places items had. The tooltip and Data section say "culled" ("3, culled"). This
  amends the 7a-1 entry above: a depth-1 tree is a `.list` unless it is culled.
- **§4 Cull Pattern.** The mask is the saved text `cullPattern` (`1 0 1`, `T F T`, commas allowed; 1 or T keeps, 0 or F culls;
  default `1 0`), or a list of booleans wired into `keep`, which takes its place. `scope` (Per branch, the default; Overall) says where
  the mask starts: Per branch, it starts again at each branch; Overall, it runs on along the whole tree, branch after branch. Either way
  it counts the items there are now, so a second Cull Pattern works on what is left. On a tree whose branches hold one item each
  (`{row;column;0}`, Face Pattern's cells) Per branch keeps every cell for `1 0`; use Overall.
- **§4 Cull Index.** The saved text `cullIndices` holds indices (`3`: that place in every branch) and paths (`{0;3}`: one item;
  `{1}`: the whole second branch, which stays as an empty branch); numbers wired into `indices` add to them. An index or path
  names the place an item had before any cull. `{}` (the whole tree) refuses, pointing at Cull Pattern `0`. A path with more
  indices than the tree has levels refuses naming the shape;
  a path that names nothing warns once ("{0;9} names nothing in this tree."); an index past the end is not a problem. A bare index is a
  place within a branch (the last level), so on a tree whose branches hold one item each (`{row;column;0}`) `1` names nothing and
  `0` names every cell; name cells by path (`{0;1}`, `{0;1;0}`, `{1}` for a row).
- **§4 Cull by Region.** `reference` (Profile, Point, Edges, Face) says which of `profile`, `point`, `edges` or `faces` is
  measured from, `keep` (Inside or within, Outside or beyond) says which side stays, and `distance` is the limit for the other
  three. A placement is judged by its origin. A profile is a prism along its plane's normal; a point exactly on the outline or at
  exactly the distance counts as inside. Edges are measured exactly when straight or circular (another curve refuses, with the
  count); faces are measured to their **plane**, not their outline (a placement far beside a small flat face counts as near it),
  and a curved face refuses, with the count.
- **§4 Random Reduce.** `by` (Count, Fraction), `count`, `fraction`, `scope` (Overall, the default, or Per branch) and `seed`. Overall
  because Per branch on branches of one item (a Face Pattern's cells) drops every item. Each item's key is the
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
- **§6 Culled instances keep their path.** Place and the shortcuts make exactly the instances a culled list or branch of placements
  holds (a longer size list adds none), name each by the path its placement had (`{3}` in a flat list, `{1;2}` in rows: the
  placement's branch path and the index it kept, so a cull of `{1;1}` leaves `{1;2}` where it is), and read sizes and tools at that
  index (`InstanceGrid`: a culled size list gives instance `i` its value at `i`, else the nearest one before it, else its first).
  A pick on `{1;2}` therefore survives a cull of `{1;1}`, and a pick on a culled instance warns naming its path. Place outputs
  its copies in the placements' shape with the same gaps. A culled size or tool list never adds instances, however many survivors it
  holds, and one with everything culled makes none.
- **§3, §4 Points to Placements takes trees (the user's decision U15).** `points` and `direction` are read whole and matched as
  `InstanceGrid` matches placements, and the placements come back in the shape of the points with the same paths: a cull anywhere
  before the node (on the Grid Points, say) numbers the instances as a cull of the placements would, a tree of points gives a tree of
  placements, and a culled direction list is read at the instance's index. This replaces the 7a-2 behaviour of one run per branch.
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
  Jitter after Pattern Feature (the layouts come first in the section). Typing "cull" in the add-node palette finds three.
  Pinned: `thePatternsSectionHoldsThePatternNodes`. **Observed:**
- [ ] **VA-2 Cull Pattern.** The Pattern row shows `1 0` in a text field: every other hole is gone. Type `1 1 0` and press Return: every
  third is gone. Type `1 2`: the badge reads "“1 2” isn't a pattern. Use 1 to keep an item and 0 to cull it, like 1 0 1." The
  Edit menu names each change ("Change Cull pattern"). A long pattern scrolls inside the field. Set Scope to Overall with the
  placements in rows (Partition by 4): the mask runs on from one row into the next. Pinned: `CullPatternNodeTests`,
  `VariationSettingTests`. **Observed:**
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
  re-rolls them without a badge. Selecting Jitter shows no preview triads (previews are the layout nodes' only); record that nothing
  shows. Pinned: `JitterNodeTests`. **Observed:**
- [ ] **VA-10 The same file twice.** Save the graph, quit, reopen it: the holes are exactly where they were (the seed is saved, nothing
  else is random). On a second machine, if there is one, the same file gives the same part. Pinned: `SeededRandomTests`.
  **Observed:**
- [ ] **VA-11 Undo.** Undoing a pattern or a path edit puts the previous mask back and the holes with it; the Edit menu names the step
  ("Change Cull pattern", "Change Cull indices"). Pinned: `VariationSettingTests` (the names and the undo; the menu text is human).
  **Observed:**
- [ ] **VA-12 A cull before Points to Placements.** Move the Cull Index to sit between Grid Points and Points to Placements (wire Grid
  Points into it and it into Points to Placements) and type `0`: the first point's hole is gone and the others stay where they are,
  exactly as when the cull came after Points to Placements. Fillet the rim of the fifth hole (index 4): it stays on that hole when you
  change the cull to `1`, and with the cull changed to `4` the badge reads "Instance {4} no longer exists, so the edge picked on it
  isn't selected." Pinned: `CulledPickTests` (both stages), `pointsToPlacementsKeepsACulledListsIndices`. **Observed:**
- [ ] **VA-13 Equal seeds.** Random Reduce (Count 3, Seed 0) and Random Values (Seed 0, wired into the Hole Pattern's `diameter`): the
  holes Random Reduce drops are not simply the smallest ones. Pinned: `withTheSameSeedTheItemsRandomReduceDropsAreNotTheSmallestRandomValues`.
  **Observed:**
- [ ] **VA-14 A cull in rows keeps `{row;column}`.** Replace Grid Points and Points to Placements with a Grid Pattern (4 × 3, 15 mm)
  wired into the Cull Index. Fillet the rim of the hole in the second row, third column (`{1;2}`), then type `1` into the Cull
  Index: the second column goes from every row and the fillet stays on the same hole. Type `{1;2}`: the badge reads "Instance {1;2}
  no longer exists, so the edge picked on it isn't selected." and nothing else is filleted. Type `{1}`: the whole second row is gone,
  the other rows have not moved, and the same badge appears. Pinned: `CulledTreePickTests`. **Observed:**
- [ ] **VA-15 Points to Placements in rows.** Put a Partition (size 4) between Grid Points and Points to Placements: the placements come
  out as three rows of four (the Hole Pattern's holes are `{row;column}`), and a Cull Index `{1;2}` between Partition and
  Points to Placements leaves every other hole where it was. Pinned: `aTreeOfPointsIsATreeOfPlacementsAtTheSamePaths`,
  `CulledTreePickTests` (`beforePlacements`). **Observed:**
- [ ] **VA-16 Cull by Region, Edges.** Reference Edges, wire All Edges of the plate into `edges`, Within 12 mm, Keep "Outside or
  beyond": the holes nearest the plate's rim go and the middle ones stay. Wire Edges by Tag on a hole pattern's rims instead (circles):
  the same node measures to them. Wire an edge set with a spline in it: the badge says how many of the edges it can't measure.
  Pinned: `CullByRegionNodeTests`. **Observed:**
- [ ] **VA-17 Cull by Region, Face.** Reference Face. **Record whether anything in the library can feed `faces`** (at the time of
  writing no node outputs a face set, User decision U18, so the socket cannot be wired from the window and the node reports the missing
  input). If a face-set node exists by now, wire a flat face's set to it: the distance is to the face's **plane**, so a flat face
  far to the side of a small face counts as near it (record that this surprises, as the Errata say; User decision U3). A curved face
  refuses with the count. Pinned: `theFaceReferenceCullsByDistanceToTheFacePlane`, `aCurvedFaceIsRefusedWithTheCount`. **Observed:**
- [ ] **VA-18 Cells three deep.** With Face Pattern (7a-layouts) on a face, wire its placements through Cull Pattern `1 0`: every vent
  stays (per branch, one item each). Set Scope to Overall: every other vent goes. Cull Index `1`: nothing goes; `{0;1}` removes
  one vent and the others have not moved; a pick on a vent follows it through that cull. Random Reduce (defaults) removes one vent.
  Pinned on a hand-made `{row;column;0}` tree: `CellTreeTests`, `CellTreePickTests`. **Observed:**
```


- [ ] **Step 4: Run the task's tests**

Run: `swift test --filter "VariationPipelineTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

- [ ] **Step 5: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > "${TMPDIR:-/tmp}/vtest.log" 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,938 = master + 197** (+4 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "docs(7a-3b): variation pipeline test, CLAUDE.md, roadmap, spec Errata and human checks VA"
```

---

### Task 11: Trees three deep, settings in files, undo names

**Files:**

- Test: `Tests/CreatorNodesTests/Variation/CellTreeTests.swift` (new)
- Test: `Tests/CreatorNodesTests/Variation/CellTreePickTests.swift` (new)
- Test: `Tests/CreatorNodesTests/Variation/VariationFileTests.swift` (new)
- Test: `Tests/CreatorEditorTests/VariationSettingTests.swift` (new)

**Interfaces:**

- Consumes: Tasks 1–10; `TreeSource`, `Harness.source(count:rows:)` (Task 4), `PatternPlate`, `GraftNode`, `GridPatternNode`, `OCCTKernel`.
- Produces: Nothing the code depends on.

Review findings on Tasks 3 to 9: nothing pinned a tree of depth 3, which is the shape Face Pattern (7a-layouts Task 9, merging first) feeds into Place and these
nodes (`{row;column;0}`, one placement per cell). These tests build that shape by hand, a Series partitioned into rows and grafted (`cells`), and a Grid
Pattern's placements grafted (`CellTreePickTests`), so they hold whatever the layouts do. They cover the instance paths and tags Place makes after a cull
of one cell, Cull Index paths of two and three indices, the bare index (degenerate, deliberately, User decision U16), Cull Pattern per branch and Overall,
Random Reduce's scope, Random Values' and Jitter's per-branch ordinals, and a pick that survives a cull of another cell. The other two files pin the saved
settings (a save and reopen, and a format-5 file; User decision U17) and the undo names of typing a mask or a list. All pass at once (they exercise Tasks 1–10),
so there is no red step.

- [ ] **Step 1: Write the tests**

Create `Tests/CreatorNodesTests/Variation/CellTreeTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// The variation nodes on a tree three deep, `{row;column;0}`: one item in every branch, which is the shape Face Pattern gives
/// Place (one placement per cell). It is built here by hand (a Series, Partition and Graft), not by Face Pattern, so these
/// tests hold whatever the layouts do. Bare indices and the mask count places within a branch, so what they do to this shape
/// is pinned: it is deliberate (User decisions U10 and U16), and the paths, Cull Pattern's Overall scope and Cull by Region
/// are how a designer reaches cells.
struct CellTreeTests {
    /// 2 rows of 3 cells numbered 0…5: `{0;0;0}` … `{1;2;0}`.
    static let all = "[[[0],[1],[2]],[[3],[4],[5]]]"

    /// A Series of 6 in rows of 3, every item then grafted into a branch of its own.
    func cells(_ h: inout Harness) -> TreeSource {
        let rows = h.source(count: 6, rows: 3)
        let graft = h.add(GraftNode.self)
        h.wire(rows, to: graft, "tree")
        return TreeSource(node: graft, socket: "tree")
    }

    /// `type` run on the cells with `settings`.
    func run(_ type: any NodeDefinition.Type,
             _ settings: [SocketName: ConstantValue]) async throws -> (report: EvaluationReport, node: Node) {
        var h = Harness()
        let source = cells(&h)
        let node = h.add(type, settings)
        h.wire(source, to: node, "tree")
        return (try await h.run([node]), node)
    }

    func cull(_ text: String) async throws -> (report: EvaluationReport, node: Node) {
        try await run(CullIndexNode.self, [NodeSetting.cullIndices: .text(text)])
    }

    @Test func theCellsAreThreeDeepWithOneItemInEveryBranch() async throws {
        var h = Harness()
        let source = cells(&h)
        let report = try await h.run([source.node])
        let tree = try #require(report.tree(source.node))
        #expect(tree.depth == 3 && tree.shapeText == "2 × 3 × 1")
        #expect(tree.outline == Self.all)
        #expect(tree.leaves.map(\.path) == [[0, 0], [0, 1], [0, 2], [1, 0], [1, 1], [1, 2]].map { TreePath($0) })
    }

    // MARK: Cull Index

    @Test(arguments: ["{0;1;0}", "{0;1}"])
    func aPathOfThreeIndicesOrTwoCullsOneCell(_ text: String) async throws {
        let (report, node) = try await cull(text)
        #expect(report.value(node, "tree")?.outline == "[[[0],[],[2]],[[3],[4],[5]]]", "\(text)")
        #expect(report.tree(node)?.leaves.count == 6, "the other five cells are still at their own paths")
        #expect(report.isOK(node))
    }

    @Test func aRowPathCullsTheWholeRowAndLeavesItsBranchesEmpty() async throws {
        let (report, node) = try await cull("{1}")
        #expect(report.value(node, "tree")?.outline == "[[[0],[1],[2]],[[],[],[]]]")
    }

    @Test func severalPathsAtDifferentLevelsApplyTogether() async throws {
        let (report, node) = try await cull("{0;0;0}, {1;1}, {0;2}")
        #expect(report.value(node, "tree")?.outline == "[[[],[1],[]],[[3],[],[5]]]")
    }

    @Test func aBareIndexIsAPlaceInTheLastLevelSoOnCellsOnlyZeroIsThere() async throws {
        let (one, oneNode) = try await cull("1")
        #expect(one.value(oneNode, "tree")?.outline == Self.all, "no cell has an item 1: nothing is culled, and nothing warns")
        #expect(one.isOK(oneNode))
        let (zero, zeroNode) = try await cull("0")
        #expect(zero.value(zeroNode, "tree")?.outline == "[[[],[],[]],[[],[],[]]]", "every cell's only item is item 0: all of them go")
    }

    @Test func aPathWithFourIndicesIsRefusedNamingTheShape() async throws {
        let (report, node) = try await cull("{0;1;0;0}")
        #expect(report.error(node) == "{0;1;0;0} has 4 indices, but an item of this tree (2 × 3 × 1) needs 3. Write it like {0;0;0}.")
    }

    @Test func aPathThatNamesNoCellWarns() async throws {
        let (report, node) = try await cull("{0;5}, {0;1;0}")
        #expect(report.warning(node) == "{0;5} names nothing in this tree.")
        #expect(report.value(node, "tree")?.outline == "[[[0],[],[2]],[[3],[4],[5]]]")
    }

    // MARK: Cull Pattern

    @Test func perBranchTheMaskRestartsInEveryCellSoOneOneZeroKeepsEveryCell() async throws {
        let (report, node) = try await run(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0")])
        #expect(report.value(node, "tree")?.outline == Self.all, "each branch has one item, the mask's first")
        #expect(report.tree(node)?.isCulled == false)
        let (second, secondNode) = try await run(CullPatternNode.self, [NodeSetting.cullPattern: .text("0 1")])
        #expect(second.value(secondNode, "tree")?.outline == "[[[],[],[]],[[],[],[]]]", "and 0 1 culls every cell")
    }

    @Test func overallTheMaskRunsAlongTheCellsInOrder() async throws {
        let (report, node) = try await run(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 0"), "scope": .integer(1)])
        #expect(report.value(node, "tree")?.outline == "[[[0],[],[2]],[[],[4],[]]]", "cells 0, 2 and 4 stay, at their own paths")
        let (thirds, thirdsNode) = try await run(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 1 0"), "scope": .integer(1)])
        #expect(thirds.value(thirdsNode, "tree")?.outline == "[[[0],[1],[]],[[3],[4],[]]]")
    }

    // MARK: Random Reduce

    @Test func randomReduceDropsOneCellByDefaultAndNeverEmptiesTheTree() async throws {
        let (report, node) = try await run(RandomReduceNode.self, [:])
        #expect(report.tree(node)?.itemCount == 5)
        let (three, threeNode) = try await run(RandomReduceNode.self, ["count": .integer(3), "seed": .integer(7)])
        #expect(three.tree(threeNode)?.itemCount == 3)
    }

    @Test func randomReducePerBranchOnCellsDropsEveryCellAsItSays() async throws {
        let (report, node) = try await run(RandomReduceNode.self, ["scope": .integer(0)])
        #expect(report.tree(node)?.itemCount == 0)
        #expect(report.isOK(node))
    }

    @Test func randomReduceOverallKeepsTheSurvivorsAtTheirCellPaths() async throws {
        let (report, node) = try await run(RandomReduceNode.self, ["count": .integer(2), "seed": .integer(3)])
        let tree = try #require(report.tree(node))
        #expect(tree.leaves.count == 6 && tree.itemCount == 4)
        for leaf in tree.leaves {
            let cell = String(leaf.path.indices[0] * 3 + leaf.path.indices[1])
            #expect(leaf.items.isEmpty || leaf.items.map(\.outlineText) == [cell], "a survivor keeps its own number at its own path")
        }
    }

    // MARK: Random Values and Jitter

    @Test func aCulledCellKeepsTheOtherCellsRandomValues() async throws {
        func values(culling text: String) async throws -> [[String]] {
            var h = Harness()
            let source = cells(&h)
            let cullNode = h.add(CullIndexNode.self, [NodeSetting.cullIndices: .text(text)])
            let random = h.add(RandomValuesNode.self, ["seed": .integer(42)])
            h.wire(source, to: cullNode, "tree")
            h.wire(cullNode, "tree", to: random, "shape")
            let report = try await h.run([random])
            return try #require(report.tree(random, "values")).leaves.map { $0.items.map(\.outlineText) }
        }
        let whole = try await values(culling: "")
        let culled = try await values(culling: "{0;1}")
        #expect(whole.count == 6 && culled.count == 6)
        #expect(Set(whole.joined()).count == 6, "each cell draws from its own branch's stream")
        #expect(culled[1].isEmpty)
        for cell in [0, 2, 3, 4, 5] { #expect(culled[cell] == whole[cell], "cell \(cell)") }
    }

    @Test func aCulledCellKeepsTheOtherCellsJitter() async throws {
        func jittered(culling text: String) async throws -> [[Plane]] {
            var h = Harness()
            let layout = h.add(GridPatternNode.self, ["countX": .integer(3), "countY": .integer(2)])
            let graft = h.add(GraftNode.self)
            let cullNode = h.add(CullIndexNode.self, [NodeSetting.cullIndices: .text(text)])
            let jitter = h.add(JitterNode.self, ["distance": .number(2), "turn": .number(10), "seed": .integer(5)])
            h.wire(layout, "placements", to: graft, "tree")
            h.wire(graft, "tree", to: cullNode, "tree")
            h.wire(cullNode, "tree", to: jitter, "placements")
            let report = try await h.run([jitter])
            return try #require(report.tree(jitter, "placements")).leaves.map { leaf in
                leaf.items.compactMap { if case .plane(let plane) = $0 { plane } else { nil } }
            }
        }
        let whole = try await jittered(culling: "")
        let culled = try await jittered(culling: "{1;0}")
        #expect(whole.count == 6 && culled.count == 6 && culled[3].isEmpty)
        for cell in [0, 1, 2, 4, 5] { #expect(culled[cell] == whole[cell], "cell \(cell)") }
        #expect(whole[0] != whole[1], "the cells do not all move alike")
    }
}
```


Create `Tests/CreatorNodesTests/Variation/CellTreePickTests.swift`:

```swift
import CreatorGeometry
import CreatorGraph
import CreatorKernel
@testable import CreatorNodes
import CreatorOCCT
import Testing

/// Patterns spec §6 and §9 for a culled tree three deep, `{row;column;0}` (one placement per cell, the shape Face Pattern gives
/// Place): the instances Place makes are named by the whole path, a pick on one survives a cull of another, and a pick on a
/// culled one warns, naming its three-index path. The tree is a Grid Pattern's rows with every placement grafted into a branch
/// of its own, so none of this needs Face Pattern.
struct CellTreePickTests {
    /// 3 × 2 Ø5 holes 15 mm apart, grafted to `{row;column;0}`, a Cull Index, a Hole Pattern, an Edges by Tag and a Fillet.
    struct Fixture {
        var plate = PatternPlate(columns: 3, rows: 2, spacingX: 15, spacingY: 15)
        let cull: Node, holes: Node, rule: Node, fillet: Node

        init() {
            let layout = plate.h.add(GridPatternNode.self, ["countX": .integer(3), "countY": .integer(2),
                                                            "spacingX": .number(15), "spacingY": .number(15),
            ])
            let graft = plate.h.add(GraftNode.self)
            cull = plate.h.add(CullIndexNode.self)
            holes = plate.h.add(HolePatternNode.self, ["diameter": .number(5), "depth": .number(6)])
            plate.h.wire(layout, "placements", to: graft, "tree")
            plate.h.wire(graft, "tree", to: cull, "tree")
            plate.h.wire(plate.plate, "solid", to: holes, "part")
            plate.h.wire(cull, "tree", to: holes, "placements")
            rule = plate.h.add(EdgesByTagNode.self)
            plate.h.wire(holes, "solid", to: rule, "solid")
            fillet = plate.h.add(FilletNode.self, ["radius": .number(0.5)])
            plate.h.wire(rule, "edges", to: fillet, "edges")
        }

        mutating func cull(_ text: String) { plate.h.set(cull, NodeSetting.cullIndices, .text(text)) }

        /// The tag of the bore of the hole at `path`, the way Hole Pattern names it.
        func bore(_ path: [Int]) -> TopoTag {
            TopoTag(node: NodeID.instanceScoped([holes.id, holes.id]), item: InstancePath.item(for: path) ?? -1, role: .side(segment: 1))
        }

        /// The rim of the hole at `path` on the plate's top.
        func rim(of path: [Int], in solid: Solid) -> EdgeInfo? {
            let top = TopoTag(node: plate.plate.id, item: 0, role: .endCap)
            return solid.topology.edges.first { edge in
                guard edge.kind == .circle, !edge.isSeam, edge.faces.count == 2 else { return false }
                let sides = edge.faces.compactMap { solid.topology.face($0) }
                return sides.contains { $0.tags.contains(bore(path)) } && sides.contains { $0.tags.contains(top) }
            }
        }

        /// Picks the rims of the holes at `paths` on the rule, from a run with nothing culled.
        mutating func pick(_ paths: [[Int]], kernel: any Kernel) async throws {
            cull("")
            let solid = try onlySolid(try await plate.h.run([holes], kernel: kernel), holes)
            let edges = try paths.map { try #require(rim(of: $0, in: solid)).id }
            plate.h.set(rule, NodeSetting.picks, .edgePicks(solid.topology.picks(for: edges)))
        }

        func selected(_ report: EvaluationReport) throws -> (solid: Solid, edges: [EdgeInfo]) {
            let set = try #require(report.value(rule, "edges")?.edgeSets?.first)
            return (set.solid, set.edges.compactMap { set.solid.topology.edge($0) })
        }

        func touches(_ path: [Int], _ edge: EdgeInfo, in solid: Solid) -> Bool {
            edge.faces.compactMap { solid.topology.face($0) }.contains { $0.tags.contains(bore(path)) }
        }

        /// The paths of the holes the Hole Pattern made.
        func holePaths(_ report: EvaluationReport) throws -> Set<[Int]> {
            let solid = try onlySolid(report, holes)
            let items = solid.topology.faces.flatMap(\.tags).filter(\.node.isInstanceQualified).map(\.item)
            return Set(items.compactMap { InstancePath.indices(ofItem: $0) })
        }
    }

    static let every: Set<[Int]> = [[0, 0, 0], [0, 1, 0], [0, 2, 0], [1, 0, 0], [1, 1, 0], [1, 2, 0]]

    @Test func everyCellMakesAHoleAtItsThreeIndexPath() async throws {
        var f = Fixture()
        f.cull("")
        let report = try await f.plate.h.run([f.holes], kernel: OCCTKernel())
        #expect(try f.holePaths(report) == Self.every)
    }

    @Test(arguments: ["{0;1;0}", "{0;1}"])
    func aCulledCellLeavesTheOthersAtTheirPaths(_ text: String) async throws {
        var f = Fixture()
        f.cull(text)
        let report = try await f.plate.h.run([f.holes], kernel: OCCTKernel())
        #expect(try f.holePaths(report) == Self.every.subtracting([[0, 1, 0]]), "\(text)")
        #expect(report.isOK(f.holes), "a cull never warns")
    }

    @Test func aBareIndexOnCellsCullsNothingOrEverythingAsItsLastLevelHasOnlyZero() async throws {
        var f = Fixture()
        f.cull("1")
        let kept = try await f.plate.h.run([f.holes], kernel: OCCTKernel())
        #expect(try f.holePaths(kept) == Self.every)
        f.cull("0")
        let report = try await f.plate.h.run([f.holes], kernel: OCCTKernel())
        #expect(report.isOK(f.holes), "no holes is not an error")
        #expect(try onlySolid(report, f.holes).topology.faces.flatMap(\.tags).filter(\.node.isInstanceQualified).isEmpty)
    }

    @Test(arguments: ["{1;1;0}", "{1;1}", "{1}"])
    func aPickOnACulledCellWarnsNamingItsThreeIndexPathAndSelectsNothing(_ text: String) async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([[1, 1, 0]], kernel: kernel)
        f.cull(text)
        let report = try await f.plate.h.run([f.rule], kernel: kernel)
        #expect(report.warning(f.rule) == "Instance {1;1;0} no longer exists, so the edge picked on it isn't selected.", "\(text)")
        #expect(try f.selected(report).edges.isEmpty, "never a neighbour's rim")
    }

    @Test(arguments: ["{0;0;0}", "{0;2}", "{0}", "{1;0}, {1;2}"])
    func aPickOnOneCellSurvivesACullOfAnother(_ text: String) async throws {
        let kernel = OCCTKernel()
        var f = Fixture()
        try await f.pick([[1, 1, 0]], kernel: kernel)
        let before = try f.selected(try await f.plate.h.run([f.rule], kernel: kernel))
        f.cull(text)
        let report = try await f.plate.h.run([f.fillet], kernel: kernel)
        #expect(report.isOK(f.rule) && report.isOK(f.fillet), "after culling \(text): \(String(describing: report.state(f.rule)))")
        let (solid, edges) = try f.selected(report)
        #expect(edges.count == 1 && edges.allSatisfy { f.touches([1, 1, 0], $0, in: solid) }, "still the rim of {1;1;0}")
        #expect(before.edges.count == 1)
    }
}
```


Create `Tests/CreatorNodesTests/Variation/VariationFileTests.swift`:

```swift
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing

/// The variation nodes' two text settings are saved with the graph (format 6, which does not change: User decision U17) and a
/// reopened graph evaluates exactly as it did.
struct VariationFileTests {
    func roundTrip(_ file: GraphFile) throws -> GraphFile {
        try GraphFileIO.decode(try GraphFileIO.encode(file), registry: BuiltInNodes.registry)
    }

    @Test func cullPatternAndCullIndexSettingsSurviveSaveAndReload() async throws {
        var h = Harness()
        let source = h.source(count: 8, rows: 4)
        let pattern = h.add(CullPatternNode.self, [NodeSetting.cullPattern: .text("1 1 0"), "scope": .integer(1)])
        let index = h.add(CullIndexNode.self, [NodeSetting.cullIndices: .text("1, {0;3}")])
        h.wire(source, to: pattern, "tree")
        h.wire(pattern, "tree", to: index, "tree")
        let before = try await h.run([index])

        let reopened = try roundTrip(GraphFile(graph: h.graph))
        #expect(reopened.formatVersion == GraphFile.currentFormatVersion && GraphFile.currentFormatVersion == 6)
        #expect(reopened.graph.nodes[pattern.id]?.inputValues[NodeSetting.cullPattern] == .text("1 1 0"))
        #expect(reopened.graph.nodes[pattern.id]?.inputValues["scope"] == .integer(1))
        #expect(reopened.graph.nodes[index.id]?.inputValues[NodeSetting.cullIndices] == .text("1, {0;3}"))

        let after = try await Evaluator(registry: BuiltInNodes.registry, kernel: FakeKernel())
            .evaluate(reopened.graph, demand: [index.id])
        #expect(after.value(index, "tree")?.outline == before.value(index, "tree")?.outline)
        #expect(after.positions(index) == before.positions(index) && before.positions(index) != nil)
    }

    @Test func aFormatFiveFileStillOpensWithTheVariationNodesAvailable() throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["count": .integer(4)])
        let older = try roundTrip(GraphFile(formatVersion: 5, graph: h.graph))
        #expect(older.formatVersion == 5, "a file keeps the version it was written with until it is saved")
        #expect(older.graph.nodes[series.id]?.inputValues["count"] == .integer(4))
    }
}
```


Create `Tests/CreatorEditorTests/VariationSettingTests.swift`:

```swift
import CreatorGraph
import CreatorNodes
import Testing
@testable import CreatorEditor

/// Typing a Cull Pattern mask or a Cull Index list is one named undo step, like any text setting (`TextSettingTests`).
@MainActor
struct VariationSettingTests {
    /// Types `text` into the first text field of a new `typeID` node and returns the editor and the node.
    func type(_ text: String, into typeID: String) throws -> (editor: EditorModel, node: Node) {
        let node = BuiltInNodes.registry.makeNode(typeID)
        let editor = makeEditor([node], registry: BuiltInNodes.registry)
        editor.selection = [node.id]
        let field = try #require(editor.inspectorPage.sections.flatMap(\.rows).compactMap { row -> InputField? in
            if case .text(let field) = row { field } else { nil }
        }.first)
        editor.setInput(field, to: .text(text))
        return (editor, node)
    }

    @Test func typingACullPatternMaskIsOneNamedUndoStep() throws {
        let (editor, node) = try type("1 1 0", into: CullPatternNode.typeID)
        #expect(editor.graph.nodes[node.id]?.inputValues[NodeSetting.cullPattern] == .text("1 1 0"))
        #expect(editor.document.undoName == "Change Cull pattern")
        editor.document.undo()
        #expect(editor.graph.nodes[node.id]?.inputValues[NodeSetting.cullPattern] == .text("1 0"))
    }

    @Test func typingCullIndicesIsOneNamedUndoStep() throws {
        let (editor, node) = try type("1, {0;3}", into: CullIndexNode.typeID)
        #expect(editor.graph.nodes[node.id]?.inputValues[NodeSetting.cullIndices] == .text("1, {0;3}"))
        #expect(editor.document.undoName == "Change Cull indices")
        editor.document.undo()
        #expect(editor.graph.nodes[node.id]?.inputValues[NodeSetting.cullIndices] == .text(""))
    }
}
```


- [ ] **Step 2: Run them (they pass at once)**

Run: `swift test --filter "CellTreeTests|CellTreePickTests|VariationFileTests|VariationSettingTests" 2>&1 | grep -v 'ld: warning'`

Expected: PASS, with no line saying "recorded an issue" or "failed after".

- [ ] **Step 3: The full rule**

Run, from the worktree root:

```bash
swift build --build-tests 2>&1 | grep -E "^/.*(warning|error):" | grep -v "ld: warning" | sort -u
swift test > "${TMPDIR:-/tmp}/vtest.log" 2>&1; echo "exit=$?"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -cE "recorded an issue|failed after"
sed 's/\x1b\[[0-9;]*m//g' "${TMPDIR:-/tmp}/vtest.log" | grep -c "Test run with"
swiftlint lint --strict
```

Expected: no warnings other than master's `ContextMenuTests.swift:140` ('underPointer' mutated after capture), which appears whenever that test target recompiles; `exit=0`; `0` bad lines; `11` "Test run with" lines; swiftlint `Found 0 violations`. **Test count: 2,961 = master + 220** (+23 in this task; the Swift Testing total counts a parameterised test once).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test(7a-3b): variation on trees three deep, saved settings and undo names"
```

---

## Self-review

**Spec coverage (§4, §6, §8, §9).**
- Cull Pattern: Task 4 (with a `scope`: Per branch or Overall). Cull Index (indices and paths such as `{0;3}`): Task 5. Cull by Region (profile inside/outside; point, edge set, face within/beyond): Task 6. Random Reduce (N or fraction, overall by default or per branch): Task 7. Random Values (integers or reals in a range, in the shape of a tree or a count): Task 8. Jitter (offset in the placement's plane, turn about its normal, within limits): Task 9. All in the Patterns category and tree-aware (`access: .tree`).
- Culling keeps paths, including item gaps inside a branch: Task 2 (the representation), Task 3 (instances and tags by tree path, and Points to Placements passing every path on), pinned per node in Tasks 4 to 9, end to end in Task 10, and on a tree three deep, `{row;column;0}`, in Task 11.
- Randomness seeded by a `seed` input, a fixed documented repo algorithm, pinned values, never the system generator, seed change never warns: Task 1 (generator, one purpose per random node, and their pins), Tasks 7 to 9 (`report.isOK` after a seed change; pinned results per branch and overall), Task 10 (same seed, same part; equal seeds on different nodes decorrelated).
- Naming (§6, §9): a pick on an instance survives a cull of another and a pick on a culled instance warns naming its path, on a flat list and in rows: Task 5 (`CulledPickTests`, `CulledTreePickTests`, each with the cull on both sides of Points to Placements); the tags themselves: Task 3.
- Errors (§8): path shapes named (Task 5), refused values name their socket (Tasks 4 to 9), unmatched paths named (Task 5), no warning for a seed or a cull.
- Face Pattern, layout previews, Pattern on Face and the acceptance test are 7a-layouts Tasks 9 to 14 (merging first); no benchmark is run or added.

**Placeholder scan.** Every code block was applied, task by task, to a fresh copy of master `6dda4d6` (the replay below) and built, tested and linted; the plan text is the text that was applied, so there is no pseudo-code and no "similar to Task N". The steps name the files; the code is in the plan.

**Type consistency.** `culledList(_:at:)`, `isCulled`, `itemPositions`, `culledPositions`, `Leaf.positions`, `keepingItems(where:)`, `mappingItems(_:)`, `replacingItems(_:)` (Task 2) are the names Tasks 3 to 9 call (Task 3 through `InstanceGrid`, which reads `isCulled`, `itemPositions`, `culledPositions`, `Leaf.positions` and builds `culledList`); `InstanceGrid.vectors(_:)` (Task 3) is Points to Placements'; `SeededRandom.value(at:)/unit(at:)/below(_:at:)` (Task 1) are Tasks 7 to 9's; `NodeSetting.cullPattern/cullIndices` are their nodes' and the tests'.

**Review Focus.** Each of the eight has its test in the task named in the list at the top; none is left uncovered.

**Verification record.** Replayed on master `6dda4d6` (2741 tests), twice. The first replay applied Tasks 1 to 10 of the earlier version of this plan in order to a fresh scratch copy (a sibling `MetalUI` symlink to `/Users/maxburger/Developer/MetalUI`) by a script that stops at an anchor that is missing or repeated: build, full `swift test` and `swiftlint lint --strict` clean, with the per-task totals in the table. The pinned random values (Tasks 1, 7, 8, 9) were recomputed with a separate SplitMix64 and the purpose salts, never by running the nodes. This revision (review findings on the depth-3 shape, U16 and U17) was replayed the same way on a fresh scratch copy, **Tasks 1 to 11 applied by the script (83 edits, no anchor missed)**: `swift build --build-tests` with no warning beyond master's `ContextMenuTests.swift:140`, a full `swift test` with exit 0, 0 lines saying "recorded an issue" or "failed after", 11 "Test run with" lines totalling **2,961 tests** (231 + 73 + 187 + 197 + 149 + 640 + 147 + 418 + 48 + 593 + 278), and `swiftlint lint --strict` with 0 violations. A mutation (Cull Pattern ignoring its scope) failed 5 tests across `CullPatternNodeTests` and `CellTreeTests`, so the new tests can fail. The totals of Tasks 4 to 10 in the table moved by this revision's +3 (Task 4) and +3 (Task 7); only the final total was re-measured. Task 3's Step 2 is red (37 issues) and every other task's Step 2 fails to build with the symbol it names; Tasks 10 and 11 have no red step. Per-task new tests and running totals:

| Task | What | New tests | Total |
|---|---|---|---|
| 1 | SeededRandom, the one generator, one purpose per random node | +11 | 2,752 (master + 11) |
| 2 | Culled lists in trees (paths kept through a cull) | +20 | 2,772 (master + 31) |
| 3 | Surviving instances keep their path (`InstanceGrid`, Points to Placements over trees) | +42 | 2,814 (master + 73) |
| 4 | Cull Pattern (with `scope`) | +16 | 2,830 (master + 89) |
| 5 | Cull Index, and the naming tests (spec §9) on a flat list and on rows, the cull on both sides of Points to Placements | +31 | 2,861 (master + 120) |
| 6 | Cull by Region | +28 | 2,889 (master + 148) |
| 7 | Random Reduce (scope Overall by default) | +17 | 2,906 (master + 165) |
| 8 | Random Values | +16 | 2,922 (master + 181) |
| 9 | Jitter | +12 | 2,934 (master + 193) |
| 10 | The pipeline test (flat and in rows) and the records | +4 | 2,938 (master + 197) |
| 11 | Trees three deep, saved settings, undo names | +23 | 2,961 (master + 220) |

Every task: `swift build --build-tests` with no new warnings (master's `ContextMenuTests.swift:140` aside), full `swift test` exit 0 with no "recorded an issue" or "failed after" line and 11 "Test run with" lines, `swiftlint lint --strict` with 0 violations.
