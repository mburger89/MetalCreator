# KI-2: KiCad board import — solid components — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Import KiCad Board node's `components` output: one solid per footprint from its STEP, compressed STEP or IGES models,
scaled and placed as KiCad places them (top and bottom), with faces named so picks follow the footprint, and model files watched.

**Architecture:** `CreatorPCB` gains the pure parts (model path resolution, format detection, the placement chain). `Inflate` moves to
`CreatorGeometry/Compression` with a gzip reader. `Kernel` gains `readModel`, `scaled` and `compound`. `CreatorGraph` gains file
dependencies a node reports and the evaluator re-checks. The node reads each distinct model once (a cache keyed by the file's stamp),
scales it once per distinct scale, and places every copy with one `PlacementMoves.place`.

**Tech Stack:** Swift 6.4 (strict concurrency), Swift Testing, OpenCascade 7.9 through `Kernel` (STEP and IGES readers).

**Spec:** `docs/superpowers/specs/2026-11-15-kicad-import-design.md` (§Components, §Names that picks follow, §Files found while running,
§Limits, §Construction, KI-2). KiCad facts with source lines: `docs/superpowers/specs/2026-11-16-kicad-format-facts.md` §3 (the model
transform) and §7 (extensions).

## Global Constraints

- Worktree `/Users/maxburger/Developer/kicad-import/MetalCreator`, branch `kicad-ki-2`. Never touch `/Users/maxburger/Developer/MetalUI`.
- `CreatorPCB` stays portable and kernel-free (depends on `CreatorGeometry` only; Foundation `Data` and `JSONSerialization` allowed; no
  dictionary iteration where order reaches output).
- Board-local coordinates are KiCad's with y negated (y up) minus the chosen origin; z = 0 is the board's bottom, z = thickness its top.
- Errors and warnings are full sentences (`Locale.messages`, `Double.display`, `Int.display`). Swift Testing only. `swiftlint lint --strict`
  zero violations. Keep OCCT behind `Kernel`; every C allocation has a `*_free`, no C++ exception crosses into Swift; OCCT work runs under
  `OCCTKernel.serialized`.
- Limits: a STEP or IGES model at most 256 MB after decompression (`ModelLimits.maxSolidModelBytes = 256 << 20`); at most 10,000 distinct
  models per board (`ModelLimits.maxDistinctModels = 10_000`), over which the node refuses: "This board names more than 10,000 different 3D
  models."
- Never check in the user's boards, their models or any path under `/Users/maxburger`. Model fixtures are made in the test (OCCT writes a
  STEP or IGES of a solid built by the kernel into a temporary folder).
- No file format bump (format 13 already carries `TopoRole.imported(face:)`). Test-target count stays 14. Built-in nodes stay 89.
- Commit after each task with the trailer:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76`.

## Rulings (calls the spec leaves open)

- R1. Several solid models on one footprint are one solid (`Kernel.compound`); the k-th model's faces (k from 0, in file order of the
  readable models) are `imported(face: (k << 32) + index)`, so the first model's faces are plain indices.
- R2. A footprint's own scale (the 20260616 `transform` form) does not scale its models (KiCad's viewer applies the model's `scale` only).
- R3. A model scale with a component that is not finite and positive: that model is "couldn't be read … (its scale isn't positive)".
- R4. Until KI-3 and KI-4, a VRML, X3D or IDF model with no STEP twin, and a `kicad-embed://` model, count as "couldn't be read" with the
  reasons "VRML isn't read yet", "X3D isn't read yet", "IDF isn't read yet", "models stored in the board aren't read yet". (KI-3/KI-4 replace
  these.)
- R5. The vanished-pick message stays KI-1's "The picked feature no longer exists in the imported board." Naming the reference would need
  the pick resolver to know the board's references; deferred (ledger).
- R6. Variable precedence: the process environment, then `kicad_common.json`'s `environment.vars` (the newest KiCad version folder present),
  then the built-in defaults. `${VAR}` and `$(VAR)` both expand. `KIPRJMOD` is always the board's folder.
