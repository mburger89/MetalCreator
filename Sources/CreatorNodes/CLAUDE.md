# CreatorNodes

Notes for this module, moved from the root `CLAUDE.md` (which Claude Code loads in every session) so they load only when work touches this folder. The project-wide rules, commands and toolchain notes stay in the root file.

Patterns, sub-project 7a-2 (Place, Points to Placements, the four shortcut nodes, the `Patterns` library category and the
200-instance benchmark; plan `docs/superpowers/plans/2026-10-10-7a-place.md`, spec `2026-10-10-patterns-trees-design.md` §3, §5,
§6, §7) code is done; its human checks (group PA) are pending and its benchmark numbers (`PatternBench`) await an idle run.
Patterns, sub-project 7a-3 part A (the five layout nodes, trees of placements through Place and the shortcuts, instance
tags by
tree path, layout previews in the viewport, Pattern on Face and the acceptance test; plan
`docs/superpowers/plans/2026-10-12-7a-layouts.md`,
spec `2026-10-10-patterns-trees-design.md` §3, §6, §8, §9 and its Errata (7a-3)) code is done; its human checks (group
PL) are pending.
Patterns, sub-project 7a-3 part B (variation and culling: Cull Pattern, Cull Index, Cull by Region, Random Reduce, Random Values and
Jitter; plan `docs/superpowers/plans/2026-10-12-7a-variation.md`, spec `2026-10-10-patterns-trees-design.md` §4) code is done; its human
checks (group VA) are pending. The layouts, previews and acceptance test are part A (7a-layouts).
Fields, sub-project 7b-1 (the fields core: the `Field` value and `.field` sockets, `FieldSampler` and `FieldDistanceCache`,
`Kernel.distances`, the four sources, the six maths nodes, Sample Field and Cull by Field, the `Fields` library category and
`FieldBench` rows 1 to 3; plan `docs/superpowers/plans/2026-10-12-7b-core.md`, spec `docs/superpowers/specs/2026-10-12-fields-design.md`
§2 to §4, §7 and §9) is merged; its human checks (group FI-core) are pending and its benchmark numbers are recorded in
`docs/verification/performance.md`.
Fields, sub-project 7b-2 (images: the Image Field, `ImageReference` and `NodeSetting.image`, the document's `images` table,
`GreyImageDecoder`, choosing, linking, relinking and embedding a picture, file format 7, and a `field` socket on a group's edge; plan
`docs/superpowers/plans/2026-10-13-7b-2-images.md`, spec `docs/superpowers/specs/2026-10-12-fields-design.md` §5 and the 7b-1 Errata)
code is done; its human checks (group FI-img) are pending.
Fields, sub-project 7b-3 (Field Scatter, the surface tint, the slice plane and the legend, the three theme roles `fieldLow`,
`fieldMid` and `fieldHigh`, the acceptance test and `FieldBench` rows 3 and 4; plan
`docs/superpowers/plans/2026-10-13-7b-3-scatter-previews.md`, spec `docs/superpowers/specs/2026-10-12-fields-design.md` §3.3, §6, §7
and §8 and its Errata (7b-3)) code is done; its human checks (group FI) are pending and its benchmark numbers are recorded in
`docs/verification/performance.md`.

