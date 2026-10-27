import CreatorGeometry
import Foundation
import MetalUI

/// The value box (spec §7): opened on a dimension's text, it edits a draft and changes nothing until `submitValueBox()`.
extension ViewportModel {
    /// The box's room beyond its text, its least width and its height, in points.
    static let valueBoxPadding = 16.0, valueBoxMinimumWidth = 72.0, valueBoxHeight = 22.0

    /// Opens the box for the dimension `id`, selecting its value. `false`, and no box, when the dimension is not shown, the editor
    /// is gone or finds it not editable, or the open box is being checked. Another open box is replaced.
    @discardableResult
    public func openValueBox(for id: OverlayDimensionID) -> Bool {
        guard valueBox?.isChecking != true, dimensions.contains(where: { $0.id == id }),
              let content = dimensionEditor?.valueBoxContent(for: id) else { return false }
        let text = content.text
        valueBox = DimensionValueBox(id: id, draft: text, opening: text,
                                     selection: TextSelection(range: text.startIndex..<text.endIndex), note: content.note)
        valueBoxAnchor = drawnDimensions.first { $0.id == id }.map { ValueBoxAnchor(origin: $0.textOrigin, size: $0.textSize) }
        valueBoxGeneration += 1
        return true
    }

    /// The field's text changed. Only the draft changes: nothing is solved or evaluated while typing.
    public func valueBoxDraftChanged(_ text: String) {
        guard valueBox?.isChecking == false, valueBox?.draft != text else { return }
        valueBox?.draft = text
    }

    public func valueBoxSelectionChanged(_ selection: TextSelection?) {
        guard valueBox?.isChecking == false, valueBox?.selection != selection else { return }
        valueBox?.selection = selection
    }

    /// Return: commits the draft once. An untouched draft closes the box and commits nothing. Otherwise the box is checking until the
    /// editor answers: accepted closes it, refused keeps it open with the message. An answer for a box that has since closed (or
    /// been replaced) changes nothing.
    public func submitValueBox() async {
        guard let box = valueBox, !box.isChecking else { return }
        guard box.draft != box.opening else {
            closeValueBox()
            return
        }
        guard let editor = dimensionEditor else { return }
        let generation = valueBoxGeneration
        valueBox?.isChecking = true
        valueBox?.message = nil
        let outcome = await editor.commitValue(box.draft, to: box.id)
        guard valueBox?.id == box.id, valueBoxGeneration == generation else { return }
        switch outcome {
        case .accepted:
            closeValueBox()
        case .refused(let message):
            valueBox?.message = message
            valueBox?.isChecking = false
        }
    }

    /// Esc: closes the box with no change. A box being checked stays until the answer.
    public func cancelValueBox() {
        guard valueBox?.isChecking == false else { return }
        closeValueBox()
    }

    /// The field lost focus: cancels, unless a commit is being checked.
    public func valueBoxLostFocus() {
        cancelValueBox()
    }

    /// The box on screen, centred on its dimension's text box (where it was last drawn when it is not drawn now): the draft's
    /// measured width rounded up plus the padding, at least `valueBoxMinimumWidth`, `valueBoxHeight` high.
    public func placedValueBox(measuring measure: TextMeasure) -> PlacedValueBox? {
        guard let box = valueBox else { return nil }
        if valueBoxAnchor == nil {
            let camera = DimensionCamera(pose: pose, size: viewSize)
            valueBoxAnchor = dimensions.first { $0.id == box.id }
                .flatMap { DimensionLayout.place($0, style: dimensionStyle, camera: camera, measure: measure) }
                .map { ValueBoxAnchor(origin: $0.textOrigin, size: $0.textSize) }
        }
        guard let anchor = valueBoxAnchor else { return nil }
        let width = max(measure(box.draft).width.rounded(.up) + Self.valueBoxPadding, Self.valueBoxMinimumWidth)
        let size = ViewportSize(width: width, height: Self.valueBoxHeight)
        let origin = ScreenPoint(anchor.origin.x + (anchor.size.width - width) / 2,
                                 anchor.origin.y + (anchor.size.height - size.height) / 2)
        return PlacedValueBox(box: box, origin: origin, size: size)
    }

    /// Closes the box whatever it is doing.
    func closeValueBox() {
        valueBox = nil
        valueBoxAnchor = nil
        valueBoxGeneration += 1
    }
}