- R7. The models sit on the board's faces: top footprints at z = thickness, back ones at z = 0 (KiCad's exporter adds copper thickness;
  our board has none).

## Review Focus

1. A back-side footprint rotated by a non-right angle with a model offset and rotation on all three axes: the model's corners land where
   KiCad's chain puts them, not mirrored. Task 3 pins it by hand-worked numbers; Task 6 through OCCT.
2. A model path written on another OS (`C:\Program Files\KiCad\9.0\share\kicad\3dmodels\…` or the macOS app path) resolves on this one;
   `${KICAD8_3DMODEL_DIR}` with the variable unset resolves to the default folder. Task 2.
3. A model edited, deleted or added on disk reruns the node at the next evaluation, and an unrelated edit does not reread any model. Task 5,
   Task 6.
4. A damaged model (a truncated STEP, a gzip with a bad CRC, a `.step` that is a PNG) is one warning naming the file, never a failed node.
   Task 1, Task 4, Task 6.
5. The same switch model on 60 footprints is read and scaled once and placed with one kernel call. Task 6 counts reads.

---

### Task 1: `Inflate` moves to `CreatorGeometry/Compression`; a gzip reader

**Files:**
- Move: `Sources/CreatorImplicit/Import/Inflate.swift` → `Sources/CreatorGeometry/Compression/Inflate.swift` (make `Inflate`,
  `InflateError` and `inflate(_:size:isCancelled:)` public; behaviour unchanged). If a CRC-32 exists in `CreatorImplicit` (search `crc`),
  move it beside it as public `CRC32`; otherwise add one there.
- Create: `Sources/CreatorGeometry/Compression/Gzip.swift`
- Modify: `Sources/CreatorImplicit/Export/ZipReader.swift` (import the moved type), any other user.
- Move: `Tests/CreatorImplicitTests/InflateTests.swift` → `Tests/CreatorGeometryTests/InflateTests.swift`
- Create: `Tests/CreatorGeometryTests/GzipTests.swift` (with a test helper that writes a gzip of stored deflate blocks and its CRC).

**Interfaces — Produces:**
```swift
public enum GzipError: Error, Equatable { case notGzip, malformed, tooLarge(limit: Int), checksumMismatch, cancelled, allocationFailed }
public enum Gzip {
    public static func isGzip(_ data: Data) -> Bool                       // 1F 8B 08
    /// One member (RFC 1952): FEXTRA, FNAME, FCOMMENT, FHCRC honoured; ISIZE checked against `limit` before allocating;
    /// CRC-32 and ISIZE verified after. A second member is `malformed`.
    public static func decompress(_ data: Data, limit: Int, isCancelled: () -> Bool) throws(GzipError) -> Data
}
```

- [ ] **Step 1: Tests.** `GzipTests`: `roundTripsStoredBlocks` (payload "ISO-10303-21;…" of 70,000 bytes, two stored blocks); `readsNameAndComment`
  (FNAME and FCOMMENT set); `refusesBadCRC` → `.checksumMismatch`; `refusesSizeOverLimit` (ISIZE 300 with limit 200 → `.tooLarge(limit: 200)`
  before inflating); `refusesTruncated` → `.malformed`; `refusesNotGzip` → `.notGzip`; `refusesSecondMember` → `.malformed`;
  `cancels` → `.cancelled`. `InflateTests` keep passing after the move.
- [ ] **Step 2:** Run `swift test --filter CreatorGeometryTests` and `swift test --filter CreatorImplicitTests` (3MF tests unchanged). Expect pass.
- [ ] **Step 3:** `swiftlint lint --strict`; commit "Compression: Inflate moves to CreatorGeometry; a gzip reader".

### Task 2: Model paths, variables and formats (`CreatorPCB/Models`)

