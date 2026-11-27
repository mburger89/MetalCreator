import CreatorGeometry
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// The canvas's buckets and their revisions (drawings speed R3): a revision moves exactly when a bucket's contents do.
@MainActor
@Suite("Sheet layers")
struct SheetLayersTests {
    /// Two views, a note on the first and a dimension-free second; every bucket is easy to name.
    @MainActor struct Scene {
        let h: EditorHarness
        let a: DrawingView
        let b: DrawingView
        let note: AnnotationID

        var model: DrawingEditorModel { h.model }
        var layers: SheetLayers { model.layers ?? SheetLayers() }
        /// The note, edited: its text and position.
        func setNote(_ text: String, at position: Vector2) {
            var document = model.document
            var annotation = document.sheets[0].annotations[0]
            annotation.kind = .note(DrawingNote(text: text, position: position))
            document.sheets[0].setAnnotation(annotation)
            model.document = document
        }
    }

    private func scene() -> Scene {
        let a = EditorDocuments.view(at: Vector2(100, 100))
        let b = EditorDocuments.view(at: Vector2(250, 100))
        let note = AnnotationID()
        let annotation = DrawingAnnotation(
            id: note, view: a.id, kind: .note(DrawingNote(text: "Plate", position: Vector2(90, 60))))
        let sheet = DrawingSheet(name: "Sheet 1", views: [a, b], annotations: [annotation])
        let h = EditorHarness(
            document: EditorDocuments.document([sheet]), sheet: sheet.id,
            contents: [a.id: EditorHarness.rectangle(40, 20), b.id: EditorHarness.rectangle(40, 20)])
        return Scene(h: h, a: a, b: b, note: note)
    }

    /// Every bucket of `layers` by name.
    private func buckets(_ layers: SheetLayers, _ scene: Scene) -> [String: SheetLayers.Bucket] {
        [
            "frame": layers.frame,
            "linework A": layers.linework(of: scene.a.id), "annotations A": layers.annotations(of: scene.a.id),
            "linework B": layers.linework(of: scene.b.id), "annotations B": layers.annotations(of: scene.b.id),
        ]
    }

    /// The names of the buckets whose revision moved, after checking a revision moves exactly when the contents do.
    private func moved(_ before: SheetLayers, _ after: SheetLayers, _ scene: Scene) -> Set<String> {
        let old = buckets(before, scene), new = buckets(after, scene)
        var names: Set<String> = []
        for (name, bucket) in new {
            let previous = old[name] ?? .empty
            let same = bucket.sameContent(as: previous)
            #expect((bucket.revision == previous.revision) == same, "\(name): its revision moves exactly when its contents do")
            if !same { names.insert(name) }
        }
        return names
    }

    @Test func unchangedBucketsKeepTheirRevision() throws {
        let s = scene()
        let before = s.layers
        #expect(!before.annotations(of: s.a.id).isEmpty, "the note is in its view's annotations bucket")
        s.setNote("Plate", at: Vector2(95, 60))
        let after = s.layers
        #expect(moved(before, after, s) == ["annotations A"], "only the note's view's annotations changed")
        for name in ["frame", "linework A", "linework B", "annotations B"] {
            #expect(buckets(after, s)[name]?.revision == buckets(before, s)[name]?.revision, "\(name) kept its revision")
        }
    }

    @Test func changedBucketsTakeANewRevision() throws {
        let s = scene()
        var before = s.layers
        s.setNote("Bracket", at: Vector2(90, 60))
        #expect(moved(before, s.layers, s) == ["annotations A"], "a note's text change")

        before = s.layers
        s.model.contents[s.b.id] = EditorHarness.rectangle(60, 30)
        #expect(moved(before, s.layers, s) == ["linework B"], "a projection landing")

        before = s.layers
        var document = s.model.document
        var flagged = s.a
        flagged.showsLabel = true
        document.sheets[0].setView(flagged)
        s.model.document = document
        let changed = moved(before, s.layers, s)
        #expect(!changed.isEmpty && !changed.contains("linework B") && !changed.contains("annotations B"), "a view flag: \(changed)")
        #expect(changed.contains("linework A") || changed.contains("annotations A"), "the flagged view redraws: \(changed)")
    }

    @Test func bucketsHoldEverything() throws {
        let s = scene()
        let picture = try #require(s.model.picture)
        let layers = s.layers
        var all = [layers.frame] + s.model.sheet!.views.flatMap { [layers.linework(of: $0.id), layers.annotations(of: $0.id)] }
        all.removeAll { $0.isEmpty }
        func count<T: Hashable>(_ items: [T]) -> [T: Int] { items.reduce(into: [:]) { $0[$1, default: 0] += 1 } }
        #expect(count(all.flatMap(\.strokes)) == count(picture.strokes))
        #expect(count(all.flatMap(\.fills)) == count(picture.fills))
        #expect(count(all.flatMap(\.texts)) == count(picture.texts))
    }

    /// What `SheetCanvas.highlighted(in:)` filtered before the buckets, kept as the reference.
    private func oldFilter(
        _ picture: SheetPicture, annotations chosen: Set<AnnotationID>, marks selected: Set<ViewID>
    ) -> (strokes: [SheetStroke], fills: [SheetFill], texts: [SheetText]) {
        var strokes = picture.strokes.filter { $0.annotation.map(chosen.contains) ?? false }
        var fills = picture.fills.filter { $0.annotation.map(chosen.contains) ?? false }
        var texts = picture.texts.filter { $0.annotation.map(chosen.contains) ?? false }
        strokes += picture.strokes.filter { $0.mark.map(selected.contains) ?? false }
        fills += picture.fills.filter { $0.mark.map(selected.contains) ?? false }
        texts += picture.texts.filter { $0.mark.map(selected.contains) ?? false }
        return (strokes, fills, texts)
    }

    @Test func selectionMatchesTheOldFilter() throws {
        let s = SelectionScene.make([.horizontal, .diameter, .note, .mark])
        let picture = try #require(s.h.model.picture)
        let layers = try #require(s.h.model.layers)
        let everything: Set<AnnotationID> = [
            SelectionScene.horizontal, SelectionScene.diameter, SelectionScene.note, SelectionScene.mark,
        ]
        let selections: [Set<AnnotationID>] = [
            [], [SelectionScene.horizontal], [SelectionScene.note, SelectionScene.diameter], everything, [AnnotationID()],
        ]
        for chosen in selections {
            for marks: Set<ViewID> in [[], [s.view.id]] {
                let want = oldFilter(picture, annotations: chosen, marks: marks)
                let got = layers.selection(annotations: chosen, marks: marks)
                #expect(got.strokes == want.strokes && got.fills == want.fills && got.texts == want.texts)
            }
        }
        let some = layers.selection(annotations: everything, marks: [])
        #expect(!some.strokes.isEmpty && !some.texts.isEmpty, "the reference selection draws something")
    }
}
