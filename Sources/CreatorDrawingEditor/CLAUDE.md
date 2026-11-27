# CreatorDrawingEditor

Notes for this module, moved from the root `CLAUDE.md` (which Claude Code loads in every session) so they load only when work touches this folder. The project-wide rules, commands and toolchain notes stay in the root file.

- `CreatorDrawingEditor`: the drawing editor. `@MainActor @Observable DrawingEditorModel` holds the open sheet, tool, selection, hover and canvas transform and turns gestures into `DrawingCommit`s (DR-2: the annotation tools, picking, selection, `remembered` last values and re-attaching) (the whole drawing document, as a `SketchCommit` carries the whole sketch) through `events.committed`, which the app stores with one `.setDrawings` step; MetalUI views in `Views/` (`SheetCanvas`, `SheetViewLayer` and `SheetFrameLayer` `.equatable()`, `SheetTextView`, `SheetTabs`, `DrawingToolbar`, `DrawingInspector`; `Templates/` holds `DrawingTemplateFolder` and `DrawingTemplateStore`; `DrawingClipboard` is the in-memory clipboard of ⌘C, ⌘X and ⌘V). Depends on CreatorDrawing, CreatorKernel, CreatorGeometry, CreatorStyle and MetalUI only, never CreatorGraph. Tests: `swift test --filter CreatorDrawingEditorTests`.

Drawings speed (linework memo): `DrawingEditorModel.linework` is a `LineworkMemo` passed to `SheetComposer.compose` in `rebuildPicture`, so a drag of an annotation re-maps no view; `lineworkMapped` is a running total of views mapped, read by `DragWorkTests`.

Also read:

@../CreatorDrawing/CLAUDE.md
