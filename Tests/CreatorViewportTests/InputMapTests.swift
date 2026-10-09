import MetalUI
import Testing
@testable import CreatorViewport

struct InputMapTests {
    @Test func plainDragOrbitsShiftPansOptionZooms() {
        #expect(ViewportInputMap.dragMode(for: []) == .orbit)
        #expect(ViewportInputMap.dragMode(for: .shift) == .pan)
        #expect(ViewportInputMap.dragMode(for: .option) == .zoom)
        #expect(ViewportInputMap.dragMode(for: [.shift, .option]) == .pan)
        #expect(ViewportInputMap.dragMode(for: .command) == .orbit)
    }

    @Test func theRightButtonOrbitsAndTheMiddleButtonPans() {
        #expect(ViewportInputMap.dragMode(for: [], button: .secondary) == .orbit)
        #expect(ViewportInputMap.dragMode(for: .shift, button: .secondary) == .orbit)
        #expect(ViewportInputMap.dragMode(for: [], button: .middle) == .pan)
        #expect(ViewportInputMap.dragMode(for: .option, button: .middle) == .pan)
        #expect(ViewportInputMap.dragMode(for: .option, button: .primary) == .zoom)
    }

    @Test func viewportButtonsAreMetalUIButtons() {
        #expect(ViewportPointerButton.primary.mouseButton == .primary)
        #expect(ViewportPointerButton.secondary.mouseButton == .secondary)
        #expect(ViewportPointerButton.middle.mouseButton == .middle)
    }

    @Test func scrollEventsMapToZoomPhases() {
        func phase(_ phase: InputPhase, momentum: InputPhase = .none) -> ViewportScrollPhase {
            ViewportScrollPhase(ScrollEvent(position: Point(x: Pixels(0), y: Pixels(0)), delta: Point(x: Pixels(0), y: Pixels(4)),
                                            phase: phase, momentumPhase: momentum, isPrecise: true, timestamp: 0))
        }
        #expect(phase(.none) == .step, "a wheel mouse has no phase")
        #expect(phase(.mayBegin) == .moving)
        #expect(phase(.began) == .moving)
        #expect(phase(.changed) == .moving)
        #expect(phase(.ended) == .ended)
        #expect(phase(.cancelled) == .ended)
        #expect(phase(.none, momentum: .began) == .momentum)
        #expect(phase(.none, momentum: .changed) == .momentum)
        #expect(phase(.none, momentum: .ended) == .momentum)
    }

    @Test func metalUIModifiersConvert() {
        #expect(ViewportModifiers(Modifiers([.shift, .option])) == [.shift, .option])
        #expect(ViewportModifiers(Modifiers.command) == .command)
        #expect(ViewportModifiers(Modifiers.control) == .control)
        #expect(ViewportModifiers(Modifiers()) == [])
    }

    @Test func keyBindingsAreValidMetalUIKeystrokes() {
        #expect(ViewportInputMap.keyBindings.count == 5)
        #expect(ViewportInputMap.keyBindings.filter { $0.command == .zoomIn }.map(\.spelling) == ["=", "shift-+", "+"],
                "the main row's = and Shift-=, and the keypad's +")
        for binding in ViewportInputMap.keyBindings {
            #expect(Keystroke(binding.spelling) != nil, "\(binding.spelling) is not a MetalUI keystroke")
        }
        #expect(Set(ViewportInputMap.keyBindings.map(\.command)) == Set(ViewportKeyCommand.allCases))
    }

    @Test func screenPointsConvertFromMetalUIPoints() {
        #expect(ScreenPoint(Point(x: Pixels(12.5), y: Pixels(-3))) == ScreenPoint(12.5, -3))
        #expect((ScreenPoint(4, 6) - ScreenPoint(1, 2)).length == 5)
    }

    @Test func sizesUnderOnePointOrNotFiniteAreEmpty() {
        #expect(ViewportSize(width: 0, height: 0).isEmpty)
        #expect(ViewportSize(width: 200, height: 0.5).isEmpty)
        #expect(ViewportSize(width: .infinity, height: 10).isEmpty)
        #expect(ViewportSize(width: .nan, height: 10).isEmpty)
        let size = ViewportSize(width: 400, height: 200)
        #expect(!size.isEmpty)
        #expect(size.aspect == 2)
        #expect(size.center == ScreenPoint(200, 100))
        #expect(ViewportSize(width: 0, height: 0).aspect == 1)
    }
}