**Files:**
- Create: `Sources/CreatorPCB/Models/ModelPathResolver.swift`, `KiCadPathVariables.swift`, `ModelFormat.swift`
- Create: `Tests/CreatorPCBTests/ModelPathResolverTests.swift`, `KiCadPathVariablesTests.swift`, `ModelFormatTests.swift`

**Interfaces — Produces:**
```swift
public enum KiCadPlatform: Sendable { case macOS, linux, windows
    public static var current: KiCadPlatform { get }
    /// KiCad's library folder of 3D models for major version n (6...10): macOS "/Applications/KiCad/KiCad.app/Contents/SharedSupport/3dmodels",
    /// Linux "/usr/share/kicad/3dmodels", Windows "C:\\Program Files\\KiCad\\<n>.0\\share\\kicad\\3dmodels".
    public func libraryFolder(version n: Int) -> String
    /// Where kicad_common.json lives for version "n.0": macOS ~/Library/Preferences/kicad/<v>, Linux $XDG_CONFIG_HOME or ~/.config/kicad/<v>,
    /// Windows %APPDATA%\kicad\<v>.
    public func settingsFolder(version: String, environment: [String: String], home: String) -> String
}
public struct KiCadPathVariables: Sendable, Equatable {
    public var values: [String: String]
    /// `{"environment": {"vars": {"NAME": "path", …}}}`; `vars` may be null or absent (empty). Anything else unreadable → empty.
    public static func parsingCommonSettings(_ data: Data) -> KiCadPathVariables
    /// R6: process environment over settings over defaults (KICADn_3DMODEL_DIR → libraryFolder(version: n) for n in 6...10).
    public static func merged(environment: [String: String], settings: KiCadPathVariables, platform: KiCadPlatform) -> KiCadPathVariables
}
public enum ModelLocation: Sendable, Equatable { case files([String]) /* candidates, in order */; case embedded(name: String) }
public enum ModelPathResolver {
    /// `boardFolder` absolute. Order of candidates: the expanded path (relative → against boardFolder); if it is an absolute path into a
    /// known KiCad library folder of any platform and version (case-insensitive, `\` or `/`), the same relative part under this platform's
    /// folder for versions 10 down to 6 (Linux: one folder); for a `.wrl` or `.wrz`, each candidate's `.step` then `.stp` twin comes before
    /// it. `kicad-embed://name` → `.embedded(name:)`. An unknown `${VAR}` is left as written (and so not found).
    public static func locate(_ path: String, boardFolder: String, variables: KiCadPathVariables, platform: KiCadPlatform) -> ModelLocation
}
public enum ModelFormat: Sendable, Hashable { case step, stepGzip, iges, vrml, vrmlGzip, x3d, idf, unknown
    /// By name, case-insensitive: stp, step → step; stpz, stepz, stp.gz, step.gz → stepGzip; igs, iges → iges; wrl → vrml; wrz → vrmlGzip;
    /// x3d → x3d; idf → idf (facts §7). `.emn` → unknown (a board file).
    public init(fileName: String)
    /// The bytes agree with the name: STEP starts (after whitespace) "ISO-10303-21"; gzip 1F 8B; IGES has 'S' in column 73 of its first
    /// 80-column line; VRML "#VRML V1.0" or "#VRML V2.0"; X3D contains "<X3D" in its first 4 KB; IDF ".HEADER" first non-blank.
    public func matches(_ bytes: Data) -> Bool
}
```

- [ ] **Step 1: Tests.** `ModelPathResolverTests`: `${KIPRJMOD}/3dmodels/sw.step` with boardFolder `/b` → `["/b/3dmodels/sw.step"]`;
  `$(KIPRJMOD)/x.step` the same; relative `models/a.step` → `/b/models/a.step`; `${KICAD8_3DMODEL_DIR}/Button_Switch_SMD.3dshapes/SW.wrl`
  on `.linux` with no variable → `/usr/share/kicad/3dmodels/Button_Switch_SMD.3dshapes/SW.step`, `.stp`, `.wrl` in that order; the macOS
  absolute `/Applications/KiCad/KiCad.app/Contents/SharedSupport/3dmodels/A.3dshapes/a.step` on `.windows` → first
  `C:\Program Files\KiCad\10.0\share\kicad\3dmodels\A.3dshapes\a.step` … down to `6.0`, after the path as written; a Windows path
  `C:\Program Files\KiCad\9.0\share\kicad\3dmodels\A.3dshapes\a.step` on `.macOS` → the macOS folder; `kicad-embed://sw.step` →
  `.embedded(name: "sw.step")`; `${NOPE}/a.step` stays `${NOPE}/a.step` (resolved against nothing: absolute check fails, so relative →
  `/b/${NOPE}/a.step`); a settings variable `MYLIB=/libs` expands `${MYLIB}/x.step`. `KiCadPathVariablesTests`: parses vars; null vars →
  empty; junk → empty; environment wins over settings; settings win over defaults. `ModelFormatTests`: each extension and case; each
  `matches` true and a PNG's bytes false for every format.
