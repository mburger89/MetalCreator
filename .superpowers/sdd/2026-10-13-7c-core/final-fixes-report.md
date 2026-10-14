# 7c-core final fixes

HEAD: 99feac3 (commits 6ff8dba Place, 99feac3 export cancel). swiftlint --strict: 0 violations. Full `swift test`: exit 0, 12 "Test run with" lines, no "recorded an issue" / "failed after".

## Finding 2: Place drops implicits when the tool list is empty
Fix: PlaceNode.evaluate sets `solids` to the empty tree and continues to the implicit branch.
RED: new test `anEmptyToolListStillPlacesAWiredImplicit` failed (implicits count nil) with the fix stashed; GREEN: PlaceImplicitTests 6/6.

## Finding 1: cancelled export can still write the STL
Fix: `ExportRun.onCancel` has a didSet that replays a Cancel already pressed; exportMeshes returns without writing if `run.isCancelling` / task cancelled after evaluation, after each solid tessellation, and before the write.
Tests: ExportRunTests (replay before onCancel set; single call after set).
Ruling: no deterministic end-to-end "cancel after evaluation, no file" test was added; that instant cannot be hit without a test seam in the evaluator, which would be production code for tests only. The replay unit test covers the lost-early-cancel path, the guards are direct, and ExportSheetWindowTests still covers Cancel leaving no file.
