# Mesh import Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An Import Mesh node reads binary STL, ASCII STL and 3MF into `mesh` values on every platform, so zebra, Section, Measure, Decimate, the checks and export work on a file from elsewhere.

**Architecture:** Readers live in `CreatorImplicit/Import` and produce a welded, unplaced `TriangleMesh`. The file reference reuses the Image Field's whole path: `ImageReference`, `ImageResolver`, its stamp in the cache key, the embedded-bytes table and pool, path rewriting on save and the clipboard. Own inflate and own XML scanner, so no new library ships.

**Tech Stack:** Swift 6.4, Swift Testing, MetalUI. No OpenCascade.

**Spec:** `docs/superpowers/specs/2026-11-03-mesh-import-design.md`.

**Three PRs:** MI-1 (Tasks 1–7), MI-2 (Tasks 8–11), MI-3 (Task 12). Each merges on its own.

## Refinements to the spec (add to it as an erratum in Task 7)

These change no behaviour the spec promises.

1. **One embedded table.** `ConstantValue.meshFile` holds an `ImageReference`, and embedded mesh bytes sit in the document's existing `images` table and pool, which are keyed by hash and don't care what the bytes are. There is no `MeshFileReference` and no `meshFiles` table. This replaces a parallel copy of the reference, resolver, table, pool, clipboard and evaluator plumbing.
2. **Files are read, not mapped** (final review, spec erratum 2). A file is read whole into `Data` through the descriptor `openedRegularFile` opened and checked, under the 1 GB limit; a mapped file truncated during a parse is a SIGBUS. The zip reader is extended and works over that `Data`.
3. **`EdgeCounts`.** Closed-ness comes from a sort-based count of edges (below), since the checks call it on every run and `MeshTopology`'s dictionaries are slow at these sizes.

## Global Constraints

