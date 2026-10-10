import CreatorGeometry
import CreatorGraph

/// Adding comments (canvas comments spec 2026-10-09 §7): a note at a point, a frame around the selection, from keys
/// and the canvas's context menu. Each is one undo step and leaves the new comment alone selected.
extension EditorModel {
    /// Adds a 160 × 100 note, "Note", muted, with its top-left corner at `screen` (canvas-local screen points) and
    /// selects it, as one undo step. Returns false, having shown the refusal, when the graph refuses it.
    @discardableResult
    public func addNote(atScreen screen: Vector2) -> Bool {
        let display = CanvasRect(origin: transform.toCanvas(screen), size: CommentLayout.noteSize)
        return add(StickyNote(frame: flow.stored(display)))
    }

    /// ⌘⇧N: a note at the pointer when it is over the canvas, else centred on the visible canvas.
    @discardableResult
    public func addNoteAtPointer() -> Bool {
        if let pointerLocation { return addNote(atScreen: pointerLocation) }
        let centre = transform.toCanvas(visibleCanvasSize * 0.5)
        return add(StickyNote(frame: flow.stored(CanvasRect(origin: centre - CommentLayout.noteSize * 0.5,
                                                           size: CommentLayout.noteSize))))
    }

    /// Frame Selection (⌘⇧C): a "Frame" around the selection's bounds, padded 24 points with a 22-point title bar
    /// above, muted; it is selected, as one undo step. Returns false, changing nothing, with nothing selected on the
    /// canvas (which is what disables the menu item).
    @discardableResult
    public func addFrameAroundSelection() -> Bool {
        guard let bounds = bounds(of: canvasSelection) else { return false }
        return add(CommentFrame(frame: flow.stored(CommentLayout.framing(bounds))))
    }

    /// Whether `item` can run now.
    public func isEnabled(_ item: CanvasMenuItem) -> Bool {
        switch item {
        case .addNote: true
        case .frameSelection: bounds(of: canvasSelection) != nil
        }
    }

    /// Runs a context-menu item; `screen` is where the menu opened (`nil` for a keyboard open: the visible centre). It does
    /// nothing while a drag is under way, as the keys do nothing then: the item's edit would split the drag's undo step.
    public func choose(_ item: CanvasMenuItem, at screen: Vector2?) {
        guard interaction == nil else { return }
        switch item {
        case .addNote:
            if let screen { addNote(atScreen: screen) } else { addNoteAtPointer() }
        case .frameSelection:
            addFrameAroundSelection()
        }
    }

    private func add(_ note: StickyNote) -> Bool {
        commit(.setSticky(note), selecting: note.id, named: UndoName.addNote)
    }

    private func add(_ box: CommentFrame) -> Bool {
        commit(.setFrame(box), selecting: box.id, named: UndoName.addFrame)
    }

    private func commit(_ command: GraphCommand, selecting id: CommentID, named name: String) -> Bool {
        do {
            try edit(command, name: name)
            canvasSelection = CanvasSelection(comments: [id])
            return true
        } catch {
            refuse(error.message, node: nil)
            return false
        }
    }
}
