// Test fixture file: sketches and a recording host for the sketch editor's tests.
import CreatorGeometry
import CreatorSketch
@testable import CreatorSketchEditor

/// A 60 × 40 rectangle of four shared-corner lines, held by horizontal and vertical constraints and a fixed corner,
/// with `width` and `height` dimensions: fully constrained when both are driving.
struct RectangleSketch {
    var sketch = Sketch()
    var corners: [SketchEntityID] = []
    var lines: [SketchEntityID] = []
    var width = DimensionID(0)
    var height = DimensionID(0)

    init(dimensioned: Bool = true) {
        corners = [Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)].map { sketch.addPoint($0) }
        lines = (0..<4).map { sketch.addLine(from: corners[$0], to: corners[($0 + 1) % 4]) }
        sketch.add(.horizontal(lines[0]))
        sketch.add(.horizontal(lines[2]))
        sketch.add(.vertical(lines[1]))
        sketch.add(.vertical(lines[3]))
        sketch.add(.fix(corners[0], at: .zero))
        if dimensioned {
            width = sketch.addDimension(.length(lines[0]), value: 60)
            height = sketch.addDimension(.length(lines[1]), value: 40)
        }
    }
}

/// Collects what an editor hands its host.
@MainActor
final class RecordingHost {
    private(set) var commits: [SketchCommit] = []
    private(set) var finishes = 0

    init(_ model: SketchEditorModel) {
        model.events.committed = { [weak self] in self?.commits.append($0) }
        model.events.finished = { [weak self] in self?.finishes += 1 }
    }
}