- Swift Testing only; `swiftlint lint --strict` reports 0; prefix `swift` and `swiftlint` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- 12 "Test run with" lines on macOS and Linux; the only allowed failure is `HLSLEngineTests.onTheCutTheHLSLEngineAgreesWithTheMetalEngine`.
- Everything in `CreatorImplicit/Import` is portable: `ImplicitPortabilityTests` must pass. No `XMLParser` or `Compression` outside tests. Keep async wrappers thin and heavy work in synchronous helpers (the Windows compiler notes in CLAUDE.md).
- Limits, exact: file 1 GB (`1 << 30`), 10,000,000 triangles, embedded file 64 MB, zip entry 2 GB, component nesting depth 32, crease angle 30 degrees, warning above 2,000,000 triangles.
- `GraphFile.currentFormatVersion` becomes 12. Files of formats 1 to 11 open unchanged.
- Messages use `Locale.messages`, and all the copy below is exact. Nothing the Import Mesh node says contains the word "image".
- Commit with explicit paths, merge commits only. Commit trailer:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76`.

## Review Focus

1. A binary STL whose 80-byte header starts with "solid", or an ASCII STL whose size happens to fit 84 + 50 × a count: each reads as what it is (Task 1).
2. A document opened where its linked mesh is missing: the document opens, the node says which file and offers Relink…, and other nodes evaluate (Task 6).
3. Dragging `placement` on a large mesh: the file is not read again, and the mesh changes id so the viewport redraws it (Task 3).
4. File ▸ Import Mesh… while inside a group, where an Output node is refused, and in sketch mode: inside a group it inserts the node alone, and in sketch mode the item is disabled (Task 6).
5. A unit or placement that overflows `Float`, such as a coordinate of 1e38 in metres: refused in words, no infinities reach the viewport (Task 3).

---

## MI-1: STL

### Task 1: The STL reader and welding

**Files:** Create `Sources/CreatorGraph/MeshFiles/MeshImportLimits.swift`, `Sources/CreatorGraph/MeshFiles/MeshImportProblem.swift`, `Sources/CreatorImplicit/Import/ImportedMesh.swift`, `Sources/CreatorImplicit/Import/STLReader.swift`, `Sources/CreatorImplicit/Import/ExactWeld.swift`, `Sources/CreatorImplicit/Mesh/EdgeCounts.swift`. Test `Tests/CreatorImplicitTests/STLReaderTests.swift`, `ExactWeldTests.swift`, `EdgeCountsTests.swift`.

**Interfaces, produces:**
- `MeshImportLimits`: `maxFileBytes`, `maxTriangles`, `maxEmbeddedBytes`, `warnTriangles`.
- `MeshImportProblem: Error`, with `message`. Cases and copy: `notAMeshFile` "This file isn't an STL or 3MF."; `endsEarly` "The STL ends early."; `badNumber(line: Int)` "The STL has a bad number on line N."; `noTriangles` "This file holds no triangles."; `tooManyTriangles(Int)` "This file has N triangles; Import Mesh takes at most 10,000,000."; `tooLarge` "This file is larger than the 1 GB limit."; `coordinatesOverflow` "This file's coordinates are too large at these units."; `notChosen` "Choose a mesh file."; `missing(name:folder:)`, `notAFile(name:)`, `unreadable(name:reason:)`, `embeddedMissing`, which reword `ImageProblem`'s sentences with "file" for "image".
- `struct ImportedMesh: Sendable { var mesh: TriangleMesh; var droppedTriangles: Int; var unit: Double? /* mm per file unit; nil for STL */; var ignoredExtras: Bool }`.
- `enum STLReader { static func read(_ data: Data, isCancelled: () -> Bool) throws -> ImportedMesh }`.
- `enum ExactWeld { static func weld(corners: [SIMD3<Float>]) -> (positions: [SIMD3<Float>], triangles: [UInt32], dropped: Int) }`: keyed by `Float` bits with -0 read as +0; a triangle with a repeated vertex is dropped and counted.
- `struct EdgeCounts { init(_ mesh: TriangleMesh); let open, overfull, flipped: Int; var isClosed: Bool }`: sorts 3 × triangles `UInt64` edge keys, with the direction in a low bit; no dictionary.

- [ ] **Step 1: Write the failing tests.** `aBinaryStartingWithSolidIsBinary`; `anAsciiWhoseSizeFitsTheBinaryFormulaIsAscii` (padded to 84 + 50n: the size check also needs the count at byte 80 to equal n, and it won't); `asciiToleratesCRLFOddSpacingAndExponents` (`1.5E+01`); `aTruncatedBinaryEndsEarly` (a header count above what the size holds, and not text: `.endsEarly`, without allocating); `aCountAboveTheLimitRefuses` (`.tooManyTriangles` from the header alone, on 84 bytes); `aBadNumberNamesItsLine`; `aNonFiniteBinaryCoordinateRefuses` (NaN in a binary file: `.notAMeshFile`, since it has no line to name); `anEmptySolidHoldsNoTriangles`; `theFacetNormalIsIgnored`; `aRoundTripThroughSTLWriterIsExact` (a Mesh-node style closed box: same positions set, same triangle set, `EdgeCounts.isClosed`); `cancellationStopsAParse`. Weld: `minusZeroWeldsWithZero`, `nearlyEqualIsNotWelded`, `aZeroAreaTriangleIsDroppedAndCounted`. Edges: `aBoxIsClosed`, `aMissingFaceCountsThreeOpenEdges`, `aFlippedFaceCountsThree`, `threeFacesOnAnEdgeCountOneOverfull`, `agreesWithMeshTopologyOnTheseMeshes`.
- [ ] **Step 2: Run.** `swift test --filter 'STLReaderTests|ExactWeldTests|EdgeCountsTests'`. Expected: compile failure on the missing types.
- [ ] **Step 3: Implement** the types above. Binary if `data.count >= 84` and `84 + 50 × count == data.count`; else ASCII if the first non-space word is `solid`; else `.notAMeshFile` or, when the header has a count above what the size holds and bytes aren't text, `.endsEarly`. Parse ASCII numbers from bytes (no `strtod`: it is locale dependent). Check `isCancelled` every 64,000 triangles.
- [ ] **Step 4: Run again.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(mesh): read STL and weld by exact position`.

### Task 2: The file reference and format 12