- [ ] **Step 2:** `swift test --filter CreatorPCBTests` passes. Lint. Commit "KiCad import: model paths, variables and formats".

### Task 3: The placement chain (`CreatorPCB/Models/ModelPlacement.swift`)

**Interfaces — Produces:**
```swift
public struct ModelFrame: Sendable, Equatable { public var origin: Vector3; public var xAxis: Vector3; public var yAxis: Vector3; public var zAxis: Vector3
    public func apply(_ point: Vector3) -> Vector3 }   // origin + x·xAxis + y·yAxis + z·zAxis
public enum ModelPlacement {
    /// Board-local frame of a model (spec §Components, facts §3). With p = (place.origin − boardOrigin) and z0 = back ? 0 : thickness:
    /// M = T(p.x, p.y, z0) · Rz(angle) · [back: Rx(π)] · T(offset) · Rz(−rz) · Ry(−ry) · Rx(−rx)   (degrees; the scale is applied to the
    /// model beforehand, not here). `angle` is the footprint's (`Footprint.place.angle`), unchanged for a back footprint.
    public static func frame(of model: ModelReference, on footprint: Footprint, boardOrigin: Vector2, thickness: Double) -> ModelFrame
}
```
- [ ] **Step 1: Tests** (`Tests/CreatorPCBTests/ModelPlacementTests.swift`), each comparing `frame.apply(corner)` for the corners of a
  box (0…3, 0…2, 0…1) within 1e-9 to numbers worked by hand in the test's comment: identity (top, no offset) → corners + (p, thickness);
  top, angle 90 → (x, y) ↦ (−y, x); top, offset (1, 2, 3) and rotate (0, 0, 90) → Rz(−90) then offset; back, angle 0 → (x, y, z) ↦
  (x, −y, −z) + (p, 0); back, angle 30, offset (0.5, −1, 0.2), rotate (10, 20, 30) → the full chain multiplied out by hand (write the 3×3
  matrices in the comment); the frame is orthonormal and right-handed (det +1) for every case (never a mirror).
- [ ] **Step 2:** Implement with plain 3×3 maths (no simd needed). Run, lint, commit "KiCad import: the model placement chain".

### Task 4: Kernel: read a model, scale, compound

**Files:**
- Modify: `Sources/CreatorKernel/Kernel.swift` (requirements and default refusals), `FakeKernel` (refuses), `KernelUnavailable`.
- Create: `Sources/CreatorKernel/SolidModelFormat.swift`
- Modify: `Sources/COCCT/include/cocct.h`, `Sources/COCCT/cocct_mesh.cpp` (or a new `cocct_import.cpp`), `Sources/CreatorOCCT/OCCTKernel.swift`,
  `OCCTShape+Mesh.swift`; `Package.swift` (`"TKDEIGES"` in `occtLibraries`); `scripts/linux/Dockerfile` (`TKDEIGES` in
  `BUILD_ADDITIONAL_TOOLKITS`); confirm vcpkg's `opencascade` port ships `TKDEIGES` (`packaging/windows/vcpkg.json`, `.github/workflows/xp.yml`)
  and add a feature if it doesn't; `scripts/package-*.sh`/`package-windows.ps1` bundle the new library if they list libraries by name;
  `ShimPortabilityTests` must still pass.
