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
