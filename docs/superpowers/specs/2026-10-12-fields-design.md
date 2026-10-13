# Fields (sub-project 7b) — design

Status: written 2026-10-12 from a design conversation with the user; awaiting the user's review.
Parent spec: `2026-10-07-metalcreator-vertical-slice-design.md` (§4 values and broadcasting, §6 UI, §7.3 performance), with
all its Errata. Sibling spec `2026-10-10-patterns-trees-design.md` (7a: trees, placements, culling, `SeededRandom`,
`InstanceGrid`, instance naming), with all its Errata; its §1 table places 7b between 7a and 7c/7d.

## 1. Intent

A **field** is a value that varies over space: a number at every point. 7b adds fields as a first-class value, the
sources that make them, the maths that combines them, the nodes that turn them into per-instance numbers, culls and
scattered placements, and previews that show them on the part.

**Purposes (user, all four):**
1. Graded sizes: a hole, boss or slot size that follows a field (larger near an edge, smaller in the middle).
2. Density and culling: keep or scatter instances where a field says.
3. Image-driven patterns: a greyscale picture projected onto a face drives sizes or density.
4. Groundwork for 7c (implicit geometry, lattices) and 7d (surface textures), which will sample the same fields.

**Success.** A field is cheap to build and inspectable as text; sampling is deterministic and batched; previews show a
field on the part while it is being edited; everything 7b makes stays exact B-rep and STEP-exportable (a field only
chooses numbers and placements; it never becomes geometry here).

### Decisions recorded (user, 2026-10-12)

| # | Decision |
|---|---|
| D1 | Purposes: all four above. |
| D2 | Sources: distance, gradients, noise, image. |
| D3 | Approach A: a field is an immutable, inspectable expression tree, sampled in batches in Swift; never saved; kernel distances cached per field; compilable to Metal later (7c). |
| D4 | A number or integer converts implicitly to a constant field; a field never converts to a number (only a sampling node turns it into numbers). |
| D5 | Distance to a solid is signed: negative inside. |
| D6 | Density: both Cull by Field and Field Scatter. |
| D7 | Field Scatter renumbers its points when the field or region changes; a pick on a scattered instance then warns "Instance {n} no longer exists" (the existing rule), and the inspector help says so. |
| D8 | Field Scatter fills a flat face or a profile on its plane; curved-surface and volume scatter are out of scope (7c/7d). |
| D9 | Images: embed or link, chosen per image; file format 7. |
| D10 | Embedded image limits: 16 MB and 8,192 px per side. |
| D11 | A linked image is reloaded when its modification date changes, checked at each evaluation. |
| D12 | Preview: tint on the part's surface and an optional slice plane, with a colour ramp and legend. |
| D13 | The ramp is three theme roles, `fieldLow`, `fieldMid`, `fieldHigh` (not a fixed palette). |
| D14 | Parts over 200,000 mesh vertices are previewed coarsely, and the legend says so. |
| D15 | Build split: 7b-1 core, then 7b-2 images and 7b-3 scatter and previews in parallel. |

## 2. The field value

### 2.1 Type

- `Field` (in `CreatorGraph`, beside `DataTree`) is an immutable, `Sendable` value: an indirect enum of nodes (sources,
  maths) whose leaves hold plain values and kernel references (`Solid`, `EdgeSet`, `FaceSet`, `Profile2D`, `Plane`, a
  decoded `GreyImage`). It holds no samples.