- Create: `Tests/CreatorOCCTTests/ModelImportTests.swift`; a test-only shim `occt_test_write_iges` (beside the other `occt_test_*`).

**Interfaces — Produces:**
```swift
public enum SolidModelFormat: Sendable, Hashable { case step, iges }
// Kernel requirements:
/// A solid model read from bytes, in millimetres. Every face is tagged `TopoTag(tag, .imported(face: i))`, i its index in the shape's face
/// map as read; several bodies are one compound. A file with no shapes is refused: "The model contains no shapes.".
func readModel(_ data: Data, format: SolidModelFormat, tag: NodeTag) throws -> Solid
/// Scaled about the origin by `factors` (all finite and > 0, else `KernelError` "The scale must be greater than 0."): uniform is a
/// similarity, uneven OCCT's general transform. Face tags are kept face for face.
func scaled(_ solid: Solid, by factors: Vector3, tag: NodeTag) throws -> Solid
/// One solid holding all of `solids`, every tag kept.
func compound(_ solids: [Solid], tag: NodeTag) throws -> Solid
```
Default implementations throw `KernelError.unsupported("reading 3D models")`, `("scaling")`, `("compounds")`; `FakeKernel` uses them.
Reading from bytes: STEP through `STEPControl_Reader::ReadStream` over an `std::istringstream`; IGES through `IGESControl_Reader`'s stream read
if OCCT 7.9 has one, else write the bytes to a unique file in `std::filesystem::temp_directory_path()` and remove it after (always, also on
failure). Both call `occt_initialize()` first (millimetres). The STEP reader's own failure is "The STEP model couldn't be read."; IGES "The IGES
model couldn't be read.".

