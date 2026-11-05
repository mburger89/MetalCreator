import CreatorGraph
import CreatorKernel
import MetalUI
import Testing
@testable import CreatorApp

/// A long Undo or Redo title gives way first: the Preview menu keeps its width and its chevron, and no text lands on
/// another's (ui-polish finding 3). The glyphs come out of the frame in the bar's left-to-right order, so an overlap shows as
/// an x that steps back.
@MainActor
struct TopBarSqueezeTests {
    private let longName = "Change A Rather Long Input Label For A Very Long Named Socket Indeed"

    /// Two edits and an undo, so both titles are set and the document is edited either way (the name reads the same).
    private func app(longTitles: Bool) async throws -> AppModel {
        let app = await makeApp()
        for _ in 0..<2 {
            try app.document.perform(.setSticky(StickyNote(frame: CanvasRect(origin: .zero, size: .init(10, 10)))),
                                     name: longTitles ? longName : "Move")
        }
        app.undo()
        return app
    }

    private func glyphXs(_ app: AppModel, width: Double) -> [Double] {
        let scene = renderFrame({ ZStack { TopBar(model: app) } }, size: Size(width: Pixels(Float(width)), height: Pixels(100)),
                                scaleFactor: 2, textSystem: testTextSystem(), atlas: GlyphAtlas(width: 1024, height: 1024))
        return scene.glyphs.map { Double($0.bounds.origin.x) / 2 }
    }

    @Test func theTitlesAreLongHere() async throws {
        let app = try await app(longTitles: true)
        #expect(app.undoTitle == "Undo " + longName && app.redoTitle == "Redo " + longName)
    }

    @Test(arguments: [1440.0, 1100, 1000])
    func longTitlesNeverLandOnTheMenuOrEachOther(width: Double) async throws {
        let xs = glyphXs(try await app(longTitles: true), width: width)
        let steps = zip(xs, xs.dropFirst()).filter { $1 < $0 - 0.5 }.count
        #expect(steps == 0, "glyphs step back \(steps) times at \(width) pt")
    }

    @Test(arguments: [1440.0, 1100, 1000])
    func thePreviewMenuKeepsItsWidthAndChevron(width: Double) async throws {
        // The name's glyphs end at the first big step; the menu's 13 ("Final preview" and the chevron) follow. However
        // long the titles are, they sit exactly as they do with short ones.
        func menu(_ xs: [Double]) -> [Double] {
            let start = xs.indices.dropFirst().first { xs[$0] - xs[$0 - 1] > 50 } ?? 0
            let run = xs.dropFirst(start).prefix(13)
            return run.map { $0 - (run.first ?? 0) }
        }
        let short = menu(glyphXs(try await app(longTitles: false), width: width))
        let long = menu(glyphXs(try await app(longTitles: true), width: width))
        #expect(short.count == 13 && long.count == 13)
        // Within a point: glyphs sit on the pixel grid of wherever the run starts.
        #expect(zip(short, long).allSatisfy { abs($0 - $1) <= 1.5 }, "\(short) against \(long)")
    }
}
