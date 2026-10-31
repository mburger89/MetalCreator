import CreatorKernel
import CreatorViewport

/// The Measure tool in the app (measure spec, part A). It is the viewport's tool while it runs; it excludes the sketch editor and the
/// model dimension tool, and a pick session ends it. It makes no command and marks nothing edited.
extension AppModel {
    /// Starts or ends Measure (the top bar's toggle, View ▸ Measure and M). Refused while a sketch is open or a pick session runs.
    func setMeasure(_ on: Bool) {
        guard on else { return endMeasure() }
        guard sketch == nil, pick == nil, measure == nil else { return }
        editor.commitPendingEntry()
        editor.closePalette()
        endModelDimension()
        let session = MeasureSession(kernel: kernel, viewport: viewport)
        session.overlayChanged = { [weak self, weak session] in
            guard let self, let session, self.measure === session else { return }
            self.showMeasureOverlay()
        }
        session.dimensionsChanged = { [weak self, weak session] in
            guard let self, let session, self.measure === session else { return }
            self.refreshDimensions()
        }
        measure = session
        viewport.tool = session
        showMeasureOverlay()
    }

    /// Ends Measure and gives the viewport back; the viewport's tool is cleared only when it is still this one.
    func endMeasure() {
        guard let session = measure else { return }
        measure = nil
        if viewport.tool === session { viewport.tool = nil }
        showMeasureOverlay()
        refreshDimensions()
    }

    /// The overlay the viewport shows outside sketch mode: the selected layout's placements (nothing while picking), then Measure's.
    func showMeasureOverlay() {
        guard sketch == nil else { return }
        var overlay = pick == nil ? layoutOverlay : ViewportOverlay()
        if let measured = measure?.overlay {
            overlay.lines += measured.lines
            overlay.points += measured.points
            overlay.fills += measured.fills
        }
        if viewport.overlay != overlay { viewport.showOverlay(overlay) }
    }

    /// The measurement's dimensions for the viewport: none while sketching or picking.
    func measureDimensions() -> [OverlayDimension] {
        guard sketch == nil, pick == nil else { return [] }
        return measure?.dimensions(style: viewport.dimensionStyle, units: units) ?? []
    }
}