- [ ] **Step 1: Tests (OCCT).** `readsStepFromBytes`: an L-shaped extrusion exported to STEP (temp folder), read back from its bytes: same face
  count, volume within 1e-6, every face tagged `.imported(face: i)` with i = 0..<n in order; `readsIgesFromBytes` the same through
  `occt_test_write_iges` (volume within 1e-3, face count equal); `refusesGarbage` (a PNG's bytes, STEP format) → the sentence;
  `refusesEmptyStep` (a valid header, no shapes) → "The model contains no shapes."; `scalesUniformly` (×2: volume ×8, tags unchanged, face kinds
  unchanged); `scalesUnevenly` ((1, 2, 3): volume ×6 within 1e-6, same face count and tags); `refusesZeroScale`; `compoundKeepsTags` (two read
  models, the second retagged with `(1 << 32) + i`: the compound holds both sets of tags and the summed volume). FakeKernel: each refuses
  `unsupported`.
- [ ] **Step 2:** Implement, run `swift test --filter CreatorOCCTTests` and `--filter CreatorKernelTests`. Run `scripts/linux-test.sh build`
  (the OCCT image rebuilds with TKDEIGES; let it). Lint. Commit "Kernel: read STEP and IGES models, scale, compound".

### Task 5: File dependencies (`CreatorGraph`)

**Files:**
- Create: `Sources/CreatorGraph/Files/FileDependency.swift`, `Sources/CreatorGraph/Images/ImageResolver+Models.swift`,
  `Sources/CreatorGraph/BoardFiles/ModelFileProblem.swift`
- Modify: `NodeOutputs.swift`, `NodeResult.swift`, the evaluator's cache lookup (find where a cached `NodeResult` is reused after `gather`).
- Create: `Tests/CreatorGraphTests/FileDependencyTests.swift`

**Interfaces — Produces:**
```swift
public struct FileDependency: Sendable, Hashable { public var path: String; public var stamp: ImageStamp }
// NodeOutputs: public var dependencies: [FileDependency] = []   — files the run read or looked for, stamped by the node BEFORE reading.
// NodeResult:  public var dependencies: [FileDependency] = []
// Evaluator: a cached result is reused only if every dependency's `ImageResolver.stamp(ofFileAt: path)` now equals its recorded stamp;
//            otherwise the node runs again (and so does what is downstream of it, as for any rerun).
extension ImageResolver {
    public static func stamp(ofFileAt path: String) -> ImageStamp              // as stamp(of: .linked(relativePath: nil, absolutePath: path))
    /// Folder of a linked file (the board's), nil for embedded.
    public func folder(of reference: ImageReference) -> URL?
    /// A regular file of at most `limit` bytes (openedRegularFile), stamped first; the bytes and the stamp taken before reading.
    public static func modelFile(at path: String, limit: Int) throws(ModelFileProblem) -> (data: Data, stamp: ImageStamp)
}
public enum ModelFileProblem: Error, Equatable { case missing, notAFile, tooLarge(limit: Int), unreadable(String)
    public var reason: String }   // "it wasn't found", "it isn't a file", "it is larger than 256 MB", the read error's words
```
- [ ] **Step 1: Tests** with a test node type registered in the test (reads a file path from a text setting and returns its size as a
  number, reporting the dependency): unchanged file → the second evaluation reuses the result (the node's run count stays 1); file rewritten
  with a new size → reruns; file deleted → reruns (and fails or warns as the node says); a missing file that appears → reruns; an unrelated
  node's edit → no rerun. `NodeResult.dependencies` carries what the node reported.
- [ ] **Step 2:** Run `swift test --filter CreatorGraphTests`. Lint. Commit "Graph: file dependencies a node reports are re-checked each evaluation".

### Task 6: The node's components

**Files:**
- Create: `Sources/CreatorNodes/Import/BoardComponents.swift` (gathering, reading, scaling, placing), `ComponentModelCache.swift`,
  `KiCadSettingsFiles.swift` (finding and reading `kicad_common.json`)
- Modify: `ImportKiCadBoardNode.swift` (read the `components` toggle; fill `components`; dependencies; warnings; facts), `BoardFacts.swift`;
  `Sources/CreatorPCB/Identity/KeyAssigner.swift` (each footprint gets `identity` "fp:<token>" from `footprintTokens`; add `identity` to
  `Footprint`, refused like the others on a collision)
- Create: `Tests/CreatorNodesTests/ImportKiCadComponentsTests.swift`, `ImportKiCadComponentPickTests.swift`; extend `Support/KiCadBoardText.swift`
  with a footprint that carries `(model …)` lines.

**Behaviour:**
- `components` off: no model is looked for; `components` is an empty list; no component warnings; no dependencies besides the board.
- For each footprint in natural reference order (`BoardHoles.naturallyOrdered`), each non-hidden model: `ModelPathResolver.locate` with the
  board's folder, `KiCadPathVariables.merged(environment: ProcessInfo…environment, settings: KiCadSettingsFiles.variables(), platform: .current)`.
  Candidates are tried in order: each tried path's stamp is a dependency; the first `.file` stamp is read. `kicad_common.json`'s path (found or
  not) is a dependency too.
- Format: `ModelFormat(fileName:)` of the found path; `.stepGzip` is gunzipped (`Gzip.decompress`, limit 256 MB) then read as STEP; the
  bytes must `matches` (else "couldn't be read … (the file isn't a STEP model)" in the format's word). R4 for the rest.
- `ComponentModelCache` (actor, `shared`, LRU by `Solid.estimatedBytes`, 512 MB): read solids keyed by (`ImageStamp`, `SolidModelFormat`),
  scaled ones by (that key, scale); a failure is remembered per stamp like `KiCadBoardCache`'s problems (a read error that isn't the file's
  contents is not). `readModel` is called with tag `NodeTag(node: context.node.id, item: 0)`; the footprint's item comes from placing.
- Placement: per model, `ModelPlacement.frame(…)` mapped through the board's frame (`frame.point`/directions, the same `Plane` the board uses)
  into a world `Plane(origin:normal: zAxis, xAxis:)`; all copies in one `PlacementMoves.place(tools, planes:, items: footprint keys, placedBy:
  context.node.id, …)`; R1's retag before a `compound` for footprints with several models.
- Warnings (each said once, names in natural order, at most 8 then "… (and N more)"): "N components have no 3D model: C1, C2, R4." (a
  footprint whose models are all hidden or that has none); "N models weren't found: <path as written>, …."; "N models couldn't be read:
  <file name> (<reason>), …." Singulars: "1 component has no 3D model: H1.", "1 model wasn't found: …", "1 model couldn't be read: …".
- Facts: "Components" becomes "<placed> placed, <withModel> with a 3D model, <without> without" (`Int.display`).
- More than 10,000 distinct model paths → the refusal in Global Constraints.

- [ ] **Step 1: Tests (OCCT, `#if canImport(CreatorOCCT)`)**, each writing an asymmetric L block STEP into a temp folder beside a board text
  that names it as `${KIPRJMOD}/models/l.step`: `placesTopComponent` (bounds of the component equal the hand chain of Task 3 through the board
  frame, origin Board centre); `placesBackComponentRotated` (angle 30, offset and rotate on three axes: the eight box corners of the read block,
  pushed through the chain, match the component's vertices' bounding box within 1e-6); `scalesBeforePlacing` (scale (2, 1, 1): bounds width
  ×2); `readsCompressedStep` (the same STEP gzipped via Task 1's test helper, named `l.stp.gz`); `readsIges`; `twoModelsOneCompound`
  (faces of the second carry `(1 << 32) + i`); `sixtyCopiesReadOnce` (60 footprints, one model: the cache's read count is 1 and scale count 1);
  `warnsMissingAndUnreadable` (a missing path and a `.step` holding PNG bytes: the two sentences exactly); `warnsNoModel` (H1, H2 without
  models: "2 components have no 3D model: H1, H2."); `componentsOffReadsNothing`; `hiddenModelSkipped`; `wrlTwinReadAsStep` (a `.wrl` path
  whose `.step` twin exists); `modelEditedOnDiskReruns` (rewrite the STEP scaled ×2 → next evaluation's component is larger; an unrelated
  edit → no reread); `missingModelAppearing` (warned, then the file is written → next evaluation places it); `vrmlWithoutTwinIsR4`.
  Pick test: a face pick on J1's component survives adding footprint J2 before it in the file and moving R1.
- [ ] **Step 2:** FakeKernel tests: with `FakeKernel`, models count as "couldn't be read … (reading 3D models isn't supported by this kernel
  yet)" and the board still builds.
- [ ] **Step 3:** Run `swift test --filter CreatorNodesTests`, `--filter CreatorPCBTests`. Lint. Commit "KiCad import: components from STEP and IGES".

### Task 7: Docs and the whole suite

- Modify: `CLAUDE.md` (the KI paragraph: KI-2 code done, components, `Kernel.readModel`/`scaled`/`compound`, `FileDependency`, `Inflate` and
  `Gzip` in `CreatorGeometry/Compression`, TKDEIGES; the CreatorPCB module line gains `Models/`), `docs/verification/human-checks.md` group KI
  (add: library and project models both appear; a back-side part sits under the board; a model edited on disk updates; with KiCad installed,
  `kicad-cli pcb export step` matches within 0.01 mm), `docs/mcp.md` only if a tool's output text changes.
- Run the full `swift test` (exit 0, 14 "Test run with" lines, no "recorded an issue" or "failed after"), `scripts/linux-test.sh test`
  (14 lines), `swiftlint lint --strict`. Commit "Docs: KI-2 components".
