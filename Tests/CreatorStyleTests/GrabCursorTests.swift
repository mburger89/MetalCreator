@testable import CreatorStyle
import MetalUI
import Testing

/// The closed hand: the system's on macOS, a drawn bitmap on SDL (MetalUI S4 ships image cursors but no art; gap XP-G8).
@MainActor
struct GrabCursorTests {
    @Test func macOSKeepsTheSystemClosedHand() {
        #expect(GrabCursor.pointerStyle(drawnHand: false) == .grabActive)
        #if os(macOS)
        #expect(!GrabCursor.needsDrawnHand)
        #expect(GrabCursor.pointerStyle() == .grabActive)
        #endif
    }

    @Test func sdlGetsAnImageCursorWhichIsTheSameValueEveryTimeItIsAsked() {
        let drawn = GrabCursor.pointerStyle(drawnHand: true)
        #expect(drawn != .grabActive)
        #expect(drawn == GrabCursor.pointerStyle(drawnHand: true), "one bitmap, so one cursor to the platform")
        #if os(Linux) || os(Windows)
        #expect(GrabCursor.needsDrawnHand)
        #expect(GrabCursor.pointerStyle() == drawn)
        #endif
    }

    @Test func theHandIsA24PointBitmapWithAnOutlineAndAWhiteFistAndTransparentCorners() {
        let side = GrabCursor.side, rgba = HandArt.rgba(side: side)
        #expect(rgba.count == side * side * 4)
        func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(rgba[((y * side + x) * 4)..<((y * side + x) * 4 + 4)]) }
        #expect(pixel(0, 0)[3] == 0 && pixel(side - 1, side - 1)[3] == 0, "corners are transparent")
        #expect(pixel(24, 28) == [255, 255, 255, 255], "the palm is opaque white")
        let rim = (0..<side).compactMap { y in (0..<side).map { pixel($0, y) }.first { $0[3] == 255 || ($0[3] > 0 && $0[0] < 255) } }
        #expect(rim.contains { $0[0] < 128 && $0[3] > 128 }, "the outline is dark")
    }
}
