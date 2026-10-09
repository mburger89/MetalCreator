import CreatorGeometry
import CreatorSketch
import Foundation
import Observation

/// The sketch editor's state and behaviour (sketcher spec §8), testable without a GPU or a graph: the sketch being
/// edited and its live solve, the tool and what it has drawn so far, the selection, and the edits it hands to its
/// host (`events`). Its views are thin. The host (the app shell) owns it while one Sketch node is being edited,
/// feeds it the node's stored sketch (`reload(_:)`, after undo or redo too), and stores every `SketchCommit` back.
@MainActor
@Observable
public final class SketchEditorModel {
    /// The sketch as the editor shows it: the last stored or committed one, solved and remembered, so its positions
    /// are the ones on screen.
    public internal(set) var sketch: Sketch
    /// The plane the sketch is drawn on, in world space.
    public private(set) var plane: Plane
    /// The live solve of `sketch` (re-run on every edit and every drag step).
    public internal(set) var solution: SketchSolution
    /// A plain-language reason the last command was refused, until the next edit or tool change.
    public internal(set) var refusal: String?
    /// The selected entities (drawn in the selection colour; constraints and dimensions apply to them).
    public internal(set) var selection: Set<SketchEntityID> = []
    /// The entity under the pointer, if any.
    public internal(set) var hovered: SketchEntityID?
    /// The active tool's rubber band.
    public internal(set) var preview = SketchPreview.none
    /// The active tool (`choose(_:)`).
    public internal(set) var tool = SketchTool.line
    /// Whether new geometry is construction geometry (X toggles it).
    public internal(set) var isConstruction = false
    /// What the drawing tool has placed so far.
    var drawState = DrawState.idle
    /// The point being dragged, between a drag's press and its release.
    @ObservationIgnored var dragged: SketchEntityID?
    /// The sketch when the drag began, so a drag that moved nothing records no step.
    @ObservationIgnored var dragOrigin: Sketch?

    @ObservationIgnored public var events = SketchEditorEvents()

    public init(sketch: Sketch, plane: Plane) {
        self.plane = plane
        let solution = SketchSolver.solve(sketch)
        self.solution = solution
        self.sketch = Self.remembering(sketch, solution)
    }

    /// Shows a sketch that came from the host (undo, redo, or a file change), unless it's the one already shown.
    public func reload(_ stored: Sketch, plane newPlane: Plane) {
        if newPlane != plane { plane = newPlane }
        guard stored != sketch else { return }
        let solved = SketchSolver.solve(stored)
        solution = solved
        sketch = Self.remembering(stored, solved)
        selection = selection.filter { sketch.entities[$0] != nil }
        if let hovered, sketch.entities[hovered] == nil { self.hovered = nil }
        // A stroke may hold points the stored sketch no longer has.
        drawState = .idle
        preview = .none
    }

    /// Takes `edited` as the sketch, solved and remembered, and hands it to the host as one undo step.
    func commit(_ edited: Sketch, _ description: String) {
        let solved = SketchSolver.solve(edited)
        let stored = Self.remembering(edited, solved)
        solution = solved
        sketch = stored
        refusal = nil
        events.committed(SketchCommit(sketch: stored, description: description))
    }

    /// `sketch` with `solution` as its warm start when the solve is usable (S4 → S5 handoff: the node then
    /// warm-starts from what the user sees); an unusable solve keeps the sketch as it is.
    static func remembering(_ sketch: Sketch, _ solution: SketchSolution) -> Sketch {
        guard solution.status.isUsable else { return sketch }
        var remembered = sketch
        remembered.remember(solution)
        return remembered
    }
}