G2 fillets (curvature-continuous blends: spec `docs/superpowers/specs/2026-11-01-g2-surfacing-design.md` G-b, with its 2026-11-01 corner and mitred-corner errata; `FilletNode`'s Continuity and tangency weight) code is done; its human checks (group G2F) are pending and its benchmark row `g2-fillet-1` is in `docs/verification/performance.md`. While a slider or handle is being dragged (`EditorModel.sliderEditingChanged`, `AppModel.handleChanged`'s `.changed` to `.ended`; the slice and section handles don't count) `DocumentModel.isScrubbing` is true and `EvalContext.isScrubbing` makes a G2 fillet build as its circular (G1) fillet with identical tags and no warnings; `NodeDefinition.readsScrubbing` (and `readsScrubbing(for:)`, false for a G1 fillet so it keeps its cache entry) puts the flag in the node's cache key as `readsMeshQuality` does, and the flag clearing schedules the G2 evaluation (view state: no undo step, no edit); human check G2F-9.

Loft end conditions (G-d: a Loft that grows out of a part's face tangent or curvature continuous; spec `docs/superpowers/specs/2026-11-02-loft-end-conditions-design.md`, plan `docs/superpowers/plans/2026-11-02-loft-end-conditions.md`) code is done; its human checks (group LE) are pending and its benchmark row `loft-ends-1` is in `docs/verification/performance.md` (a box's top face to a 12 mm square at G2: about 295 ms from edit to preview, on a loaded Mac, saturated).
Convert Units (`ConvertUnitsNode`, `Sources/CreatorNodes/Values`: a plain number between lengths mm, cm, m, in, ft or angles deg, rad, by exact factors; its `value` has no unit, so the document's display units never touch it; the inspector shows only the active quantity's two controls through `inspector(for:)`) code is done; its human checks (group CU) are pending.

- `CreatorNodes`: the 115 built-in node definitions (`BuiltInNodes.registry`: the slice's 26, Plane from Face and Sketch,
the fourteen `Fields` nodes below, the fourteen `Implicit` nodes and the six Mesh nodes (`Implicit/`, categories `NodeCategory.implicit` and
`.mesh`: Sphere, Box, Cylinder, Union, Subtract, Intersect, Shell, Offset, To Implicit, Isosurface, Drain Holes, TPMS, Strut Lattice, Voronoi Lattice
(`Implicit/Lattices/`: they share `LatticeSetup` and `LatticeFill`, which joins the skin and the lattice by a smooth union of the `blend` input, 0 on a graph saved before 7c-3f; the built-in Voronoi seeds are `VoronoiSeedSource`, drawn with
`SeededRandom.Purpose.voronoi`); Mesh, Decimate, Check Thin Walls, Check Trapped Volumes, Mesh to Solid, Import Mesh in `Implicit/MeshTools`), the seventeen
  `Patterns` nodes below, and the eight Lists & Trees nodes in `Lists/`: Flatten, Graft, Partition, Tree Statistics, List Item, Branch by Path, Merge and Path
  Mapper, whose rule syntax is `Lists/PathMapper/PathRule`), UI-free: inspector sections and handles are data. Non-socket settings (`NodeSetting` in CreatorGraph:
  parameter, picks, showHandle, sketch, face, groupID, pathRule, branchPath, itemPath, cullPattern, cullIndices, image, meshFile, pcbFile, and `projection(reference)` per projected edge) live in
  `Node.inputValues`; `NodeRegistry.makeNode` seeds `defaultSettings` and sets `isOutput` for `.output`-category nodes.
  - Merge (`Lists/MergeNode`, `creator.merge`): four optional `.any` tree sockets `a` to `d` and one `list` output; the items of a, then b, c and d, as one flat `.list` (a single value is one item, a tree is flattened row by row, a culled list contributes its survivors and the result is renumbered, never culled; unwired inputs are skipped, nothing wired is an empty list). It is how different shapes reach a list socket such as Union's `shapes`, since an input takes one wire; for more than four, merge a Merge. It judges no types: a solid or a number beside implicits is refused by the next node ("“shapes” needs an implicit solid. To Implicit makes one from a solid."). No format bump. Human checks (group MG) are pending.
  - Patterns (`Sources/CreatorNodes/Patterns`, category `NodeCategory.patterns`, library section "Patterns"; patterns spec §3, §5–§7):
    The layouts (`Patterns/Layouts`): Linear Pattern (a flat list), Grid Pattern (a tree, a branch per row), Circular
    Pattern (a
    branch per ring; `countStep`, `radiusStep`, `startAngle`), Curve Pattern (a branch per chain of straight or circular
    edges,
    `EdgeChains`, or per loop of a profile) and Face Pattern (a picked flat face, `FaceRegion` clipping to its holes and
    a margin; a
    branch per row holding a branch per grid cell, counted from the lowest row and column its box reaches, so a vent
    keeps its path
    as the margin or a hole changes (a face growing at its lower left renumbers)), each refusing over 2,000
    (`PatternLimit`). A layout that is a tree is one even for one row or ring, so a ring added later renames no path. A
    list wired into
    a layout's input is refused in its own words (`NodeDefinition.singleValuesRefusal`, before it runs).
    Place (a tool built at the origin facing +Z and `Plane` placements, matched by `InstanceGrid`: the longer flat list
    sets the
    count and the shorter repeats its last item; a tree of placements gives a tree of copies, a flat list applying to
    every
    branch and a tree as deep as the shape matching level by level, so a Graft of one size per ring sizes the rings),
    Points to Placements, and the shortcuts Hole Pattern, Boss / Pin
    Pattern, Slot Pattern and Pattern Feature, each Place + Boolean underneath through `PatternApply`: tools built once per
    distinct size (`ToolPlan`), one `Kernel.place` and one `Kernel.boolean`, never a boolean per instance. A shortcut's sizes
    are `.tree` sockets matched to the placements by `InstanceGrid` (inside the node, so it can make one kernel call).
    Over 2,000
    instances refuses ("Patterns are limited to 2,000 instances.", `PatternLimit`); a tree on the part or the operation
    is refused
    (`EvalContext.isTreeRun`, `PlacementMoves.requireSingleValues`); placements, sizes and tools are read whole, one
    kernel call for a tree; an instance that did nothing to the part
    warns with the count (`PatternMisses`: a cut leaves no face tagged with its item, a union's bounds don't touch the
    part's). A copy's tags are its tool's, qualified: node `NodeID.instanceScoped([placer, toolNode])` and item the copy's
    path (`InstancePath.item(for:)`: `{i}` is the item `i`, `{row;i}` one packed negative number), so a pick follows its
    instance through
    count, spacing and size changes; `EdgeTagMatch` and Plane from Face say "Instance {4} no longer exists…" (several,
    in path order) when it is gone
    and never fall back to a neighbour. In a group, `EvaluationScope.entering` lifts its renaming table to the placer/tool
    pairs (`GroupScopes.lifting`, `NodeDefinition.placesInstances`), and `GraphContent.relativeToLevel(_:levels:registry:)`
    does the same for a pick made in the viewport inside one. Group, Ungroup and Make Unique rename instance picks too
    (`GroupScopes.names` lifts its table with the registry); not lifted yet: a Place inside a group whose tool comes from
    outside it keeps instance picks stored in the definition from matching.
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
  - Fields (`Sources/CreatorNodes/Fields`, category `NodeCategory.fields`, library section "Fields", after Lists & Trees; fields spec
    §3): `FieldSampler.sample(_:at:kernel:cache:)` is the one way to read a field: it walks the expression once per batch over
    structure-of-arrays `[Double]`s, checks cancellation every 1,024 points, asks the kernel once per distance leaf (through the
    evaluator's `FieldDistanceCache` when given), and never lets a value depend on the rest of the batch; its one `switch` over
    `Field` has no `default`, so a new case (the Image Field's `.image`, 7b-2, was the first) is a compile error there, in `Field.children`, `Field.description` and
    `Field.ownPlane`. `FieldNoise` is 3D simplex noise hashed with `SeededRandom` (purpose `.fieldNoise`, the octave as the stream;
    `.fieldCull` is Cull by Field's; both pinned in `FieldNoiseTests` like the others). The sources are Distance Field (`target` is
    an `any` socket: a vector, edge set, profile, face set or solid; `mode` Unsigned / Signed matters to a solid only), Linear
    Gradient, Radial Gradient and Noise Field; the maths nodes (`Maths/`) are Add, Multiply, Min / Max, Remap, Clamp and Smooth
    Blend, each over `.field` item sockets, so a list of fields broadcasts and a number typed or wired in is a constant field.
    Sample Field (`at` is a `plane` socket with `tree` access, so points and placements both wire) returns numbers in the shape of
    `at`, culled gaps and paths included, from one sampler call; a single plane gives a list of one. Cull by Field keeps placements
    by Threshold (Above and Below both keep a value exactly on the level) or Probability (a `.fieldCull` draw at the item's kept
    index, stream = branch ordinal, below the field held to 0…1, as Random Reduce draws), keeping paths; both refuse a list in any
    input in the layouts' words (`singleValuesRefusal` = `LayoutChecks.singleValues`). The graded-sizes chain is a field → Remap →
    Sample Field → a shortcut's size socket (Remap takes and returns a field, so the spec's reverse order cannot be wired; fields
    spec Errata (7b-1)). Fields are computed, never saved; a group interface may carry a `field` socket (format 7: under 6 `"field"`
    would not decode in an older build, so 7b-1 refused it with `GroupRefusal.fieldSocket`, now gone). The distance cache counts the
    solids its entries keep alive. `FieldBench`
    (`Tests/CreatorAppTests/Bench`): rows 1 and 2 are the spec's (row 2's 100 ms is for analytic solids and gates the merge;
    `field-2b` records a smooth loft); row 3 is Field Scatter over a face (`field-3b` keeps 7b-1's Sample Field and Cull by Field
    over 2,000 placements); row 4 (`FieldBenchPreview`) is the edit to a tinted preview on the bracket. Timings taken on a loaded
    Mac are recorded as saturated, never as a verdict.
  - Images (fields spec §5; plan `2026-10-13-7b-2-images`): the Image Field (`Fields/Sources/ImageFieldNode`) projects a picture along a
    plane (centred, `width` × `height` mm, row 0 at the plane's +y, Tile or Clamp, bilinear grey in 0…1) as `Field.image(GreyImage,
    plane:width:height:edges:)`. The picture is the node's `NodeSetting.image`, a `ConstantValue.image(ImageReference)`: `.embedded(ImageHash)`
    (the SHA-256 of the file's bytes) or `.linked(relativePath:absolutePath:)`. **Images are untrusted input**: `ImageLimits` (16 MB, 8,192 px
    a side, PNG and JPEG only) are checked from the header before a pixel is decoded (`GreyImageDecoder.inspect` over MetalUI's `ImageInfo(data:)`, S9, gap XP-G10, with `OtherPictureSignature` for
    GIF and the like, gap XP-G12; `PNGStructure.isWhole` still refuses a cut-short PNG), `decode` runs off the caller's actor and
    decodes through MetalUI's `DecodedImage(data:format: .rgba)` on every platform (S2, gap XP-G4; ImageIO is not used anywhere in `Sources`),
    then converts to grey in 32 MB bands, checking for cancellation between them and applying the orientation as it indexes the stored
    pixels (no oriented copy). Peak memory at 8,192²: the file (16 MB), MetalUI's whole decoded RGBA (256 MB, whatever the bit depth) and the 128 MB result,
    so about 0.4 GB, plus any transient copy inside MetalUI's decode; the decode itself cannot be cancelled. A 16-bit PNG is read to the
    nearest 8-bit level (S2 rounds), a PNG with a bad CRC and a truncated JPEG are refused. A linked path must be
    a regular file, opened without blocking and checked again on the descriptor, and is read at most 16 MB + 1 byte (`ImageResolver`),
    and every failure is an `ImageProblem` with its sentence. Colour becomes Rec. 709 luminance of the straight-alpha colour composited against black (our conversion, not S2's `.grey`, which is Rec. 601
    with alpha dropped); EXIF orientation is applied. `DocumentModel.images` is the session's pool of embedded bytes by hash (`addImage`; unused ones are dropped on save, not
    before, so undo works); `ImageResolver` (the pool and the document's folder) goes to every evaluation, and `gather` adds
    `ImageStamp` (a linked file's path, modification date and size, or an embedded hash) to a node's cache key, so a file edited on disk
    runs the node again at the next evaluation and nothing else does. `GreyImageCache` keeps decoded pictures by that stamp (256 MB, LRU) and, under the same stamp, the pictures that
    failed to decode (at most 256), so a damaged file fails at once until it changes; a read error is not remembered.
    `fileData(savingTo:)` writes the linked paths as they will be found from the new folder, and `DocumentModel.didSave(to:)` brings the
    open document's paths into line with them (no undo step, no edit). `Field.ownPlane` is the plane of the first linear gradient or
    image in a field (the slice plane of 7b-3 starts there). `NodeSetting.image` is the one setting not in `NodeSetting.reservedForSockets` (the names a group socket or an exposed Sketch
    dimension may not take), so one called "image" in an older file keeps working. The inspector's `.image` control makes a
    status line and the buttons that fit (Choose Image…, Link Image…, Relink…, Embed Image: `InspectorAction`s carried out by
    `AppModel.performImage`, which owns the panels); the clipboard carries the embedded pictures its nodes use.
    Field Scatter (7b-3, `Using/FieldScatterNode`) is the layout node for density: `solid` (a picked flat face, the `face` setting, read
    as Face Pattern reads it, holes and margin respected) or `profile` (exactly one), `field` (a number is a constant field),
    `minSpacing`, `maxSpacing`, `margin` and `seed`. `PoissonScatter` is variable-radius Bridson sampling: rounds of candidates in
    the annulus `r`…`2r` round each active point, the field asked once per round for all that survive the cheap tests, each active
    point taking its first candidate at least its own spacing from every placed point, a new seed drawn when nothing is active (islands,
    jumps in spacing), every draw `SeededRandom` under `Purpose.scatter`; the spacing at a point is
    `minSpacing + clamp(field, 0, 1) × (maxSpacing − minSpacing)`, so no two points are closer than `minSpacing`. It makes one flat
    list of placements on the region's plane in generation order, refuses over 2,000 ("Field Scatter would place N points; …", "more
    than 8,000" when it stopped at its ceiling) and renumbers when the field, region or seed changes: a pick on a scattered instance
    then warns "Instance {n} no longer exists". `InspectorControl.note(_:)` carries its help line, and the face menu's Scatter on Face
    (`AppModel.scatterOnFace`, `FaceLayout`) inserts one wired to the part.
  Driving dimensions: the Sketch node's `sketchTrace` (the `SketchTrace` of its evaluated profile, evaluation output only) and
  `SketchNode.projectedEntity` (the projected entity a reference resolves to).
