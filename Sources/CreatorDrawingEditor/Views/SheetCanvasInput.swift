import CreatorGeometry
import MetalUI

/// MetalUI's pointer, key and scroll values turned into the model's. Pure, so the mapping is tested without a window.
@MainActor
enum SheetCanvasInput {
    static func vector(_ point: Point<Pixels>) -> Vector2 {
        Vector2(Double(point.x.value), Double(point.y.value))
    }

    static func modifiers(_ modifiers: Modifiers) -> SheetModifiers {
        var result: SheetModifiers = []
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.primary) { result.insert(.primary) }
        return result
    }

    /// The letters that choose an annotation tool (plan R17), each with its capital.
    private static let toolLetters: [Character: DrawingTool] = [
        "d": .dimension, "h": .holeCallout, "m": .centreMark, "l": .centreLine, "n": .note, "s": .section, "e": .detail,
        "u": .auxiliaryView, "a": .datum, "g": .featureControlFrame, "r": .surfaceFinish,
        "b": .balloon, "p": .partsList,
    ]

    /// The drawing key a press stands for: F, the tool letters D, H, M, L, N, S, E, U, A, G, R, B and P, Return (finishes a cutting line), Delete and ⌫, the arrows (1 mm, 10 with Shift) and Esc.
    static func key(_ key: KeyEquivalent, modifiers: EventModifiers, isRepeat: Bool = false) -> DrawingKey? {
        // ⌘C, ⌘X and ⌘V (Ctrl elsewhere) are the editor's clipboard; every other chord belongs to the menus.
        if let clipboard = clipboardKey(key, modifiers: modifiers) { return clipboard }
        // A chord with ⌘ (Ctrl elsewhere) or ⌥ belongs to the menus.
        if modifiers.contains(.primary) || modifiers.contains(.control) || modifiers.contains(.option) { return nil }
        if let letter = key.character.lowercased().first, let tool = toolLetters[letter] { return .tool(tool) }
        switch key {
        case "f", "F": return .fit
        case .return: return .finish
        case .delete, .deleteForward: return .delete
        case .escape: return .escape
        default: return arrow(key, step: modifiers.contains(.shift) ? 10.0 : 1.0, isRepeat: isRepeat)
        }
    }

    private static let clipboardLetters: [Character: DrawingKey] = ["c": .copy, "x": .cut, "v": .paste]

    private static func clipboardKey(_ key: KeyEquivalent, modifiers: EventModifiers) -> DrawingKey? {
        guard modifiers.contains(.primary), !modifiers.contains(.option), !modifiers.contains(.shift) else { return nil }
        return key.character.lowercased().first.flatMap { clipboardLetters[$0] }
    }

    private static func arrow(_ key: KeyEquivalent, step: Double, isRepeat: Bool) -> DrawingKey? {
        switch key {
        case .leftArrow: .nudge(Vector2(-step, 0), isRepeat: isRepeat)
        case .rightArrow: .nudge(Vector2(step, 0), isRepeat: isRepeat)
        case .upArrow: .nudge(Vector2(0, step), isRepeat: isRepeat)
        case .downArrow: .nudge(Vector2(0, -step), isRepeat: isRepeat)
        default: nil
        }
    }

    static func primaryGesture(_ model: DrawingEditorModel) -> DragGesture {
        DragGesture(minimumDistance: Pixels(0))
            .onChanged { value in
                model.primaryChanged(to: vector(value.location), modifiers: Self.modifiers(value.modifiers))
            }
            .onEnded { value in
                model.primaryEnded(at: vector(value.location), modifiers: Self.modifiers(value.modifiers))
            }
            .onCancelled { model.primaryCancelled() }
    }

    static func middleGesture(_ model: DrawingEditorModel) -> DragGesture {
        DragGesture(minimumDistance: Pixels(0), button: .middle)
            .onChanged { value in model.middleChanged(translation: vector(value.location) - vector(value.startLocation)) }
            .onEnded { _ in model.middleEnded() }
            .onCancelled { model.middleEnded() }
    }

    static func pinchGesture(_ model: DrawingEditorModel) -> MagnifyGesture {
        MagnifyGesture()
            .onChanged { value in model.pinchChanged(value.magnification, at: vector(value.startLocation)) }
            .onEnded { _ in model.pinchEnded() }
            .onCancelled { model.pinchEnded() }
    }

    static func scrolled(_ event: ScrollEvent, _ model: DrawingEditorModel) -> Bool {
        model.scrolled(by: vector(event.delta), at: vector(event.location), zooming: event.modifiers.contains(.primary))
        return true
    }
}
