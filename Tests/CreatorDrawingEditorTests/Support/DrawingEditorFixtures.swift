import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// What a model reported, in order.
@MainActor
final class EditorLog {
    var commits: [DrawingCommit] = []
    var sheets: [SheetID?] = []
}

/// A model over a document with a log of its events; sources and contents are fakes, no kernel.
@MainActor
struct EditorHarness {
    let model: DrawingEditorModel
    let log: EditorLog
    let sources: [DrawingSourceOption]

    /// A rectangle of `width` by `height` model millimetres, drawn as four sharp visible lines.
    static func rectangle(_ width: Double, _ height: Double) -> ViewContent {
        let a = Vector2(0, 0), b = Vector2(width, 0), c = Vector2(width, height), d = Vector2(0, height)
        let lines = [(a, b), (b, c), (c, d), (d, a)].map {
            ProjectedLine(visibility: .visible, lineClass: .sharp, curve: .line($0.0, $0.1), source: nil)
        }
        return ViewContent(projection: Projection2D(lines: lines))
    }

    static func sources(count: Int = 2) -> [DrawingSourceOption] {
        (0..<count).map {
            DrawingSourceOption(
                id: NodeID(), name: "Output \($0 + 1)",
                bounds: BoundingBox(min: Vector3(0, 0, 0), max: Vector3(100, 50, 30)))
        }
    }

    init(
        document: DrawingDocument, sheet: SheetID?, units: DocumentUnits = .millimetres, today: String = "2026-11-24",
        sources: [DrawingSourceOption] = EditorHarness.sources(), contents: [ViewID: ViewContent]? = nil
    ) {
        let log = EditorLog()
        self.log = log
        self.sources = sources
        model = DrawingEditorModel(
            document: document, sheet: sheet, units: units, today: { today },
            events: DrawingEditorEvents(
                committed: { log.commits.append($0) }, sheetChanged: { log.sheets.append($0) }))
        model.sources = sources
        model.visibleRect = Rect2D(min: .zero, max: Vector2(1000, 600))
        model.canvasSize = Vector2(1000, 600)
        if let contents {
            model.contents = contents
        } else if let current = document.sheets.first(where: { $0.id == sheet }) {
            model.contents = Dictionary(uniqueKeysWithValues: current.views.map { ($0.id, Self.rectangle(50, 30)) })
        }
    }

    /// Canvas point of a sheet point.
    func canvas(_ x: Double, _ y: Double) -> Vector2 { model.transform.screenPoint(Vector2(x, y)) }

    func click(_ x: Double, _ y: Double, _ modifiers: SheetModifiers = []) {
        model.pointerDown(at: canvas(x, y), modifiers: modifiers)
        model.pointerUp(at: canvas(x, y))
    }
}

enum EditorDocuments {
    static func view(
        at center: Vector2, source: NodeID = NodeID(), orientation: StandardOrientation = .front
    ) -> DrawingView {
        DrawingView(kind: .base, source: source, orientation: .standard(orientation), center: center)
    }

    static func child(of parent: DrawingView, axis: AlignmentAxis, at center: Vector2) -> DrawingView {
        DrawingView(
            kind: .projected, source: parent.source, orientation: .standard(.right), center: center,
            alignment: ViewAlignment(parent: parent.id, axis: axis))
    }

    static func document(
        _ sheets: [DrawingSheet], settings: DrawingSettings = DrawingSettings()
    ) -> DrawingDocument {
        DrawingDocument(settings: settings, sheets: sheets)
    }
}