- `Scalar` gains `.field(Field)`; `SocketType` gains `.field` (a new socket colour role in the editor). `Scalar.type`,
  `estimatedBytes` (64 + 32 per node, plus a referenced image's bytes) and the socket colour cover it.
- `Scalar.converted(to: .field)` turns `.number(x)` and `.integer(n)` into a constant field (D4). No conversion from
  `.field` to any other type exists; a field wired into a number socket is refused by `connectionProblem` like any type
  mismatch.
- Fields broadcast like any item value: a list or tree of fields is allowed (a field per branch), and every node in §3
  treats its field input as an ordinary item socket.
- `Field.description` is a one-line readable recipe, e.g. `remap(distance(edges), 0…20 → 1…0) × noise(seed 4)`. Numbers
  use `Locale.messages`. The inspector shows it in a read-only "Field" row on any node with a field output, and the
  socket tooltip shows it shortened to 80 characters.
- Fields are computed, never saved (no format change for fields themselves; §5's images are the only format change).

### 2.2 Sampling

- One entry point: `FieldSampler.sample(_ field: Field, at points: [Vector3], kernel: any Kernel) async throws -> [Double]`.
  Every user of a field (nodes and previews) calls it; nothing evaluates a field point by point.
- It walks the expression tree once per batch, evaluating each node over the whole array (structure of arrays), and
  checks `Task.checkCancellation()` between chunks of 1,024 points.
- Deterministic: the same field and points give the same numbers on any machine and run; a result at a point never
  depends on the other points in the batch (batch and point-by-point agree exactly).
- Kernel distances (§3.1) are cached per distance node and per point set in a `FieldDistanceCache` (an actor owned by
  the evaluation context, keyed by the distance node's identity and a hash of the points, capped at 64 MB, least
  recently used dropped first), so re-sampling the same points after a downstream edit costs nothing.

## 3. Nodes

All in a new library category `NodeCategory.fields`, section "Fields". Each source fails with a node error (never a
silent zero) when its settings are invalid or its geometry is missing.

### 3.1 Sources

| Node | Inputs | Value at a point p |
|---|---|---|
| Distance Field | `target`: a point (vector), an edge set, a profile, a face set, or a solid; `mode` (segmented): Unsigned / Signed (solids only, default Signed for a solid) | distance from p to the target in mm. Signed for a solid: negative inside (D5). A profile is measured in 3D to its loops on its plane (its edges, not its area). |
| Linear Gradient | `plane`, `length` (> 0) | the signed distance from p to the plane along its normal ÷ length: 0 on the plane, 1 one length along the normal, unclamped. |
| Radial Gradient | `center` (vector), `radius` (> 0) | ‖p − center‖ ÷ radius: 0 at the centre, 1 at the radius, unclamped. |
| Noise Field | `seed` (integer), `scale` (mm, > 0), `octaves` (integer 1–6) | smooth gradient noise in 0…1 (simplex-style, 3D, fractal sum of octaves halving in size and amplitude, rescaled to 0…1). Hashing is `SeededRandom` (SplitMix64) with a new `Purpose` constant, pinned like 7a's; never the system generator. |
| Image Field | (7b-2) see §5 | the image's grey value in 0…1. |

Kernel distances: `Kernel` gains one batched query,
`func distances(from points: [Vector3], to target: DistanceTarget, signed: Bool) throws -> [Double]`, with
`DistanceTarget` `.solid(Solid)`, `.faces(FaceSet)`, `.edges(EdgeSet)`. `OCCTKernel` implements it with
`BRepExtrema_DistShapeShape` (and a point classifier for the sign) under `OCCTKernel.serialized`; `FakeKernel` implements
it exactly for its boxes and planar faces and straight edges, enough for every test. Distances to a point or a profile
are plain Swift maths and never reach the kernel.

### 3.2 Field maths

| Node | Inputs | Value |
|---|---|---|
| Add | `a`, `b` (fields) | a + b |
| Multiply | `a`, `b` | a × b |
| Min / Max | `a`, `b`, `mode` (segmented) | min or max |
| Remap | `field`, `fromLow`, `fromHigh`, `toLow`, `toHigh`, `clamp` (bool, default on) | linear map of the from range onto the to range, clamped to it when on; `fromLow == fromHigh` fails with a message |
| Clamp | `field`, `low`, `high` | clamped; `low > high` fails |
| Smooth Blend | `a`, `b`, `width` (≥ 0) | polynomial smooth minimum of a and b over `width` (width 0 is plain min) |

Because numbers convert to constant fields (D4), "multiply by 0.5" is Multiply with 0.5 typed into `b`.

### 3.3 Using fields

- **Sample Field.** Inputs: `field`; `at`, a `plane` socket with `tree` access (a vector converts to a plane through it,
  so points and placements both wire). Output: numbers in exactly the shape of `at`, paths and culled gaps included,
  each the field at the placement's origin. One `FieldSampler` call for the whole tree. A single plane gives one
  number. This is the graded-sizes path: Sample Field → Remap → a shortcut's size socket, paired per instance by
  `InstanceGrid`.
- **Cull by Field.** Inputs: `placements` (`tree` access), `field`, `mode` (segmented): Threshold / Probability;
  Threshold has `level` and `keep` (Above / Below); Probability has `seed`. Probability keeps an item when a
  `SeededRandom` draw (its own `Purpose`; stream = branch ordinal, index = the item's kept index, exactly as Random
  Reduce draws) is below the field's value clamped to 0…1. Output: the same nesting with culled lists where items went
  (7a §4: paths kept), so instance picks survive as with the other cull nodes. Listed under Fields and found by the
  palette's search beside the other cull nodes.
- **Field Scatter** (7b-3). A layout node (7a's rules: refuses a list in its single-value inputs through
  `singleValuesRefusal`, refuses over 2,000 through `PatternLimit`). Inputs: a region, either a picked flat face (the
  `face` setting and `FaceRegion`, as Face Pattern: holes and a `margin` respected) or a `profile` on its plane;
  `field`; `minSpacing` (> 0), `maxSpacing` (≥ minSpacing); `seed`. Spacing at a point is
  `minSpacing + clamp(field, 0, 1) × (maxSpacing − minSpacing)`. Points come from variable-radius Poisson-disk sampling
  (Bridson's method, candidates drawn with `SeededRandom` under its own `Purpose`): no two points closer than
  `minSpacing`, ever. Output: a flat list of placements on the region's plane, facing its normal (x axis the plane's),
  numbered in generation order. Changing the field, region or seed renumbers (D7). Same inputs, same points, always.

## 4. Errors and UI

- Messages follow the house style: "Distance Field needs a target: wire a point, edges, a profile, faces or a solid.",
  "Remap's from range is empty (both ends are 3 mm).", "Field Scatter would place 2,431 points; patterns are limited to
  2,000 instances." Numbers use `Locale.messages`.
- A field's inspector row shows its recipe (§2.1). Field Scatter's inspector help: "Points renumber when the field or
  region changes; a pick on a scattered instance may stop matching."
- Undo names: each node's inputs follow the existing rule (fixed labels, "Change Scale"); images add "Choose Image",
  "Relink Image", "Embed Image", "Link Image".

## 5. Images and file format 7 (7b-2)

- **Image Field** inputs: the `image` setting (`NodeSetting.image`, holding an `ImageReference`), `plane`, `width` and
  `height` (mm, > 0), `edges` (segmented): Tile / Clamp. The image is projected along the plane's normal: a point maps
  to plane coordinates, centred, scaled by width and height; outside the rectangle Tile repeats and Clamp takes the
  nearest edge pixel. Sampling is bilinear. Value: grey in 0…1.
- **`ImageReference`** is `.embedded(hash)` or `.linked(relativePath:absolutePath:)`, chosen per image in the
  inspector with a two-way switch (D9).
- **Embedded:** the file's original PNG or JPEG bytes, base64, in a new top-level `images` table keyed by the SHA-256 of
  the bytes (two nodes with one picture store it once), written sorted by key. Images no node uses are dropped on save.
  Copy and paste carries the images the copied nodes use, as group definitions travel today (`NodeClipboard`). A file
  over 16 MB or with a side over 8,192 px is refused when chosen, with a message, and the setting is unchanged (D10).
- **Linked:** the path relative to the document plus an absolute fallback (an unsaved document stores the absolute
  path only, and gains the relative one on first save). At each evaluation the file's modification date is checked; a
  change reloads it, otherwise the decoded image is reused (D11). A missing file fails the node: "Image 'vent-mask.png'
  wasn't found at …/textures/. Relink it in the inspector." with a Relink… button (a file chooser). Nothing is ever
  written beside a linked image.
- **Switching:** link → embed reads the file in (one undo step, "Embed Image"); embed → link asks where to save the
  bytes, writes them there, then links ("Link Image"). Choosing an embedded image marks the document edited.
- **Decoding:** ImageIO, in one file `Sources/CreatorNodes/Fields/GreyImageDecoder.swift` (the only ImageIO user),
  off the main actor, into `GreyImage` (width, height, 16-bit grey; Rec. 709 luminance with alpha premultiplied against
  black), cached by content hash.
- **Format 7:** `GraphFile.currentFormatVersion` becomes 7; it adds the `image` setting and the optional `images` table.
  Files are always written as 7; formats 1 to 6 open unchanged; an older MetalCreator refuses a format-7 file with its
  existing newer-version message.

## 6. Previews (7b-3)

- **When:** a selected node whose output is a field (sources, maths) or that takes one (Sample Field, Cull by Field,
  Field Scatter) shows a field preview, evaluated even before anything downstream is wired (as `LayoutPreview`). It goes
  when the selection changes. Field Scatter also shows its placements as 7a's axis-triad overlay.
- **Surface tint:** the part shown (Final, or the selected-node preview's part) is coloured by the field sampled at its
  mesh vertices in one batch. `ViewportItem` gains optional `fieldValues: [Float]` (one per vertex) and a
  `FieldRamp` (three colours and a range); the renderer adds one float vertex buffer and a ramp lookup in the shader.
  The Swift GPU structs mirror the MSL and `GPUDataTests` pins them. `CreatorViewport` still knows nothing about
  fields: numbers and colours only.
- **Slice plane:** a translucent quad through the part showing the field on a 256 × 256 grid (one texture). It starts
  on the field's own plane when it has one (a gradient's, an image's), else through the part's bounding-box centre on
  the axis plane nearest the camera's view direction. A viewport handle moves it along its normal; the legend's toggle
  switches XY / YZ / XZ or hides it. Its pose is view state in memory, never saved.
- **Ramp and legend:** the three theme roles `fieldLow`, `fieldMid`, `fieldHigh` in `CreatorStyle` (D13); `.mctheme`
  files without them read Dracula's values (no theme-format change); the theme editor lists them. Range: automatic
  (sampled min…max) by default; a signed distance centres `fieldMid` on 0; a "0…1" toggle fixes the range. The legend is
  a small glass card at the viewport's lower left: the ramp, min, mid and max with units where the field has them (mm
  for distances), the toggles, and "Preview sampled coarsely" when D14 applies.
- **Responsiveness:** sampling runs off the main actor and is cancelled by a newer request; the old tint stays until
  the new one is ready (no grey flash). Over 200,000 vertices, a deterministic subset of 200,000 is sampled and the rest
  take their nearest sampled vertex's value (D14). Kernel distances are cached (§2.2), so orbiting never resamples.

## 7. Performance

Measured by a new `FieldBench` suite (`Tests/CreatorAppTests/Bench`, release, idle Mac, `BENCH` lines, numbers into
`docs/verification/performance.md`):

| Case | Target |
|---|---|
| A five-node field (source, remap, noise, multiply, clamp), no kernel distance, 10,000 points | < 5 ms |
| Signed distance to a solid, 10,000 points | < 100 ms first, ≈ 0 cached |
| Field Scatter, 2,000 points on a face | < 50 ms |
| Edit to tinted preview on the bracket | < 150 ms (parent §7.3's budget) |

## 8. Testing

- **Value and maths:** every source and maths node against hand-worked values; batch equals point by point exactly;
  `Field.description` pinned; D4's conversion and refusal through `connectionProblem`.
- **Determinism:** noise and Probability cull pinned to fixed numbers (as `SeededRandomTests`); a longer point list
  changes no earlier sample; the new `Purpose` constants pinned.
- **Kernel distances:** on FakeKernel and OCCT: a 10 mm cube's signed distance is −5 at its centre and 0 on a face; an
  edge's distance at a known point; the cache returns without a kernel call on the same points.
- **Paths:** Sample Field and Cull by Field keep shape and culled gaps; an instance pick survives Cull by Field; a pick
  on a renumbered scattered instance warns.
- **Scatter:** no two points closer than `minSpacing`; density follows the field; same inputs, same points; limits and
  refusals.
- **Images:** embed and link round-trip through save and open; one picture stored once for two nodes; unused images
  dropped; missing link error and relink; modification date reload; oversize refusals; formats 1–6 open unchanged;
  clipboard carries images.
- **Previews:** model tests for the range rules, the slice's starting pose, which selections preview, cancellation
  keeping the old tint, the coarse cap; one headless render test that the tint changes pixels.
- **Acceptance (headless, OCCT):** a vented plate. Field Scatter on its top face with a distance field (denser near the
  edges), Sample Field → Remap → Hole Pattern sizes (larger towards the centre), Cull by Field (Probability, noise)
  thinning them. Asserts the instance count, sizes increasing towards the centre, and identical results on a second run.
- **Human checks:** group FI: tint, slice and legend look; relink flow; scatter look.

## 9. Build split (D15)

| Plan | Contents | Depends on |
|---|---|---|
| 7b-1 core | `Field`, `.field` socket and conversion, `FieldSampler`, `FieldDistanceCache`, `Kernel.distances` (OCCT and Fake), Distance / Linear / Radial / Noise sources, the maths nodes, Sample Field, Cull by Field, the `Fields` category, `FieldBench` (first three rows) | master |
| 7b-2 images | Image Field, `ImageReference`, `NodeSetting.image`, the `images` table, `GreyImageDecoder`, relink and switching, format 7 | 7b-1 merged |
| 7b-3 scatter and previews | Field Scatter, the surface tint, slice plane and legend, the three theme roles, the acceptance test, `FieldBench` row 4, human checks FI | 7b-1 merged; runs beside 7b-2 |

7b-2 and 7b-3 share `CLAUDE.md`, `docs/verification/human-checks.md` and `BuiltInNodes`; the second to merge keeps both.

## 10. Out of scope (later)

Scatter over curved surfaces or through a volume; vector fields (directions); fields as geometry (isosurfaces: 7c);
displacement (7d); Metal compilation of fields (7c); colour images (grey only); image formats beyond what ImageIO reads
as PNG and JPEG.

## Errata (7b-1: the fields core)

- **Graded sizes: Remap comes before Sample Field (§3.3, §8).** Remap takes and returns a field and there is no numeric Remap, so
  "Sample Field → Remap → a shortcut's size socket" cannot be wired (a field into a number socket is refused, field → number).
  The chain is a field → **Remap → Sample Field** → the size socket. §8's acceptance test (Sample Field → Remap → Hole Pattern
  sizes) is built in that order; `GradedHolesTests` (7b-1) already does it on OCCT.
- **A list of fields into Sample Field or Cull by Field is refused (§2.1).** The maths nodes broadcast a list or tree of fields;
  these two work on a whole tree through a `tree`-access socket, which cannot also broadcast, so any list in any of their inputs
  is refused in the layouts' words ("… takes single values, not lists: …"). A field per branch is a later change to both nodes.
- **A group's interface cannot carry a field under format 6 (D4, §5).** `"field"` in a format-6 file would not decode in an older
  build (CLAUDE.md: that bumps the format), so `GraphContent` refuses a `.field` interface socket; 7b-2's format 7 lifts it. A
  field chain wholly inside a group works.
- **The 100 ms of §7 row 2 is for analytic solids (planes, cylinders).** A smooth loft's B-spline faces cost about forty times a
  plate's per point; `field-2b` records it without a budget.
- **The distance cache (§2.2) counts the solids it keeps alive** (`Solid.estimatedBytes`) with its points and distances, so its
  64 MB bounds what it pins.
