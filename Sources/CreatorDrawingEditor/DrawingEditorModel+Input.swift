import CreatorGeometry

extension DrawingEditorModel {
    // The canvas's gestures arrive as one report per change; these turn them into the press, drag and release the model works in.

    /// A change of the primary press-and-drag gesture; the first one is the press.
    public func primaryChanged(to canvas: Vector2, modifiers: SheetModifiers) {
        if pointerIsDown {
            pointerDragged(to: canvas)
        } else {
            pointerIsDown = true
            pointerDown(at: canvas, modifiers: modifiers)
        }
    }

    /// The gesture's end: a release, or a click's only report.
    public func primaryEnded(at canvas: Vector2, modifiers: SheetModifiers) {
        if !pointerIsDown { pointerDown(at: canvas, modifiers: modifiers) }
        pointerIsDown = false
        pointerUp(at: canvas)
    }

    /// MetalUI dropped the press without a release.
    public func primaryCancelled() {
        pointerIsDown = false
        pointerCancelled()
    }

    /// A change of the middle-button drag, `translation` since the press: pans by what is new.
    public func middleChanged(translation: Vector2) {
        let last = middleLast ?? .zero
        middleLast = translation
        middleDragged(by: translation - last)
    }

    public func middleEnded() {
        middleLast = nil
    }

    /// The pointer left the canvas.
    public func pointerLeft() {
        if hoveredStroke != nil { hoveredStroke = nil }
    }

    /// The part of the sheet that shows, in sheet millimetres, grown by 20 % on each side (plan R27).
    var visibleSheetRect: Rect2D {
        let a = transform.sheetPoint(visibleRect.min), b = transform.sheetPoint(visibleRect.max)
        let rect = Rect2D(points: [a, b]) ?? Rect2D(min: a, max: a)
        let grow = 0.2 * Swift.max(rect.width, rect.height)
        return rect.insetBy(-grow)
    }
}