**Files:** Modify `Sources/CreatorGraph/ConstantValue.swift`, `NodeSetting.swift`, `GraphFile.swift`, `Evaluator+Running.swift`, `Images/Graph+Images.swift`, `Images/ImageResolver.swift`, `Sources/CreatorEditor/EditorModel+Editing.swift`. Test `Tests/CreatorGraphTests/MeshFileSettingTests.swift`.

**Interfaces, produces:**
- `ConstantValue.meshFile(ImageReference)`, and `ConstantValue.fileReference: ImageReference?`, which answers for both `.image` and `.meshFile`. Every site that matched `.image(let reference)` for paths, stamps, hashes or the clipboard now reads `fileReference`.
- `NodeSetting.meshFile`, name `"meshFile"`, added to `reservedForSockets`.
- `ImageResolver.mappedBytes(of: ImageReference) throws(MeshImportProblem) -> Data`: embedded bytes, or a regular file read whole up to `maxFileBytes` through the descriptor the regular-file checks opened. `ImageResolver.meshFileBytes(ofFileAt: URL)` likewise. (Named `mappedBytes` before the final review.)

- [ ] **Step 1: Write the failing tests.** `aMeshFileSettingRoundTripsAtFormat12` (linked and embedded); `formatsOneToElevenOpenUnchanged`; `anEmbeddedMeshFileIsWrittenOnlyWhenUsed`; `aLinkedMeshFileEditedOnDiskRunsItsNodeOnce` (nothing else runs); `savingElsewhereRewritesARelativePath`; `theClipboardCarriesAnEmbeddedMeshFile`; `aPathToAFolderOrDeviceIsRefused`; `aFileOverOneGigabyteIsRefusedWithoutReading` (a sparse temp file, skipped where sparse files aren't); `aMissingFileSaysSoWithoutTheWordImage`.
- [ ] **Step 2: Run** `swift test --filter MeshFileSettingTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Bump the format and add its line to `GraphFile`'s history comment and CLAUDE.md's format paragraph. Update `ImageReference`'s and `images`' doc comments to say a mesh file uses them too.
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorGraphTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(graph): a mesh file setting, file format 12`.

### Task 3: The Import Mesh node

**Files:** Create `Sources/CreatorNodes/Implicit/MeshTools/ImportMeshNode.swift`, `ImportedMeshCache.swift`, `ImportUnits.swift`. Modify `Sources/CreatorNodes/BuiltInNodes.swift`, `Sources/CreatorGraph/InspectorControl.swift` (`.meshFile(SocketName)`). Test `Tests/CreatorNodesTests/ImportMeshNodeTests.swift`.

**Interfaces, consumes:** `STLReader`, `ImageResolver.meshFileBytes`. **Produces:**
- `ImportMeshNode`, typeID `creator.importMesh`, display name "Import Mesh", category `.mesh`. Inputs `placement` (`.plane`, default `.xy`), `units` (`.integer`, default 0, `.segmented` over `ImportUnits.options`: "From file", "mm", "cm", "m", "in"). Output `mesh`, list. Inspector sections "File" (`.meshFile(NodeSetting.meshFile)`) and "Placement" (`.planePicker("placement")`, `.segmented("units")`). `readsMeshQuality` stays false.
- `actor ImportedMeshCache { static let shared; func mesh(for stamp: ImageStamp, read: @Sendable () throws -> ImportedMesh) async throws -> ImportedMesh }`: 1 GB LRU on `estimatedBytes`, at most 256 remembered failures, a read error not remembered, the shape of `GreyImageCache`.
- Output meshes: `quality: .export`, `resolution: 0`, `source: nil`, `creaseAngle: 30` once Task 5 lands, and `extraFacts` Triangles, Vertices, Size ("x × y × z mm"), Closed ("Yes" or "No"), File.
- Warnings, exact, with singular forms: "This mesh isn't closed: N open edges." "This mesh has N edges shared by more than two faces." "N edges join faces flipped against each other." (singular "1 edge joins faces flipped against each other.") "N degenerate triangles were dropped." "This mesh has N triangles, so the view may be slow."

- [ ] **Step 1: Write the failing tests.** `readsAnSTLOntoTheDefaultPlane`; `noFileChosenSaysSo` (`.notChosen`'s words); `factsAreRight`; `eachWarningFires` with its exact text; `unitsScale` (in: 25.4, m: 1000, cm: 10, From file on an STL: 1); `placementMovesIt` (a plane at z = 5 with a turned x axis, vertex by vertex); `movingPlacementDoesNotReadTheFileAgain` (delete the file after the first run: a new placement still builds, and the mesh id differs); `anOverflowingUnitRefuses` (1e38 at metres: `.coordinatesOverflow`); `aBrokenFileFailsOnceUntilItChanges`; `twoNodesOnOneFileShareTheRead`; `aNonNumberPlacementRefuses` as the Image Field does; registry count in the tests goes from 85 to 86.
- [ ] **Step 2: Run** `swift test --filter ImportMeshNodeTests`. Expected: FAIL.
- [ ] **Step 3: Implement.** Scale and place in `Double`, narrow to `Float`, refuse non-finite. Read off the main actor with `ImportedMeshCache`. Update CLAUDE.md's node count.
- [ ] **Step 4: Run** the filter and `swift test --filter CreatorNodesTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mesh): the Import Mesh node`.

### Task 4: Mesh tools on an imperfect mesh

**Files:** Modify `Sources/CreatorNodes/Implicit/MeshTools/CheckThinWallsNode.swift`, `CheckTrappedVolumesNode.swift`, `MeshToSolidNode.swift`, `Sources/CreatorApp/Export/` (the sheet's warning). Create `Tests/CreatorNodesTests/ImperfectMeshTests.swift`, `Tests/CreatorAppTests/ImperfectMeshExportTests.swift`.

**Interfaces, consumes:** `EdgeCounts`.

- [ ] **Step 1: Write the failing tests,** one per row and imperfection (open, flipped, over-full), each on a real `TriangleMesh`: `checkThinWallsRefuses` "Check Thin Walls needs a closed mesh."; `checkTrappedVolumesRefuses` "Check Trapped Volumes needs a closed mesh."; `meshToSolidRefuses` "Mesh to Solid needs a closed mesh." (before the kernel is called, `FakeKernel`'s log empty); `decimatePinsOpenEdges`; `decimateOnAnOverfullEdge` (keeps the surface within tolerance, or refuses "Decimate can't work on a mesh with edges shared by more than two faces."; the test decides which: write it first as the first, and only move to the refusal if the invariant can't hold); `sectionDrawsOpenOutlines`; `measureOnAnOpenMesh`; `exportSTLWritesAnOpenMesh`; `export3MFWarnsAnOpenMesh` "This mesh isn't closed, so the 3MF may not print." and still writes; `aClosedMeshIsUnaffected` for each.
- [ ] **Step 2: Run** `swift test --filter 'ImperfectMeshTests|ImperfectMeshExportTests'`. Expected: FAIL on the refusal and warning cases.
- [ ] **Step 3: Implement** the guards. A preview of a Mesh node's output gets the same check, at the cost `EdgeCounts` measured.
- [ ] **Step 4: Run** with `swift test --filter 'CreatorImplicitTests|CreatorNodesTests'`. Expected: PASS, and the lightweight bracket acceptance test unchanged.
- [ ] **Step 5: Commit** `feat(mesh): the tools answer in words on an imperfect mesh`.

### Task 5: Hard edges on display

**Files:** Modify `Sources/CreatorImplicit/Mesh/TriangleMesh.swift` (`creaseAngle: Double?`, default nil), `Sources/CreatorApp/MeshPreview/TriangleMesh+Display.swift`, `ImportMeshNode.swift`. Test `Tests/CreatorAppTests/MeshDisplayCreaseTests.swift`.

**Interfaces, produces:** `displayMesh` keeps one triangle per triangle, in order, so `displayFaces`, highlights and `triangleFaces` still line up. With `creaseAngle` set and `normals` empty it duplicates a position for each group of a vertex's faces that isn't joined by an edge within the angle. A mesh with no `creaseAngle` is byte-identical to today.

- [ ] **Step 1: Write the failing tests.** `aWeldedBoxHasSixFlatNormals` (24 display vertices, each normal a face's); `aSphereStaysSmooth` (a fine sphere: no duplicates); `aThirtyOneDegreeEdgeSplitsAndATwentyNineDoesNot`; `theMeshNodesDisplayIsUnchanged`; `triangleOrderIsKept`; `aZebraRenderOfAnImportedBoxHasFlatFaces` (a Metal offscreen render through `ViewportZebraRenderTests`' path, behind `canImport(Metal)`; this also settles whether a mesh item is striped at all: if it isn't, make it so here and correct CLAUDE.md's line either way).
- [ ] **Step 2: Run** `swift test --filter MeshDisplayCreaseTests`. Expected: FAIL.
- [ ] **Step 3: Implement,** setting `creaseAngle: 30` in the node.
- [ ] **Step 4: Run** the filter and `swift test --filter 'CreatorViewportTests'`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mesh): an imported mesh's sharp edges draw sharp`.

### Task 6: The app: inspector, actions, File ▸ Import Mesh…

**Files:** Modify `Sources/CreatorGraph/InspectorAction.swift` (`chooseMeshFile`, `relinkMeshFile`, `embedMeshFile`), `Sources/CreatorEditor/InspectorBuilder.swift`, `Sources/CreatorGraph/UndoName*.swift`, `Sources/CreatorApp/AppCommands.swift`. Create `Sources/CreatorApp/AppModel+MeshFiles.swift`, `Sources/CreatorApp/ContentType+Meshes.swift` (`.stl`; `.threeMF` if one isn't already declared). Test `Tests/CreatorEditorTests/MeshFileRowsTests.swift`, `Tests/CreatorAppTests/MeshFileActionsTests.swift`.

**Interfaces, produces:**
- Rows: `.readOnly("File", …)`: "No file chosen" with Choose File…; "Linked · name.stl" with Relink… and Embed; "Embedded · a1b2c3d4" with Choose File…. Choose File… links.
- `AppModel.performMeshFile(_:on:using:)`, `AppModel.importMesh(using:)`, sharing `performImage`'s target and re-entrancy rules by extracting them rather than copying.
- Undo names: "Import Mesh", "Choose Mesh File", "Relink Mesh File", "Embed Mesh File". `AppProblem` title "That mesh file can't be used".
- Embed over the limit: "This file is larger than the 64 MB limit for embedding."
- Panel: `.stl` only in MI-1. Until MI-2, a zip reads as "This file isn't an STL or 3MF.".

- [ ] **Step 1: Write the failing tests.** `eachStateShowsItsRowsAndButtons`; `chooseLinksAndIsOneUndoStep`; `relinkKeepsPlacement`; `embedStoresTheBytesAndUndoRestoresTheLink`; `embedOverTheLimitRefusesAndChangesNothing`; `importMeshInsertsNodeAndOutputAsOneStep`; `importMeshInsideAGroupInsertsTheNodeAlone` (Review Focus 4); `importMeshIsDisabledInSketchMode`; `aMissingLinkOpensTheDocumentAndOffersRelink` (Review Focus 2, other nodes evaluate); `aFileDialogDeclaresItsExtensions`.
- [ ] **Step 2: Run** `swift test --filter 'MeshFileRowsTests|MeshFileActionsTests'`. Expected: FAIL.
- [ ] **Step 3: Implement.** Add the new actions to every exhaustive switch.
- [ ] **Step 4: Run** `swift test --filter 'CreatorEditorTests|CreatorAppTests'`, with `WarmWorkPinTests` skipped only if it hangs as it has before, and say so. Expected: PASS.
- [ ] **Step 5: Commit** `feat(app): import a mesh, link it, relink it, embed it`.

### Task 7: MI-1 records and PR

**Files:** `CLAUDE.md`, `docs/verification/human-checks.md`, the spec, `README` if it lists formats.

- [ ] **Step 1:** Add the plan's refinements to the spec as a dated erratum. Update CLAUDE.md: a Project state paragraph, the node count, the `TriangleMesh` watertight promise now being the Mesh node's only, format 12. Add human checks MI-1 to MI-8 from the spec, with the 3MF parts marked for MI-2.
- [ ] **Step 2:** Full `swift test` (12 lines, only the allowed failure), `swiftlint lint --strict` (0), then `docker ps` and `PATH="/Applications/OrbStack.app/Contents/MacOS/xbin:$PATH" XP_TRACK=mi-1 scripts/linux-test.sh test` (12 lines).
- [ ] **Step 3:** Commit `docs(mesh): records for STL import`. Open the PR; merge when CI is green.

---

## MI-2: 3MF

### Task 8: Inflate

**Files:** Create `Sources/CreatorImplicit/Import/Inflate.swift`. Test `Tests/CreatorImplicitTests/InflateTests.swift`.

**Interfaces, produces:** `enum Inflate { static func inflate(_ input: UnsafeRawBufferPointer, size: Int, isCancelled: () -> Bool) throws(InflateError) -> Data }`, RFC 1951, stopping at `size`. `InflateError`: `.malformed`, `.tooLong`, `.tooShort`, `.cancelled`.

- [ ] **Step 1: Write the failing tests.** `storedFixedAndDynamicBlocks`; `agreesWithCompression` (under `canImport(Compression)`, random and repetitive data at several sizes); `pinnedStreamsAgreeEverywhere` (bytes in the test, with a SHA-256 of the output); `aBombStopsAtTheDeclaredSize` (`.tooLong`, with the output never above `size`); `aDistanceBeforeTheStartIsMalformed`; `badCodeLengthsAreMalformed`; `aTruncatedStreamIsMalformedNotATrap`; `everyByteFlippedNeverTraps` (a small stream, each byte flipped in turn: a result or an error).
- [ ] **Step 2: Run** `swift test --filter InflateTests`. Expected: FAIL.
- [ ] **Step 3: Implement** with canonical Huffman tables (fast lookup plus a slow path), bounds checked in every path, no recursion.
- [ ] **Step 4: Run** the filter, and on Linux: `XP_TRACK=mi-2 scripts/linux-test.sh test --filter InflateTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mesh): our own inflate, on every platform`.

### Task 9: The zip reader on any platform and any file

**Files:** Modify `Sources/CreatorImplicit/Export/ZipReader.swift`. Test `Tests/CreatorImplicitTests/ZipReaderForeignTests.swift`.

**Interfaces, produces:** `ZipReader(data: Data)` over the file's bytes; `content(of: Entry, limit: Int) throws -> Data`, which refuses a declared size above `limit` before allocating and uses `Inflate`, on every platform; the CRC is still checked. Entries with data descriptors, as other tools write, read from the central directory. Keep the existing API for the tests that use it.

- [ ] **Step 1: Write the failing tests.** `aForeignZipReads` (deflated, with a data descriptor, carried as bytes); `aDeclaredSizeOverTheLimitIsRefusedBeforeAllocating`; `aZip64EntryReads`; `aBadCRCIsRefused`; `aCentralDirectoryPointingOutsideTheFileIsRefused`; `overlappingEntriesAreRefused`; `encryptedEntriesAreRefused` (flag bit 0).
- [ ] **Step 2: Run** `swift test --filter ZipReaderForeignTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the filter and `swift test --filter 'ThreeMFWriterTests|StreamingMesherTests'`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mesh): the zip reader reads other tools' zips`.

### Task 10: The 3MF reader

**Files:** Create `Sources/CreatorImplicit/Import/XMLScanner.swift`, `ThreeMFReader.swift`. Test `Tests/CreatorImplicitTests/ThreeMFReaderTests.swift`, `XMLScannerTests.swift`.

**Interfaces, produces:**
- `struct XMLScanner` over `UnsafeRawBufferPointer`, yielding start and end elements with attributes as byte slices, no allocation per element. Refuses `DOCTYPE`; handles comments, CDATA, processing instructions, namespaces as literal prefixes and the five predefined entities plus numeric ones.
- `enum ThreeMFReader { static func read(_ data: Data, isCancelled: () -> Bool) throws -> [ImportedMesh] }`: one per build item.
- New `MeshImportProblem` cases and copy: `noModelPart` "This 3MF has no 3D model part."; `otherFiles` "This 3MF keeps parts in other files, which isn't supported. Export it as a generic 3MF."; `encrypted` "This 3MF is encrypted."; `malformedModel(String)` "This 3MF is damaged: …".
- Warning: "This mesh's color and material data was ignored." when `ignoredExtras`.

- [ ] **Step 1: Write the failing tests.** Round trip through `ThreeMFWriter`: same vertices and triangle set; agreement with `ThreeMFReading` (the `XMLParser` oracle) where available. By hand: `theModelIsFoundThroughRels`; `eachUnitConverts` (micron, millimeter, centimeter, inch, foot, meter); `buildTransformsApply`; `componentTransformsCompose`; `aMirrorKeepsItRightSideOut` (a negative determinant: still closed and positive volume); `eachBuildItemIsItsOwnMesh`; `anEmptyBuildHoldsNoTriangles`; `coloursAndMaterialsAreIgnoredWithAWarning`; `aProductionPathIsRefused` (`p:path`). Hostile: `nestedComponentsAreCountedBeforeInstancing` (ten levels of ×10 over one triangle: `.tooManyTriangles` with memory bounded); `aCycleIsRefused`; `depth33IsRefused`; `aDoctypeIsRefused`; `anIndexOutOfRangeIsRefused`; `aNonFiniteVertexIsRefused`; `aModelEntryOver2GBIsRefused`.
- [ ] **Step 2: Run** `swift test --filter 'ThreeMFReaderTests|XMLScannerTests'`. Expected: FAIL.
- [ ] **Step 3: Implement.** Resolve `_rels/.rels` for the start part; count the triangles of the instanced tree before instantiating anything; weld each mesh with `ExactWeld`; reverse winding at a negative determinant.
- [ ] **Step 4: Run** the filter. Expected: PASS.
- [ ] **Step 5: Commit** `feat(mesh): read 3MF`.

### Task 11: 3MF in the node and app, and MI-2's PR

**Files:** `ImportMeshNode.swift`, `ImportedMeshCache.swift` (holds `[ImportedMesh]`), `ImportUnits.swift`, `AppModel+MeshFiles.swift`, CLAUDE.md, human checks.

- [ ] **Step 1: Write the failing tests** in the existing suites. `a3MFGivesAListOfMeshes`; `fromFileUsesThe3MFsUnit`; `anExplicitUnitOverridesIt`; `aZipIsDetectedByItsBytes` (a `.stl`-named zip reads as 3MF; `PK\x03\x04` decides); `thePanelOffers3MF`; `aMeshDigestIsPinned` (each fixture's SHA-256 over positions and triangles, on all three platforms).
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** A full 3MF export of an imported 3MF keeps one object per mesh.
- [ ] **Step 4: Verify** as Task 7 Step 2 with `XP_TRACK=mi-2`, and confirm in CI that the Windows job's pinned digests match.
- [ ] **Step 5: Commit** `feat(mesh): 3MF through the node and the app`; update records and remove the MI-2 marks; open the PR; merge when CI is green.

---

## MI-3: Measure and record

### Task 12: Benchmarks and the limit

**Files:** Create `Tests/CreatorAppTests/Bench/MeshImportBench.swift`. Modify `docs/verification/performance.md`, CLAUDE.md, `docs/superpowers/specs/2026-11-01-zebra-design.md`, `2026-11-01-g2-surfacing-design.md`, `2026-10-13-implicit-lattices-design.md`.

- [ ] **Step 1:** Rows `mesh-import-1` to `-3`: 1,000,000 triangles of binary STL, ASCII STL and 3MF, read to first display. Print `BENCH` lines; `.enabled(if: Bench.isRequested)`.
- [ ] **Step 2:** `scripts/bench.sh MeshImportBench`. Record the numbers; on a loaded Mac, record them as saturated. Targets, on an idle Mac: binary under 1 s, 3MF under 3 s. Also read a 10,000,000-triangle binary STL and draw it: if that is unusable on this Mac, lower `maxTriangles` and its copy, and say why in the spec.
- [ ] **Step 3:** Mark the Later and non-goal lines in the three specs as done, pointing here. Finish CLAUDE.md.
- [ ] **Step 4:** Commit `docs(mesh): measure import; records`, open the PR, merge when CI is green.
