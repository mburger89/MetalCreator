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
        "d": .dimension, "h": .holeCallout, "m": .centreMark, "l": .centreLine, "n": .note,
    ]

    /// The drawing key a press stands for: F, the tool letters D, H, M, L and N, Delete and ⌫, the arrows (1 mm, 10 with Shift) and Esc.
    static func key(_ key: KeyEquivalent, modifiers: EventModifiers, isRepeat: Bool = false) -> DrawingKey? {
        // A chord with ⌘ (Ctrl elsewhere) or ⌥ belongs to the menus.
        if modifiers.contains(.primary) || modifiers.contains(.control) || modifiers.contains(.option) { return nil }
        if let letter = key.character.lowercased().first, let tool = toolLetters[letter] { return .tool(tool) }
        let step = modifiers.contains(.shift) ? 10.0 : 1.0
        switch key {
        case "f", "F": return .fit
        case .delete, .deleteForward: return .delete
        case .escape: return .escape
        case .leftArrow: return .nudge(Vector2(-step, 0), isRepeat: isRepeat)
        case .rightArrow: return .nudge(Vector2(step, 0), isRepeat: isRepeat)
        case .upArrow: return .nudge(Vector2(0, step), isRepeat: isRepeat)
        case .downArrow: return .nudge(Vector2(0, -step), isRepeat: isRepeat)
        default: return nil
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
