import CreatorGeometry

extension EditorModel {
    /// A middle-button drag over the canvas moved (`GraphPanelInput.middlePanGesture()`; the user's Gate G answer (b),
    /// 2026-10-09: a plain drag box-selects, so the pan is the middle button's and two-finger scroll's). `start` and
    /// `location` are canvas-local screen points. It pans wherever it starts, nodes included: the canvas follows the
    /// pointer from its offset at the press, closed hand and all (`canvasCursor`), and nothing is selected, moved or
    /// edited. As the viewport's middle drag (VC3, `ViewportModel.dragChanged`): a value whose press began during a
    /// primary press is ignored (MetalUI ignores that press, `CI-AA` item 4), a primary press ends the pan
    /// (`pointerPressed`) and the rest of its press is then ignored. A pan MetalUI drops without a release arrives as
    /// `middleCancelled()`, and a value of another press starts a new pan in any case.
    public func middleDragged(from start: Vector2, to location: Vector2) {
        if middlePanStart != start {
            guard currentPress == nil else { return }
            middlePanStart = start
            setInteraction(.panning(startOffset: transform.offset))
        }
        guard case .panning(let startOffset)? = interaction, location.isFinite else { return }
        let panned = CanvasTransform(offset: startOffset + (location - start), zoom: transform.zoom)
        if panned != transform { transform = panned }
    }

    /// MetalUI dropped the middle drag without a release (`onCancelled`, C16: another press replaced it, or the release
    /// went unseen; docs/metalui-gaps.md VI-a): the pan ends where it was, and the closed hand goes with it.
    public func middleCancelled() {
        middlePanStart = nil
        if case .panning? = interaction { setInteraction(nil) }
    }

    /// The middle button was released at `location`: the pan ends there.
    public func middleReleased(from start: Vector2, at location: Vector2) {
        middleDragged(from: start, to: location)
        guard middlePanStart == start else { return }
        middlePanStart = nil
        if case .panning? = interaction { setInteraction(nil) }
    }
}
