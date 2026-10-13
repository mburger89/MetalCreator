import CreatorGeometry
import CreatorGraph
import Testing
@testable import CreatorEditor

/// The comment views and the wire read no environment, so `==` can decide whether `.equatable()` skips them (C14).
/// Each input is changed alone and must make the view unequal (`expectEqualityCovers`).
@MainActor
struct CommentViewEqualityTests {
    let rect = CanvasRect(origin: .zero, size: Vector2(200, 120))
    var moved: CanvasRect { CanvasRect(origin: Vector2(1, 0), size: rect.size) }

    @Test func aFrameIsEqualOnlyWhenEveryInputIs() {
        let box = CommentFrame(title: "Frame", frame: rect)
        var renamed = box
        renamed.title = "Other"
        expectEqualityCovers(CommentFrameView(box: box, rect: rect, isSelected: false, palette: .dracula),
                             equalTo: CommentFrameView(box: box, rect: rect, isSelected: false, palette: .dracula), [
            "box": CommentFrameView(box: renamed, rect: rect, isSelected: false, palette: .dracula),
            "rect": CommentFrameView(box: box, rect: moved, isSelected: false, palette: .dracula),
            "isSelected": CommentFrameView(box: box, rect: rect, isSelected: true, palette: .dracula),
            "palette": CommentFrameView(box: box, rect: rect, isSelected: false, palette: Palette(.alucard)),
            "isGhost": CommentFrameView(box: box, rect: rect, isSelected: false, palette: .dracula, isGhost: true),
        ])
    }

    @Test func aNoteIsEqualOnlyWhenEveryInputIs() {
        let note = StickyNote(text: "Hi", frame: rect)
        var edited = note
        edited.text = "Hello"
        expectEqualityCovers(StickyView(note: note, rect: rect, isSelected: false, palette: .dracula),
                             equalTo: StickyView(note: note, rect: rect, isSelected: false, palette: .dracula), [
            "note": StickyView(note: edited, rect: rect, isSelected: false, palette: .dracula),
            "rect": StickyView(note: note, rect: moved, isSelected: false, palette: .dracula),
            "isSelected": StickyView(note: note, rect: rect, isSelected: true, palette: .dracula),
            "palette": StickyView(note: note, rect: rect, isSelected: false, palette: Palette(.alucard)),
            "isGhost": StickyView(note: note, rect: rect, isSelected: false, palette: .dracula, isGhost: true),
        ])
    }

    @Test func aHandleAndAWireAreEqualOnlyWhenEveryInputIs() {
        expectEqualityCovers(CommentHandleView(size: rect, palette: .dracula), equalTo: CommentHandleView(size: rect, palette: .dracula), [
            "size": CommentHandleView(size: moved, palette: .dracula),
            "palette": CommentHandleView(size: rect, palette: Palette(.alucard)),
        ])
        let geometry = WireGeometry(from: Vector2(0, 0), to: Vector2(100, 40), flow: .horizontal)
        let color = Palette.dracula.socket(.solid)
        expectEqualityCovers(WireView(geometry: geometry, color: color), equalTo: WireView(geometry: geometry, color: color), [
            "geometry": WireView(geometry: WireGeometry(from: Vector2(0, 0), to: Vector2(101, 40), flow: .horizontal), color: color),
            "color": WireView(geometry: geometry, color: Palette.dracula.socket(.profile)),
            "lineWidth": WireView(geometry: geometry, color: color, lineWidth: 3),
        ])
    }
}
